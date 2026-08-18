--======================================================================
-- BakeryQuest_AllInOne.client.lua  (LocalScript, per-player)
--======================================================================
-- "THE GREAT BAKE-OFF" -- ISLAND 15. Two recipes, one chicken, zero patience.
--
--   1  TALK     The Baker gives you the quest and shows two recipe cards:
--                 BROWNIE  -- 3 Cocoa, 2 Sugar, 1 Butter, 2 Eggs
--                 BROOKIE  -- 2 Cocoa, 2 Dough, 2 Sugar, 1 Butter, 2 Eggs
--   2  GATHER   Cocoa / Sugar / Butter / Dough are scattered around the island.
--               EGGS come from the CHICKEN: tap it, it squawks, hops, lays an
--               egg behind itself and scurries off. Tap it again for more.
--   3  MIX      Bring everything to the giant mixing bowl (built on your
--               "Mixer" part). The ingredients pour in one by one, then you
--               STIR -- press the prompt 8 times, the spoon sweeps, the batter
--               darkens -- and out comes a baking pan, carried in your hands.
--   4  BAKE     Walk the pan to EITHER oven (built on your two "Oven" parts).
--               The pan slides in, the door shuts -- and the OVEN HUD opens:
--               heat drains, the STOKE THE FIRE button throws it back, and the
--               bake fills fast only while the needle holds the orange sweet
--               zone. Glow and chimney smoke track the fire. DING! -- the door
--               opens and a finished tray slides onto the rack.
--   5  DELIVER  Carry the tray back to the Baker. Coins, fireworks, done.
--   *  BONUS    Talk to him again afterward and he offers the OTHER recipe
--               for a second, smaller reward. Both recipes get baked.
--
-- WHAT THE WORLD PROVIDES (names ignore case/spaces/underscores):
--   Mixer        x1   a plain block. The mixing station is BUILT on it.
--   Oven         x2   plain blocks. A brick oven is BUILT on each.
--   ChickenPart  x1   a plain block. The chicken spawns here and wanders
--                     around it. The block itself is hidden.
--   (optional) any model with "npc" in its name near the Mixer becomes the
--   quest giver; with none there, a Baker is BUILT beside the station.
--
-- ONLY THE MIXER IS REALLY REQUIRED. It is what decides where the bakery IS, so a world
-- without one gets a warning and no quest. Everything else the scanner can stand in for:
-- a missing oven and -- above all -- a missing chicken are built beside the mixing station
-- ~40s after it goes up. No chicken means no eggs means the Bake-Off cannot be finished at
-- all, which is far worse than an oven sitting somewhere the builder did not choose.
--
-- AUDIO: the SOUND_ block below. Three ids already proven elsewhere in this place are filled
-- in; the rest are "" and silent until you paste your own owned ids in. An empty id creates
-- no Sound whatsoever, so silence never costs anything and never spams the auth log.
--
-- Everything is client-side and per-player, like every other island quest.
-- STREAMING-SAFE: island 15 is far from spawn, so the marker parts trickle
-- in late -- the scanner below keeps looking and builds each station the
-- moment its marker appears. Positions are cached, so a marker streaming
-- back OUT afterwards breaks nothing.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local SoundService      = game:GetService("SoundService")
local TextChatService   = game:GetService("TextChatService")
local PromptService     = game:GetService("ProximityPromptService")
local UserInputService  = game:GetService("UserInputService")   -- the mixing bowl is dragged

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- bump this whenever the file changes: Rojo only ADDS, so a stale copy baked into the place
-- runs alongside the synced one, and the version line is how the boot log tells you which is
-- which. Two "[Bakery] >>> VERSION" lines with different tags = a duplicate to delete.
print("[Bakery] >>> VERSION bakeoff-v3 (3 hens in a pen, station HUDs, big edge-reach prompts) loaded <<<")

-- ============================================================================
-- THE GAME'S OWN BOTTOM HUD, OUT OF THE WAY
-- ============================================================================
-- Every station panel here is a task you play with your thumbs, and the fart meter and its
-- button sit exactly where those panels' buttons are. Same shape the rest of the realm uses
-- (Campfire / CrateClient / MainMenuManager.setHud): remember what was Enabled, switch it off,
-- and put it back EXACTLY as it was. Never blanket-enable on the way out -- that would light up
-- a HUD something else had deliberately hidden.
--
-- REFCOUNTED BY TAG, because these panels overlap: an egg lift can run with the oven HUD still
-- up behind it, and whichever closed first would otherwise hand the bottom HUD back underneath
-- the other one. The state is captured on the FIRST hold and restored only when the LAST one
-- lets go.
local bottomHudHold
do
	local NAMES = { "BottomStackGui", "GasMeterGui", "FartButtonGui", "StomachGui" }
	local held, prev = {}, nil
	function bottomHudHold(tag, hidden)
		held[tag] = hidden or nil
		local any = next(held) ~= nil
		if any and not prev then
			prev = {}
			for _, n in ipairs(NAMES) do
				local sg = PlayerGui:FindFirstChild(n)
				if sg and sg:IsA("ScreenGui") then prev[n] = sg.Enabled; sg.Enabled = false end
			end
		elseif not any and prev then
			for n, was in pairs(prev) do
				local sg = PlayerGui:FindFirstChild(n)
				if sg and sg:IsA("ScreenGui") then sg.Enabled = was end
			end
			prev = nil
		end
	end
end

-- ============================================================================
-- CONFIG
-- ============================================================================
local MIXER_NAME    = "mixer"        -- exact names after norm() -- see below
local OVEN_NAME     = "oven"
local CHICKEN_NAME  = "chickenpart"
local ZONE_NAME     = "chickenzone"  -- ISLAND 15'S BASE PLATE. The name says "pen" but the
                                     -- part is the island's 300x357 base slab, so it is the
                                     -- floor AND the footprint for everything the quest
                                     -- builds: stations, ingredients, the Baker, the chicken,
                                     -- her nest and every egg all seat on its top surface and
                                     -- are clamped inside its edges. No such part -> ground
                                     -- raycasts and the old home-radius wander.
local ISLAND_PREFIX = "island15"     -- Baker parents under this model if it exists,
                                     -- so the NPC guide arrows can find him
local MARKER_RANGE  = 800            -- an Oven/ChickenPart must be this close to the
                                     -- Mixer to count as island 15's, so a same-named
                                     -- part on another island is never grabbed
local NPC_MAX_DIST  = 150            -- an existing *npc* model this close to the Mixer
                                     -- becomes the quest giver instead of the built Baker
local TALK_DIST     = 12
local BANNER_RANGE  = 420            -- objective banner shows only near the bakery

local MIXER_SCALE   = 5              -- the whole mixing station, grown in place around
                                     -- its base -- one dial each if the island outgrows them
local OVEN_SCALE    = 5              -- both brick ovens, same treatment
-- The batter is FORCED CADENCE, not a bar: it's a ProximityPrompt, so the floor comes from
-- N presses x a cooldown, and extra presses inside the cooldown do nothing at all. 14 x 1.0s
-- ~= 14s. Was 8 presses on a HoldDuration=0 prompt, which a masher cleared in about 2s.
local STIRS_NEEDED  = 14             -- prompt presses to finish the batter
local STIR_CD       = 1.0            -- seconds the prompt goes dead after each stir -- THIS is the floor
-- the oven HUD minigame: heat bleeds away, STOKE throws it back, and the bake
-- only fills fast while the needle sits in the orange sweet zone
local ZONE_LO, ZONE_HI = 42, 88      -- the sweet zone, on a 0..100 heat bar
local HEAT_DECAY    = 20             -- heat lost per second
local HEAT_STOKE    = 24             -- heat gained per STOKE press (~1 press/sec holds it)
local BAKE_FAST     = 8.5            -- %/sec in the zone  -> ~12s bake played well
local BAKE_SLOW     = 2.6            -- %/sec otherwise    -> a closed HUD still finishes
local EGG_COOLDOWN  = 2.5            -- seconds between chicken taps (per hen)
local CHICKEN_COUNT = 3              -- how many hens roam the coop
local WANDER_R      = 45             -- studs a hen strolls from the coop, when no pen part is drawn
local HEN_SPACING   = 4.5            -- hens this close pick somewhere else to be

-- THE PEN, if you draw one. Any part with one of these names becomes the hard boundary the
-- hens cannot leave -- its footprint, in its own object space, so a rotated pen works.
-- Without one they are held to WANDER_R of the coop instead. Either way the base plate is
-- ALSO applied, so "inside the pen" can never mean "off the island".
--
-- ⚠ "chicken zone" IS NOT IN THIS LIST, and must never be. Despite the name it is island15's
-- entire 300x357 walkable top, not a pen -- treating it as the boundary is what let the hen
-- roam the whole island in the first place.
local PEN_NAMES = { chickenpen = true, chickenboundaires = true, chickenboundaries = true,
	chickenboundary = true, henpen = true }

local COIN_REWARD   = 2000           -- first bake
local BONUS_REWARD  = 1000           -- baking the second recipe afterward

-- Audio: your OWN asset ids. "" = silent, and NOTHING is created for an empty id -- given how many
-- ids in this place fail auth, silence is the safe default, and the same rule Camp S'mores follows.
-- The three that are filled in are already proven elsewhere in this place, so they are safe to keep:
--   the crackle is realm 1's campfire loop, the chime is IslandTaskReward's.
local SOUND_FIRE   = "rbxassetid://158853971"      -- LOOPING oven roar, only while a bake is on
local SOUND_DING   = "rbxassetid://4612378364"     -- the oven bell, and the hand-over
local SOUND_EGG    = "rbxassetid://92880640988467" -- an egg lifted out of the straw
local SOUND_PICKUP = ""                            -- an ingredient taken off the ground
local SOUND_BAWK   = "rbxassetid://77584650945481" -- the chicken: tapped, and the odd cluck as
                                                   -- she trots past you (see runChicken)
local SOUND_STIR   = ""                            -- one sweep of the spoon
local SOUND_POUR   = ""                            -- an ingredient dropping into the bowl
local SOUND_STOKE  = ""                            -- the STOKE button -- a bellows whumph
local SOUND_DOOR   = ""                            -- the iron oven door
-- how the oven roar sits in the world: full volume at the mouth, gone before the next station.
-- Both distances stated (never just Max) so retuning the range can't silently leave Min on the default.
local FIRE_VOLUME  = 0.5
local FIRE_FULL    = 14              -- studs of full volume
local FIRE_RANGE   = 95              -- studs to silence -- the ovens are ~40 studs wide once scaled

-- the two recipes. `need` is ingredient -> count; eggs ONLY come from the chicken.
local RECIPES = {
	brownie = {
		title = "BROWNIE",
		need  = { cocoa = 3, sugar = 2, butter = 1, egg = 2 },
		batter = Color3.fromRGB(72, 44, 26),      -- what the bowl / pan fill looks like
		line   = "A classic! Dense, dark and fudgy.",
	},
	brookie = {
		title = "BROOKIE",
		need  = { cocoa = 2, dough = 2, sugar = 2, butter = 1, egg = 2 },
		batter = Color3.fromRGB(140, 100, 58),    -- half cookie dough, so lighter
		line   = "Half brownie, half cookie. ALL genius.",
	},
}

-- ingredient look-up: label + emoji for banners, and how the pickup prop is built
local ING = {
	cocoa  = { label = "Cocoa",  emoji = "\xF0\x9F\x8D\xAB" },
	sugar  = { label = "Sugar",  emoji = "\xF0\x9F\x8D\xAC" },
	butter = { label = "Butter", emoji = "\xF0\x9F\xA7\x88" },
	dough  = { label = "Dough",  emoji = "\xF0\x9F\x8D\xAA" },
	egg    = { label = "Eggs",   emoji = "\xF0\x9F\xA5\x9A" },
}
-- stable banner order (pairs() order isn't)
local ING_ORDER = { "cocoa", "dough", "sugar", "butter", "egg" }

local E_CHICK  = "\xF0\x9F\x90\x94"
local E_BOWL   = "\xF0\x9F\xA5\xA3"
local E_FIRE   = "\xF0\x9F\x94\xA5"
local E_BELL   = "\xF0\x9F\x94\x94"
local E_SPARK  = "\xE2\x9C\xA8"
local E_TIMER  = "\xE2\x8F\xB0"

-- warm bakery palette, one table (Luau register budget -- same trick as Smores)
local PAL = {
	CREAM   = Color3.fromRGB(255, 246, 232),
	CRUST   = Color3.fromRGB(196, 148, 92),
	CHOC    = Color3.fromRGB(92, 54, 28),
	CHOC_D  = Color3.fromRGB(58, 34, 18),
	CHOC_HI = Color3.fromRGB(140, 90, 52),
	DOUGHY  = Color3.fromRGB(226, 190, 132),
	BRICK   = Color3.fromRGB(158, 84, 62),
	BRICK_D = Color3.fromRGB(118, 60, 44),
	STONE   = Color3.fromRGB(150, 140, 130),
	IRON    = Color3.fromRGB(72, 70, 74),
	WOOD    = Color3.fromRGB(178, 126, 78),
	WOOD_D  = Color3.fromRGB(134, 92, 56),
	GLOW    = Color3.fromRGB(255, 148, 54),
	GLOW_H  = Color3.fromRGB(255, 224, 150),
	SUGAR   = Color3.fromRGB(252, 252, 255),
	BUTTER  = Color3.fromRGB(255, 214, 96),
	EGGSH   = Color3.fromRGB(250, 244, 228),
	FEATHER = Color3.fromRGB(248, 244, 236),
	FEATH_D = Color3.fromRGB(220, 212, 198),
	COMB    = Color3.fromRGB(226, 64, 58),
	BEAK    = Color3.fromRGB(255, 168, 54),
	PINK    = Color3.fromRGB(244, 156, 186),
	SKIN    = Color3.fromRGB(255, 204, 158),
	TEXTC   = Color3.fromRGB(74, 40, 22),
	HINTC   = Color3.fromRGB(158, 130, 108),
	PANEL   = Color3.fromRGB(255, 246, 236),
	SMOKE   = Color3.fromRGB(120, 112, 104),
}

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", "")) end

local function mk(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function tween(inst, t, goal, style, dir)
	local tw = TweenService:Create(inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play(); return tw
end

-- one-shot 2D sound. An empty id creates nothing at all -- see the SOUND_ block above.
local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 6)
end

-- ...and the positional flavour of the same thing, for anything that happens at a station rather
-- than in your hands: a chicken across the field should sound like it's across the field.
local function playAt(id, part, vol, range)
	if not id or id == "" or not (part and part.Parent) then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6
	s.RollOffMinDistance = 10; s.RollOffMaxDistance = range or 90
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = part; s:Play(); Debris:AddItem(s, 6)
end

local function frameOf(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	return inst:GetBoundingBox()
end

-- the BOTTOM face of a marker block, keeping its heading -- stations build up from
-- this. Building on the TOP surface floated everything a whole marker-height too
-- high; the marker's base is where it visibly sits, so that is the ground line.
local function baseFrameOf(part)
	local cf, sz = frameOf(part)
	return CFrame.new(Vector3.new(cf.Position.X, cf.Position.Y - sz.Y * 0.5, cf.Position.Z))
		* (cf - cf.Position)
end

local function hideMarker(src)
	local parts = src:IsA("BasePart") and { src } or src:GetDescendants()
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") then
			p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.Anchored = true
		end
	end
end

local function hrpOf()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- ============================================================================
-- BIG E PROMPTS -- readable from across the bakery, reachable from the model's EDGE
-- ============================================================================
-- Roblox's default prompt is a small grey key badge sized for an adult on a monitor, and its
-- MaxActivationDistance is measured from the part it hangs on -- which for a station scaled up
-- MIXER_SCALE/OVEN_SCALE means the trigger sits at the CENTRE of a thing 37 studs wide. You had
-- to walk into the middle of the bowl to press E on it.
--
-- Two fixes, and they are separate problems:
--   * REACH comes from the model's own footprint: half its bounding diagonal (the farthest
--     edge, not the nearest face) plus a walk-up margin. Scale the station up and the reach
--     grows with it, automatically.
--   * SIZE comes from Style = Custom plus the renderer below. There is no property for "make
--     the default prompt bigger", so a custom one is the only route -- and it doubles as the
--     place the hold-to-act ring is drawn.
local BIG_PROMPT = "BakeryBigPrompt"

-- half the bounding diagonal in XZ: the distance from the centre to the farthest EDGE.
local function reachOf(inst, margin)
	local size
	if inst:IsA("Model") then
		local ok, _, s = pcall(inst.GetBoundingBox, inst)   -- (ok, cframe, size)
		if ok then size = s end
	elseif inst:IsA("BasePart") then
		size = inst.Size
	end
	size = size or Vector3.new(6, 6, 6)
	return math.sqrt(size.X * size.X + size.Z * size.Z) * 0.5 + (margin or 14)
end

-- mark a prompt as ours: big custom art, and optionally reach measured off `reachFrom`
local function bigPrompt(prompt, reachFrom, margin)
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute(BIG_PROMPT, true)
	if reachFrom then prompt.MaxActivationDistance = reachOf(reachFrom, margin) end
	return prompt
end

-- ---- the renderer: one billboard per shown prompt, destroyed when it hides ----
do
	local live = {}   -- [prompt] = { gui=, fill=, holdTween= }

	local function build(prompt)
		local host = prompt.Parent
		if not (host and host:IsA("BasePart")) then return end
		local bb = Instance.new("BillboardGui")
		bb.Name = "BakeryPrompt"; bb.Adornee = host
		bb.Size = UDim2.fromOffset(300, 96)          -- ~3x the stock badge
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.AlwaysOnTop = true; bb.MaxDistance = 400
		bb.Parent = PlayerGui                         -- PlayerGui, not the part: a BillboardGui
		                                              -- parented into bakeFolder would be swept
		                                              -- by anchorAll's descendant walk

		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromScale(1, 1); pill.BackgroundColor3 = PAL.PANEL
		pill.BackgroundTransparency = 0.05; pill.BorderSizePixel = 0; pill.Parent = bb
		Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 22)
		local st = Instance.new("UIStroke"); st.Color = PAL.CRUST; st.Thickness = 4; st.Parent = pill

		-- the hold fill sweeps left to right UNDER the text, so a held prompt reads as loading
		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = PAL.GLOW
		fill.BackgroundTransparency = 0.55; fill.BorderSizePixel = 0; fill.Parent = pill
		Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 22)

		-- the key badge
		local key = Instance.new("TextLabel")
		key.AnchorPoint = Vector2.new(0, 0.5); key.Position = UDim2.new(0, 14, 0.5, 0)
		key.Size = UDim2.fromOffset(64, 64); key.BackgroundColor3 = PAL.CRUST
		key.Font = Enum.Font.FredokaOne; key.TextSize = 34; key.TextColor3 = Color3.new(1, 1, 1)
		key.Text = "E"; key.Parent = pill
		Instance.new("UICorner", key).CornerRadius = UDim.new(0, 16)

		local act = Instance.new("TextLabel")
		act.BackgroundTransparency = 1
		act.Position = UDim2.new(0, 88, 0, 14); act.Size = UDim2.new(1, -102, 0, 40)
		act.Font = Enum.Font.FredokaOne; act.TextSize = 30; act.TextColor3 = PAL.TEXTC
		act.TextXAlignment = Enum.TextXAlignment.Left; act.TextScaled = false
		act.Text = prompt.ActionText; act.Parent = pill

		local obj = Instance.new("TextLabel")
		obj.BackgroundTransparency = 1
		obj.Position = UDim2.new(0, 88, 0, 52); obj.Size = UDim2.new(1, -102, 0, 26)
		obj.Font = Enum.Font.GothamBold; obj.TextSize = 16; obj.TextColor3 = PAL.HINTC
		obj.TextXAlignment = Enum.TextXAlignment.Left
		obj.Text = prompt.ObjectText; obj.Parent = pill

		-- ActionText changes constantly ("Stir!  (3/14)"), so track it rather than snapshot it
		local conn = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			act.Text = prompt.ActionText
		end)

		-- pop in
		bb.Size = UDim2.fromOffset(240, 78)
		tween(bb, 0.16, { Size = UDim2.fromOffset(300, 96) }, Enum.EasingStyle.Back)

		live[prompt] = { gui = bb, fill = fill, conn = conn }
	end

	local function drop(prompt)
		local e = live[prompt]
		if not e then return end
		live[prompt] = nil
		if e.conn then e.conn:Disconnect() end
		if e.gui then e.gui:Destroy() end
	end

	PromptService.PromptShown:Connect(function(prompt)
		if prompt:GetAttribute(BIG_PROMPT) then build(prompt) end
	end)
	PromptService.PromptHidden:Connect(function(prompt) drop(prompt) end)
	PromptService.PromptTriggered:Connect(function(prompt)
		local e = live[prompt]
		if e then e.fill.Size = UDim2.new(0, 0, 1, 0) end
	end)
	PromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local e = live[prompt]
		if e and prompt.HoldDuration > 0 then
			tween(e.fill, prompt.HoldDuration, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
		end
	end)
	PromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local e = live[prompt]
		if e then
			tween(e.fill, 0.12, { Size = UDim2.new(0, 0, 1, 0) }, Enum.EasingStyle.Linear)
		end
	end)
end

-- the island15 MODEL, by name prefix. Wanted early: the quest's folder hangs off it, and
-- the Baker is parented into it so NpcGuideArrow's island-scoped scan can find him.
local function islandModel()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.sub(norm(m.Name), 1, #ISLAND_PREFIX) == ISLAND_PREFIX then
			return m
		end
	end
	return nil
end

-- everything this quest builds lives in one folder, so the ground raycast can
-- ignore it all in one line (a chicken standing on its own egg counts as ground
-- otherwise, and it slowly climbs into the sky)
local bakeFolder = Instance.new("Folder")
bakeFolder.Name = "BakeryQuestLocal"; bakeFolder.Parent = Workspace

-- ...AND THAT FOLDER BELONGS TO ISLAND 15, not to the world. Parented straight to Workspace
-- the whole bakery is a loose pile of parts sitting next to the island rather than part of
-- it -- the exact thing IslandStreaming's loose-part audit flags at boot. Under the island
-- model it travels with the island, reads as island15's in the explorer, and inherits the
-- model's Persistent streaming mode instead of relying on being local-only.
--
-- The island model may not have replicated yet when this script runs, so this is retried
-- from the scanner loop rather than assumed. The pan and tray in your hands are the one
-- thing NOT in here: those are welded into the character and must stay unanchored.
local function homeToIsland()
	local isle = islandModel()
	if isle and bakeFolder.Parent ~= isle then
		bakeFolder.Parent = isle
		print("[Bakery] quest folder re-homed under " .. isle:GetFullName())
	end
end

-- belt to that braces: every part mk() makes is Anchored already, so this only ever catches
-- something added later that forgot. Cheap, and the alternative is a bakery that falls off
-- the island the first time someone builds a prop by hand.
local function anchorAll()
	local n = 0
	for _, d in ipairs(bakeFolder:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then d.Anchored = true; n += 1 end
	end
	return n
end

homeToIsland()

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshRayFilter()
	local ex = { bakeFolder }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ex, pl.Character) end
	end
	rayParams.FilterDescendantsInstances = ex
end

local function groundAt(x, z, refY)
	refreshRayFilter()
	local hit = Workspace:Raycast(Vector3.new(x, refY + 60, z), Vector3.new(0, -220, 0), rayParams)
	return hit and hit.Position or nil
end

-- ============================================================================
-- THE BASE PLATE -- island15's "chicken zone" part
-- ============================================================================
-- Despite the name it is not a pen: it is the island's base slab (300 x 357 studs, the
-- whole walkable top), and it is the ONE thing every prop on this island should sit on.
-- Two reasons it has to be handled specially rather than raycast for like normal ground:
--
--   1  ITS TOP Y IS THE FLOOR OF RECORD. A ray can miss a floor it is standing on --
--      one fired from inside geometry returns nothing at all -- and a miss used to be
--      read as "nothing to stand on here". The stored top surface answers instead.
--      (It IS raycastable: this part is deliberately never passed to hideMarker(),
--      which would turn off its CanQuery AND its collision. See the ZONE branch.)
--   2  IT IS THE ISLAND'S FOOTPRINT. Anything clamped inside it is ON the island by
--      definition -- which is what stops a scattered ingredient landing off the edge and
--      raycasting down to an island thousands of studs below.
local zoneCF, zoneHalf           -- the plate's frame and half-extents, once it streams in
local zoneTopY                   -- its TOP surface: the floor everything seats on

-- clamp a world position into the plate's footprint, with a margin in from the edge, in
-- the PLATE's own object space so a rotated island still works. `inset` lets props that
-- must not teeter on the rim (ingredients, stations) sit further in than the chicken does.
local function clampToZone(pos, inset)
	if not zoneCF then return pos end
	local o = zoneCF:PointToObjectSpace(pos)
	local m = inset or 1.5
	local hx = math.max(1, zoneHalf.X - m)
	local hz = math.max(1, zoneHalf.Z - m)
	local cx, cz = math.clamp(o.X, -hx, hx), math.clamp(o.Z, -hz, hz)
	if cx == o.X and cz == o.Z then return pos end
	return (zoneCF * CFrame.new(cx, o.Y, cz)).Position
end

-- WHERE A PROP GOES. Real geometry wins when there is any -- a hill, a rock, the island's
-- own decking all deserve to be stood on. The plate catches the rest: a ray that hits
-- nothing (the plate itself no longer answers), or one that hits something absurdly far
-- below (off the edge, or a different island entirely). Either way the XZ is pulled inside
-- the island's footprint first, so nothing is ever seated out over the void.
local function seatOn(x, z, refY, inset)
	if zoneCF then
		local p = clampToZone(Vector3.new(x, refY, z), inset or 8)
		x, z = p.X, p.Z
	end
	local g = groundAt(x, z, refY)
	if g and math.abs(g.Y - refY) <= 60 then return g end
	if zoneTopY then return Vector3.new(x, zoneTopY, z) end
	return g   -- nil when there is neither ground nor a plate: callers fall back themselves
end

-- ============================================================================
-- STATE
-- ============================================================================
-- step: 0 talk  2 gather (incl. "bring it to the bowl")  3 mixing  4 carry pan
--       5 baking  6 carry tray  7 done
local step         = 0
local recipe       = nil        -- "brownie" | "brookie"
local have         = {}         -- ingredient -> count collected
local stirs        = 0
local bonusRound   = false      -- true while baking the second recipe
local bonusDone    = false
local mixerAt      = nil        -- cached CFrame of the mixing station (banner gate + scatter)
local bakerHead    = nil
-- SHARED EFFECTS. Every quest here is a LocalScript, so nothing one player does shows up on
-- anybody else's screen. FX.send tells the server (BakeryFxSync.server.lua) that something
-- happened; every OTHER player's copy of this script plays it on their own props. Declared here
-- because the send sites are scattered up and down the file and the receiving half is built at
-- the bottom, next to the ovens and hens it drives.
local FX = {}
local refreshBanner, flashBanner, showBubble, hideBubble, openChooser
local refreshPrompts            -- re-evaluates every station prompt after a state change

_G.bakeryQuestComplete = false
_G.bakeryQuestStep     = nil    -- small grey detail text for the Quest Journal

local function needOf() return recipe and RECIPES[recipe].need or nil end

local function allGathered()
	local need = needOf(); if not need then return false end
	for k, n in pairs(need) do if (have[k] or 0) < n then return false end end
	return true
end

local function stillNeeds(kind)
	local need = needOf(); if not need then return false end
	return (have[kind] or 0) < (need[kind] or 0)
end

-- ============================================================================
-- OBJECTIVE BANNER (top-center, proximity-gated to the bakery)
-- ============================================================================
local objGui = Instance.new("ScreenGui")
objGui.Name = "BakeryObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7
objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 560, 0, 52); objFrame.BackgroundColor3 = PAL.PANEL
objFrame.Visible = false; objFrame.Parent = objGui
do
	Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0, 16)
	local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 3; s.Parent = objFrame
end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1)
objLabel.Font = Enum.Font.FredokaOne; objLabel.TextColor3 = PAL.TEXTC
objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 21; sz.Parent = objLabel
	local pd = Instance.new("UIPadding")
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = objLabel
end

-- "🍫 2/3   🍬 1/2   🥚 0/2" -- the whole shopping list in one line
local function shoppingList()
	local need, bits = needOf(), {}
	if not need then return "" end
	for _, k in ipairs(ING_ORDER) do
		local n = need[k]
		if n then bits[#bits + 1] = ("%s %d/%d"):format(ING[k].emoji, math.min(have[k] or 0, n), n) end
	end
	return table.concat(bits, "   ")
end

local function baseObjectiveText()
	local R = recipe and RECIPES[recipe]
	if step >= 7 then
		return bonusDone and (E_SPARK .. " Both recipes baked. The Baker is thrilled!")
			or (E_SPARK .. " Bake-off complete! Ask the Baker about the OTHER recipe...")
	elseif step == 6 then
		return ("%s Carry the %s tray back to the Baker!"):format(E_SPARK, R.title)
	elseif step == 5 then
		return E_FIRE .. " Baking..."
	elseif step == 4 then
		return E_FIRE .. " Carry the pan to an OVEN!"
	elseif step == 3 then
		return ("%s STIR the bowl!  %d/%d"):format(E_BOWL, stirs, STIRS_NEEDED)
	elseif step == 2 then
		if allGathered() then return E_BOWL .. " All ingredients! Take them to the MIXING BOWL!" end
		return shoppingList() .. "   (" .. E_CHICK .. " tap a chicken for eggs!)"
	end
	return E_BOWL .. " Talk to the Baker to start the Bake-Off!"
end

local flashToken = 0
refreshBanner = function()
	objLabel.Text = baseObjectiveText()
	-- journal detail: a couple of words on where you are in the bake
	local d
	if step == 2 and recipe then
		local need, got, total = needOf(), 0, 0
		for k, n in pairs(need) do total += n; got += math.min(have[k] or 0, n) end
		d = ("gathering %d/%d"):format(got, total)
	elseif step == 3 then d = "mixing"
	elseif step == 4 then d = "to the oven!"
	elseif step == 5 then d = "baking"
	elseif step == 6 then d = "deliver it!"
	end
	_G.bakeryQuestStep = d
end
flashBanner = function(text, seconds)
	flashToken += 1; local tok = flashToken
	objLabel.Text = text
	task.delay(seconds or 2.5, function() if tok == flashToken then refreshBanner() end end)
end

-- ============================================================================
-- THE BANNER IS A REMINDER, NOT A FIXTURE
-- ============================================================================
-- Pinned to the top of the screen for the whole bake-off it was wallpaper within a minute, and
-- with a flash banner landing on it every time an ingredient moved, the top of the screen was a
-- stream nobody was reading. Now: something happened (a pickup, a counter, a flash) -> straight
-- up for 5 seconds; otherwise it reminds you what you are doing for 5 seconds once every 20; out
-- of range it is gone and walking back shows it again at once. The text changing IS the event
-- test -- every route with news already writes it here.
task.spawn(function()
	local shownUntil, nextAt, lastText = 0, 0, nil
	while true do
		task.wait(0.25)
		local now = os.clock()
		local hrp = hrpOf()
		local near = (mixerAt ~= nil and hrp ~= nil
			and (hrp.Position - mixerAt.Position).Magnitude <= BANNER_RANGE)
		if not near then
			objFrame.Visible = false
			lastText = objLabel.Text
			nextAt = 0
		else
			if objLabel.Text ~= lastText then
				lastText = objLabel.Text
				shownUntil = now + 5; nextAt = now + 20
			elseif now >= nextAt then
				shownUntil = now + 5; nextAt = now + 20
			end
			objFrame.Visible = now < shownUntil
		end
	end
end)

-- ============================================================================
-- SPEECH BUBBLE (same paged look as the other island quests)
-- ============================================================================
hideBubble = function(adornee)
	local prev = adornee and adornee:FindFirstChild("SpeechBubble")
	if prev then prev:Destroy() end
end
showBubble = function(adornee, text, persist, footer)
	hideBubble(adornee)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = adornee; bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = PAL.PANEL; frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0; frame.Parent = bb
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = PAL.CRUST; st.Thickness = 2
	st.Transparency = 0.3; st.Parent = frame
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = frame
	local lbl = Instance.new("TextLabel")
	lbl.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne; lbl.Text = text
	lbl.TextColor3 = PAL.TEXTC; lbl.TextScaled = true; lbl.TextWrapped = true; lbl.Parent = frame
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = lbl
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1, 0.2)
		h.Position = UDim2.fromScale(0, 0.8); h.BackgroundTransparency = 1
		h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = PAL.HINTC
		h.TextScaled = true; h.Parent = frame
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 14; hs.Parent = h
	end
	bb.Parent = adornee
	if not persist then
		task.delay(8, function()
			if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then bb:Destroy() end
		end)
	end
end

-- ============================================================================
-- RECIPE CHOOSER -- two big cards, pick one. X closes it (never the backdrop);
-- talking to the Baker again reopens it.
-- ============================================================================
local chGui = Instance.new("ScreenGui")
chGui.Name = "BakeryRecipeChooser"; chGui.ResetOnSpawn = false; chGui.DisplayOrder = 12
chGui.IgnoreGuiInset = true; chGui.Enabled = false; chGui.Parent = PlayerGui

local chShade = Instance.new("Frame")   -- a Frame, NOT a button: backdrop taps close NOTHING
chShade.Size = UDim2.fromScale(1, 1); chShade.BackgroundColor3 = Color3.new(0, 0, 0)
chShade.BackgroundTransparency = 0.5; chShade.ZIndex = 1
chShade.Active = true                   -- ...but they also don't reach the world behind it
chShade.Parent = chGui

local chPanel = Instance.new("Frame")
chPanel.AnchorPoint = Vector2.new(0.5, 0.5); chPanel.Position = UDim2.fromScale(0.5, 0.5)
chPanel.Size = UDim2.new(0, 640, 0, 400); chPanel.BackgroundColor3 = PAL.PANEL
chPanel.BorderSizePixel = 0; chPanel.ZIndex = 2; chPanel.Parent = chGui
-- HOUSE PANEL: the Pet Hub's 700x520 card at (0.5,0),(0.5,-45), and the bottom
-- buttons hide while it is up. One call does both -- see HousePanel.client.luau.
-- The panel keeps its own size and every child keeps its own pixel coordinates;
-- it is centred in the house shell and scaled to fit, so nothing inside moves.
pcall(_G.housePanel, chPanel)   -- island15 recipe chooser
Instance.new("UICorner", chPanel).CornerRadius = UDim.new(0, 18)
do local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 3; s.Parent = chPanel end

local chHead = Instance.new("TextLabel")
chHead.BackgroundTransparency = 1; chHead.Position = UDim2.new(0, 24, 0, 14)
chHead.Size = UDim2.new(1, -110, 0, 40); chHead.Font = Enum.Font.FredokaOne
chHead.TextSize = 28; chHead.TextColor3 = PAL.TEXTC
chHead.TextXAlignment = Enum.TextXAlignment.Left; chHead.ZIndex = 3
chHead.Text = "Pick your bake!"; chHead.Parent = chPanel

local chClose = Instance.new("TextButton")
chClose.AnchorPoint = Vector2.new(1, 0); chClose.Position = UDim2.new(1, -16, 0, 16)
chClose.Size = UDim2.fromOffset(42, 42); chClose.BackgroundColor3 = PAL.CRUST
chClose.Text = "X"; chClose.Font = Enum.Font.FredokaOne; chClose.TextSize = 22
chClose.TextColor3 = Color3.new(1, 1, 1); chClose.BorderSizePixel = 0; chClose.ZIndex = 4
chClose.Parent = chPanel
Instance.new("UICorner", chClose).CornerRadius = UDim.new(0, 12)
chClose.MouseButton1Click:Connect(function() chGui.Enabled = false end)

local chosenCallback = nil     -- set by openChooser; the card buttons call it

local function recipeCard(key, x)
	local R = RECIPES[key]
	local card = Instance.new("Frame")
	card.Position = UDim2.new(0, x, 0, 68); card.Size = UDim2.new(0, 292, 0, 312)
	card.BackgroundColor3 = Color3.fromRGB(252, 238, 222); card.BorderSizePixel = 0
	card.ZIndex = 3; card.Parent = chPanel
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local st = Instance.new("UIStroke"); st.Color = R.batter; st.Thickness = 2.5; st.Parent = card

	local big = Instance.new("TextLabel")
	big.BackgroundTransparency = 1; big.Position = UDim2.new(0, 0, 0, 8)
	big.Size = UDim2.new(1, 0, 0, 64); big.Font = Enum.Font.FredokaOne; big.TextSize = 52
	big.Text = (key == "brownie") and ING.cocoa.emoji or (ING.dough.emoji .. ING.cocoa.emoji)
	big.ZIndex = 4; big.Parent = card

	local ttl = Instance.new("TextLabel")
	ttl.BackgroundTransparency = 1; ttl.Position = UDim2.new(0, 0, 0, 72)
	ttl.Size = UDim2.new(1, 0, 0, 34); ttl.Font = Enum.Font.FredokaOne; ttl.TextSize = 28
	ttl.TextColor3 = R.batter; ttl.Text = R.title; ttl.ZIndex = 4; ttl.Parent = card

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 14, 0, 106)
	sub.Size = UDim2.new(1, -28, 0, 34); sub.Font = Enum.Font.GothamMedium; sub.TextSize = 13
	sub.TextColor3 = PAL.HINTC; sub.TextWrapped = true; sub.Text = R.line; sub.ZIndex = 4
	sub.Parent = card

	local list = Instance.new("TextLabel")
	list.BackgroundTransparency = 1; list.Position = UDim2.new(0, 14, 0, 144)
	list.Size = UDim2.new(1, -28, 0, 104); list.Font = Enum.Font.GothamBold; list.TextSize = 15
	list.TextColor3 = PAL.TEXTC; list.TextYAlignment = Enum.TextYAlignment.Top
	list.TextXAlignment = Enum.TextXAlignment.Left; list.ZIndex = 4
	local lines = {}
	for _, k in ipairs(ING_ORDER) do
		local n = R.need[k]
		if n then lines[#lines + 1] = ("%s  %d x %s"):format(ING[k].emoji, n, ING[k].label) end
	end
	list.Text = table.concat(lines, "\n"); list.Parent = card

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(0.5, 1); btn.Position = UDim2.new(0.5, 0, 1, -12)
	btn.Size = UDim2.new(1, -28, 0, 44); btn.BackgroundColor3 = R.batter
	btn.Font = Enum.Font.FredokaOne; btn.TextSize = 20; btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "BAKE THIS!"; btn.BorderSizePixel = 0; btn.ZIndex = 4; btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
	btn.MouseButton1Click:Connect(function()
		if card.BackgroundTransparency > 0.3 then return end   -- greyed-out = locked
		if chosenCallback then chosenCallback(key) end
	end)
	return card
end
local cards = { brownie = recipeCard("brownie", 22), brookie = recipeCard("brookie", 326) }

-- lockTo: on the bonus round only the OTHER recipe is offered; its card stays
-- bright and the finished one fades out
openChooser = function(lockTo, onPick)
	for key, card in pairs(cards) do
		local locked = (lockTo ~= nil and key ~= lockTo)
		card.BackgroundTransparency = locked and 0.55 or 0
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then d.TextTransparency = locked and 0.6 or 0 end
			if d:IsA("TextButton") then
				d.TextTransparency = locked and 0.6 or 0
				d.Text = locked and "ALREADY BAKED" or "BAKE THIS!"
			end
		end
	end
	chosenCallback = function(key)
		chGui.Enabled = false
		onPick(key)
	end
	chGui.Enabled = true
end

-- ============================================================================
-- FIREWORKS + WIN BANNER (the standard island celebration)
-- ============================================================================
local FW_COLORS = { Color3.fromRGB(255, 92, 138), Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(150, 235, 130), Color3.fromRGB(255, 205, 90), Color3.fromRGB(190, 130, 255) }

local function burst(atPos, color)
	for i = 1, 24 do
		local spark = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
			Color = color, Material = Enum.Material.Neon })
		spark.CFrame = CFrame.new(atPos); spark.Parent = bakeFolder
		local dest = atPos + Vector3.new((i % 7) - 3, (i % 5), ((i * 3) % 7) - 3).Unit * 13
		tween(spark, 0.9, { CFrame = CFrame.new(dest), Transparency = 1,
			Size = Vector3.new(0.1, 0.1, 0.1) })
		Debris:AddItem(spark, 1)
	end
end

local function launchFireworks(fromPos)
	for i = 1, 3 do
		task.delay(i * 0.35, function()
			local rocket = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6),
				Color = PAL.GLOW_H, Material = Enum.Material.Neon })
			local start = fromPos + Vector3.new((i - 2) * 6, 3, 0)
			local apex  = start + Vector3.new(0, 42 + i * 6, 0)
			rocket.CFrame = CFrame.new(start); rocket.Parent = bakeFolder
			local up = tween(rocket, 0.9, { CFrame = CFrame.new(apex) })
			up.Completed:Connect(function()
				burst(apex, FW_COLORS[((i - 1) % #FW_COLORS) + 1])
				rocket:Destroy()
			end)
		end)
	end
end

-- ⚠ ANNOUNCEMENTS GO THROUGH THE ONE REALM BANNER -- NEVER A ScreenGui OF THEIR OWN.
-- This is realm 1's rule (see its CoreClient, and NotifyCenter.luau here: push/pin is the whole
-- API). It used to build its own card in the middle of the screen, which meant a quest win could
-- land on top of the objective banner, an island arrival or a live event -- several cards in the
-- same band, none of them aware of the others. NotifyCenter already ranks, queues and preempts,
-- so a win is one more push and takes its turn like everything else.
--
-- EVENT priority, deliberately: finishing a quest has to outrank the objective banner that is
-- pinned underneath it (REWARD), but must not talk over a real Robux purchase (PURCHASE).
local function winBanner(text)
	local msg = text
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({
			top      = "â¨ QUEST COMPLETE",
			text     = msg,
			color    = PAL.CRUST,
			priority = _G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.EVENT or nil,
			duration = 5,
		}) end)
	else
		print("[Bakery] " .. tostring(msg))
	end
end

local function poofAt(pos, color)
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local s = mk({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4),
			Color = color or PAL.GLOW_H, Material = Enum.Material.Neon })
		s.CFrame = CFrame.new(pos); s.Parent = bakeFolder
		tween(s, 0.45, { CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 2.6, 1.4, math.sin(a) * 2.6)),
			Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) })
		Debris:AddItem(s, 0.6)
	end
end

-- ============================================================================
-- CARRYING THINGS -- the pan and the tray are WELDED into the hands, not
-- anchored and re-positioned (an anchored prop fights the walk animation and
-- reads as floating -- same lesson as the Smores axe)
-- ============================================================================
local heldModel = nil      -- the pan/tray model currently welded on
local heldKind  = nil      -- "pan" | "tray", so a respawn can rebuild it

local function dropHeld()
	if heldModel then heldModel:Destroy(); heldModel = nil; heldKind = nil end
end

-- builds the prop AND welds it, held flat in front like a waiter's tray
local function giveHeld(kind)
	dropHeld()
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not hand then return end
	local R = RECIPES[recipe] or RECIPES.brownie

	local m = Instance.new("Model"); m.Name = "BakeryHeld"
	local function bit(props)
		props.Anchored = false; props.Massless = true; props.Parent = m
		return mk(props)
	end
	local root
	if kind == "pan" then
		root = bit({ Color = PAL.IRON, Size = Vector3.new(1.7, 0.3, 1.25), Material = Enum.Material.Metal })
		root.CFrame = CFrame.new()
		local fill = bit({ Color = R.batter, Size = Vector3.new(1.5, 0.18, 1.05) })
		fill.CFrame = CFrame.new(0, 0.14, 0)
		for _, sx in ipairs({ -1, 1 }) do
			local h = bit({ Color = PAL.IRON, Size = Vector3.new(0.3, 0.12, 0.5), Material = Enum.Material.Metal })
			h.CFrame = CFrame.new(sx * 0.98, 0.05, 0)
		end
	else -- tray of finished goods
		root = bit({ Color = PAL.BUTTER, Size = Vector3.new(1.9, 0.16, 1.35), Reflectance = 0.08 })
		root.CFrame = CFrame.new()
		for gx = -1, 1 do
			for gz = 0, 1 do
				-- brookie trays alternate brownie squares with cookie blobs
				local isCookie = (recipe == "brookie") and ((gx + gz) % 2 == 0)
				local sq = bit({
					Color = isCookie and PAL.DOUGHY or PAL.CHOC,
					Shape = isCookie and Enum.PartType.Ball or Enum.PartType.Block,
					Size = isCookie and Vector3.new(0.52, 0.34, 0.52) or Vector3.new(0.46, 0.3, 0.46),
				})
				sq.CFrame = CFrame.new(gx * 0.55, 0.22, (gz - 0.5) * 0.6)
			end
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local wc = Instance.new("WeldConstraint"); wc.Part0 = root; wc.Part1 = d; wc.Parent = root
		end
	end
	m.PrimaryPart = root
	m.Parent = char
	local w = Instance.new("Weld")
	w.Part0 = hand; w.Part1 = root
	w.C0 = CFrame.new(0, -0.35, -1.0) * CFrame.Angles(0, math.rad(90), 0)
	w.Parent = root
	heldModel, heldKind = m, kind
end

-- a respawn takes the weld (and the model) down with the old character, so the
-- STEP decides what belongs back in your hands, not what was held a second ago
player.CharacterAdded:Connect(function()
	heldModel = nil; heldKind = nil
	task.delay(1.6, function()
		if step == 4 then giveHeld("pan") elseif step == 6 then giveHeld("tray") end
	end)
end)

-- ============================================================================
-- INGREDIENT PICKUPS -- scattered around the mixing station, one prop per
-- item needed. Eggs are NOT scattered; the chicken is the only egg source.
-- ============================================================================
local scattered = {}    -- live pickup models, cleared between rounds

local function buildIngredientProp(kind, at)
	local m = Instance.new("Model"); m.Name = "BakeryPickup"
	local base = CFrame.new(at + Vector3.new(0, 1.1, 0))
	local main
	if kind == "cocoa" then
		main = mk({ Shape = Enum.PartType.Ball, Color = PAL.CHOC, Size = Vector3.new(1.8, 1.15, 1.15), CanQuery = true })
		main.CFrame = base; main.Parent = m
		local ridge = mk({ Shape = Enum.PartType.Ball, Color = PAL.CHOC_HI, Size = Vector3.new(1.4, 0.5, 0.9) })
		ridge.CFrame = base * CFrame.new(0, 0.35, 0); ridge.Parent = m
	elseif kind == "sugar" then
		main = mk({ Color = PAL.SUGAR, Size = Vector3.new(1.0, 1.0, 1.0), Reflectance = 0.12, CanQuery = true })
		main.CFrame = base; main.Parent = m
		local c2 = mk({ Color = PAL.SUGAR, Size = Vector3.new(0.8, 0.8, 0.8), Reflectance = 0.12 })
		c2.CFrame = base * CFrame.new(0.45, -0.15, 0.3) * CFrame.Angles(0, math.rad(25), 0); c2.Parent = m
		local c3 = mk({ Color = PAL.SUGAR, Size = Vector3.new(0.7, 0.7, 0.7), Reflectance = 0.12 })
		c3.CFrame = base * CFrame.new(-0.3, 0.75, -0.1) * CFrame.Angles(0, math.rad(40), 0); c3.Parent = m
	elseif kind == "butter" then
		main = mk({ Color = PAL.BUTTER, Size = Vector3.new(1.6, 0.8, 1.0), CanQuery = true })
		main.CFrame = base; main.Parent = m
		local pat = mk({ Color = Color3.fromRGB(255, 234, 150), Size = Vector3.new(0.9, 0.4, 0.7) })
		pat.CFrame = base * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(15), 0); pat.Parent = m
	else -- dough
		main = mk({ Shape = Enum.PartType.Ball, Color = PAL.DOUGHY, Size = Vector3.new(1.5, 1.2, 1.5), CanQuery = true })
		main.CFrame = base; main.Parent = m
		for i = 1, 3 do
			local chip = mk({ Color = PAL.CHOC_D, Size = Vector3.new(0.28, 0.28, 0.28) })
			chip.CFrame = base * CFrame.new(math.cos(i * 2.1) * 0.5, 0.45, math.sin(i * 2.1) * 0.5)
			chip.Parent = m
		end
	end
	m.PrimaryPart = main

	local hl = Instance.new("Highlight"); hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 210, 120); hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = m; hl.Parent = m
	local glow = Instance.new("PointLight"); glow.Color = PAL.GLOW_H
	glow.Brightness = 1.2; glow.Range = 7; glow.Parent = main
	m.Parent = bakeFolder
	return m, main
end

local function wirePickup(m, main, kind, idx)
	-- gentle bob + spin so it reads as a pickup from across the field. The loop
	-- stops the moment it's taken -- PivotTo would otherwise fight the collect
	-- tween and snap the parts back every frame.
	task.spawn(function()
		local b, t = m:GetPivot(), idx * 0.7
		while m.Parent and not m:GetAttribute("Taken") do
			t += 0.06
			m:PivotTo(b * CFrame.new(0, math.sin(t) * 0.3, 0) * CFrame.Angles(0, t * 0.5, 0))
			task.wait(0.03)
		end
	end)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"; prompt.ObjectText = ING[kind].label
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false; prompt.Parent = main
	bigPrompt(prompt)          -- big art, but its own reach: a pickup you walk up to

	local taken = false
	prompt.Triggered:Connect(function()
		if taken then return end
		if step ~= 2 then return end
		if not stillNeeds(kind) then
			flashBanner(("%s You have enough %s already!"):format(ING[kind].emoji, ING[kind].label), 2)
			return
		end
		taken = true
		m:SetAttribute("Taken", true)
		have[kind] = (have[kind] or 0) + 1
		scattered[m] = nil
		poofAt(m:GetPivot().Position, PAL.GLOW_H)
		playSound(SOUND_PICKUP, 0.55)
		-- the prop arcs to you and shrinks away -- "picked up", not "vanished"
		local hrp = hrpOf()
		prompt:Destroy()
		if hrp then
			local goal = hrp.Position + Vector3.new(0, 1, 0)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					tween(d, 0.35, { CFrame = CFrame.new(goal), Size = d.Size * 0.1, Transparency = 1 })
				end
			end
		end
		Debris:AddItem(m, 0.5)
		refreshBanner()
		if refreshPrompts then refreshPrompts() end
		if allGathered() then
			flashBanner(E_BOWL .. " That's everything! To the MIXING BOWL!", 3)
			if bakerHead then showBubble(bakerHead, "That's the lot! Get mixing!", false) end
		end
	end)
end

local function clearScattered()
	for m in pairs(scattered) do if m.Parent then m:Destroy() end end
	scattered = {}
end

-- ===== EVERY INGREDIENT SITS ON THE PLATE. NOT NEAR IT, ON IT. =====
-- The plate ("chicken zone") IS island15's walkable top, so "on the plate" and "on the
-- island" are the same statement -- and its stored top Y is a flat, known number, where a
-- raycast is a guess that can be wrong in two ways that both read to a player as "floating
-- in mid-air off the island":
--   * IT HITS SOMETHING ELSE ON THE WAY DOWN. island15 is covered in props and ~150 wedges
--     standing tens of studs proud of the plate. A ray fired from above lands the ingredient
--     on the FIRST thing it meets, so a bag of sugar ends up perched on a fence rail.
--   * IT HITS NOTHING. A ray that starts inside geometry returns nil, and so does one fired
--     past the island's edge -- and the old fallback then dropped the item wherever the
--     second guess landed.
-- So: the plate's top Y is the height, full stop, and the only question left is WHERE on the
-- plate. plateClear() answers that -- it walks the spiral until it finds a patch with nothing
-- standing on it, which is also what stops an ingredient spawning inside a fence post.
local function plateSpot(x, z, inset)
	local p = clampToZone(Vector3.new(x, zoneTopY, z), inset or 12)
	return Vector3.new(p.X, zoneTopY, p.Z)
end

-- is this patch of plate bare? A short ray from just above it: hitting the plate itself (or
-- anything else within a stud and a half of its surface) is clear; hitting something higher
-- means a prop stands here; hitting NOTHING means there is no plate here at all.
local function plateClear(pos)
	refreshRayFilter()
	local hit = Workspace:Raycast(Vector3.new(pos.X, zoneTopY + 10, pos.Z), Vector3.new(0, -12, 0), rayParams)
	if not hit then return false end
	return math.abs(hit.Position.Y - zoneTopY) <= 1.5
end

-- one prop per item still needed, on a golden-angle spiral around the mixer --
-- deterministic (no random: this must land the same every respawn) and spread out.
local function scatterIngredients()
	clearScattered()
	if not (mixerAt and recipe) then return end
	-- nothing left to find? then nothing gets laid out. This runs deferred while the base plate
	-- streams in, so it can land AFTER the list is already complete -- /done being the obvious
	-- way, but a fast round is enough -- and re-littering the plate then reads as a bug.
	if allGathered() then return end
	local need, idx, placed = needOf(), 0, 0
	local onPlate, bumped = 0, 0
	for _, kind in ipairs(ING_ORDER) do
		local n = (kind ~= "egg") and (need[kind] or 0) or 0
		for _ = 1, n do
			idx += 1
			local g
			if zoneCF and zoneTopY then
				-- walk the spiral from this item's own index until the plate is bare there.
				-- The cap matters: on an island paved wall to wall in props every candidate
				-- is occupied, and a search with no end would hang the round on step 2.
				for try = 0, 40 do
					local j = idx + try * 7               -- +7, not +1: a blocked patch is usually
					                                      -- a whole prop, and the next index is
					                                      -- inches away and blocked by the same thing
					local ang = j * 2.39996               -- golden angle: never clumps, never lines up
					local rad = 28 + ((j * 31) % 75)
					local cand = plateSpot(mixerAt.Position.X + math.cos(ang) * rad,
						mixerAt.Position.Z + math.sin(ang) * rad, 12)
					g = cand                              -- worst case we keep the last: still ON the plate
					if plateClear(cand) then
						if try > 0 then bumped += 1 end   -- counted per ITEM moved, not per ray fired
						break
					end
				end
				onPlate += 1
			else
				-- NO PLATE YET (it had not streamed in when the round started). Fall back to the
				-- old raycast seat rather than refusing to scatter -- but say so, because this is
				-- the branch where an ingredient can end up somewhere silly.
				local ang = idx * 2.39996
				local rad = 28 + ((idx * 31) % 75)
				g = seatOn(mixerAt.Position.X + math.cos(ang) * rad,
					mixerAt.Position.Z + math.sin(ang) * rad, mixerAt.Position.Y, 12)
					or (mixerAt.Position + Vector3.new(math.cos(ang) * 20, 0, math.sin(ang) * 20))
			end
			local m, main = buildIngredientProp(kind, g)
			wirePickup(m, main, kind, idx)
			scattered[m] = true
			placed += 1
		end
	end
	if onPlate > 0 then
		print(("[Bakery] %d ingredient(s) scattered for the %s -- all seated on the plate at Y=%.0f%s")
			:format(placed, recipe, zoneTopY,
				bumped > 0 and (", %d moved off an occupied patch"):format(bumped) or ""))
	else
		warn(("[Bakery] %d ingredient(s) scattered for the %s BEFORE the base plate was found -- "
			.. "seated by raycast, which can put one on top of a prop"):format(placed, recipe))
	end
end

-- ============================================================================
-- THE HENS -- built at "ChickenPart", roam their pen, and TAP = EGG
-- ============================================================================
-- CHICKEN_COUNT of them now, not one. Everything that used to be a file-level variable
-- (mode, target, the tap clock) moved into a per-hen record, because three birds sharing
-- one "am I pausing right now" flag is three birds moving as a single organism.
local chickens = {}              -- { model=, home=, pos=, yaw=, mode=, target=, ... }
local chickenOrigin              -- the ChickenPart marker: the coop, and the pen's centre
local nestModel                  -- so the nest can be re-seated when the zone arrives
local penCF, penHalf             -- the drawn pen, if there is one

-- FIND THE PEN. Optional: a part you name (see PEN_NAMES). Searched under island15 first so
-- a similarly-named part elsewhere in the world cannot claim it.
local function findPen()
	local isle = islandModel()
	local function scan(scope)
		if not scope then return nil end
		for _, d in ipairs(scope:GetDescendants()) do
			if d:IsA("BasePart") and PEN_NAMES[norm(d.Name)] then return d end
		end
		return nil
	end
	local part = scan(isle) or scan(Workspace)
	if not part then return end
	penCF, penHalf = part.CFrame, part.Size * 0.5
	print(("[Bakery] chicken pen: %s (%.0f x %.0f studs) -- the hens cannot leave it")
		:format(part:GetFullName(), part.Size.X, part.Size.Z))
end

-- THE HARD WALL. A pen part's footprint if one is drawn, otherwise a WANDER_R circle around
-- the coop -- and the base plate on top of either, so "inside the pen" can never mean "off
-- the island". Every position a hen takes goes through this, not just her destination: a
-- boundary checked only when picking a target is a boundary she walks straight through on
-- her way there.
local function clampToPen(pos)
	if penCF then
		local o = penCF:PointToObjectSpace(pos)
		local hx, hz = math.max(1, penHalf.X - 1.5), math.max(1, penHalf.Z - 1.5)
		pos = (penCF * CFrame.new(math.clamp(o.X, -hx, hx), o.Y, math.clamp(o.Z, -hz, hz))).Position
	elseif chickenOrigin then
		local off = (pos - chickenOrigin) * Vector3.new(1, 0, 1)
		if off.Magnitude > WANDER_R then pos = chickenOrigin + off.Unit * WANDER_R end
	end
	return clampToZone(pos, 3)
end

-- is another hen already standing here? Keeps the flock from converging into one bird.
local function henCrowded(pos, self)
	for _, o in ipairs(chickens) do
		if o ~= self and o.model and o.model.Parent then
			if ((o.pos - pos) * Vector3.new(1, 0, 1)).Magnitude < HEN_SPACING then return true end
		end
	end
	return false
end

-- a fresh stroll destination inside the pen. Clock-derived, no math.random (deterministic),
-- and offset per hen by her index so three birds do not walk the same path in lockstep.
local function pickWanderTarget(now, rec)
	local phase = (rec and rec.phase) or 0
	for try = 0, 5 do
		local a = (now * 0.7 + phase + try * 1.7) % (math.pi * 2)
		local r = 8 + ((now * 13 + phase * 30 + try * 9) % (WANDER_R - 8))
		local t = clampToPen(chickenOrigin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		if not henCrowded(t, rec) then return t end
	end
	return clampToPen(chickenOrigin)
end

-- a feeler ray at chest height along the walk direction: solid things (the
-- ovens, the counter, island rocks) turn her around instead of being clipped
-- through. RespectCanCollide, so decor and pickups don't spook her.
local obsParams = RaycastParams.new()
obsParams.FilterType = Enum.RaycastFilterType.Exclude
obsParams.RespectCanCollide = true
local function obstacleAhead(from, dir)
	if dir.Magnitude < 0.01 then return false end
	-- EVERY hen is excluded, not just the one walking: birds bumping into each other would
	-- deadlock two of them nose to nose forever. Spacing between them is handled by
	-- henCrowded() when they pick a destination, which resolves instead of blocking.
	local ex = {}
	for _, o in ipairs(chickens) do if o.model then ex[#ex + 1] = o.model end end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ex, pl.Character) end
	end
	obsParams.FilterDescendantsInstances = ex
	return Workspace:Raycast(from + Vector3.new(0, 1.2, 0), dir.Unit * 2.4, obsParams) ~= nil
end

local function buildChicken(originPos, index)
	index = index or 1
	local m = Instance.new("Model"); m.Name = "BakeryChicken" .. index
	local at = CFrame.new(originPos + Vector3.new(0, 1.05, 0))
	local function bit(props, cf)
		props.Parent = m
		local p = mk(props); p.CFrame = at * cf; return p
	end
	-- plump body, tiny head, big personality
	local body = bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATHER,
		Size = Vector3.new(1.9, 1.7, 2.3), CanQuery = true }, CFrame.new())
	bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATH_D, Size = Vector3.new(1.5, 1.1, 1.2) },
		CFrame.new(0, -0.15, 0.75))                                   -- tail puff
	local head = bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATHER,
		Size = Vector3.new(0.95, 0.95, 0.95), CanQuery = true }, CFrame.new(0, 0.95, -1.0))
	bit({ Color = PAL.COMB, Size = Vector3.new(0.18, 0.5, 0.6) }, CFrame.new(0, 1.5, -1.0))
	bit({ Color = PAL.COMB, Size = Vector3.new(0.16, 0.35, 0.25) }, CFrame.new(0, 0.62, -1.35)) -- wattle
	bit({ Color = PAL.BEAK, Size = Vector3.new(0.3, 0.22, 0.5) }, CFrame.new(0, 0.95, -1.5))
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Shape = Enum.PartType.Ball, Color = Color3.new(0, 0, 0),
			Size = Vector3.new(0.16, 0.16, 0.16) }, CFrame.new(sx * 0.28, 1.1, -1.32))
		bit({ Shape = Enum.PartType.Ball, Color = PAL.FEATH_D, Size = Vector3.new(0.5, 1.0, 1.4) },
			CFrame.new(sx * 0.85, 0.1, 0.1) * CFrame.Angles(0, 0, math.rad(sx * 14)))  -- wings
		bit({ Color = PAL.BEAK, Size = Vector3.new(0.14, 0.85, 0.14) }, CFrame.new(sx * 0.35, -1.05, 0))
		bit({ Color = PAL.BEAK, Size = Vector3.new(0.4, 0.1, 0.5) }, CFrame.new(sx * 0.35, -1.5, -0.1))
	end
	m.PrimaryPart = body
	m.WorldPivot = at
	m.Parent = bakeFolder

	-- ONE nest for the flock, planted at the spawn block: it explains where the eggs come from
	-- and gives the wandering somewhere to read as "home". Built with the first hen only --
	-- three nests stacked on the same marker is a pile of straw, not a coop.
	if index == 1 then
		local nest = Instance.new("Model")
		nest.Name = "ChickenNest"; nest.Parent = bakeFolder
		nestModel = nest
		local ng = (zoneTopY and Vector3.new(originPos.X, zoneTopY, originPos.Z))
			or groundAt(originPos.X, originPos.Z, originPos.Y + 5) or originPos
		local ncf = CFrame.new(ng + Vector3.new(0, 0.3, 0))
		local pad = mk({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(214, 178, 110),
			Size = Vector3.new(0.6, 4.6, 4.6), Parent = nest })
		pad.CFrame = ncf * CFrame.Angles(0, 0, math.rad(90))
		for i = 1, 8 do
			local a = (i / 8) * math.pi * 2
			local straw = mk({ Color = Color3.fromRGB(190, 152, 88),
				Size = Vector3.new(0.4, 0.5, 1.7), Parent = nest })
			straw.CFrame = ncf * CFrame.new(math.cos(a) * 2.0, 0.35, math.sin(a) * 2.0)
				* CFrame.Angles(0, -a, math.rad(14))
		end
	end

	-- SHE HAS TO BE FINDABLE. Every scattered ingredient carries a gold outline; the one
	-- item that is NOT scattered -- and the only hard blocker in the whole quest -- carried
	-- nothing, so a player who missed the Baker's line had a chicken indistinguishable from
	-- island wildlife. Outline plus a floating hint, and BOTH go off the moment the eggs are
	-- in: a permanent marker on something you are done with is just clutter.
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1; hl.OutlineColor = PAL.GLOW_H; hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Enabled = false
	hl.Adornee = m; hl.Parent = m

	local tag = Instance.new("BillboardGui")
	tag.Name = "EggHint"; tag.Adornee = head; tag.Size = UDim2.new(0, 210, 0, 48)
	tag.StudsOffset = Vector3.new(0, 3.4, 0); tag.AlwaysOnTop = true
	tag.MaxDistance = 300; tag.Enabled = false; tag.Parent = m
	do
		local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = PAL.PANEL; f.BackgroundTransparency = 0.1
		f.BorderSizePixel = 0; f.Parent = tag
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 14)
		local st = Instance.new("UIStroke"); st.Color = PAL.CRUST; st.Thickness = 2; st.Parent = f
		local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1; l.Font = Enum.Font.FredokaOne; l.TextScaled = true
		l.TextColor3 = PAL.TEXTC; l.Text = ING.egg.emoji .. " TAP FOR EGGS"; l.Parent = f
		local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = l
	end
	task.spawn(function()
		while m.Parent do
			local want = (step == 2 and stillNeeds("egg"))
			if hl.Enabled ~= want then hl.Enabled = want; tag.Enabled = want end
			task.wait(0.4)
		end
	end)

	-- both input paths on the body AND head: prompt for controller/mobile
	-- radial, ClickDetector for a straight mouse tap
	for _, part in ipairs({ body, head }) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Tap"; prompt.ObjectText = "Chicken"; prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10; prompt.RequiresLineOfSight = false
		prompt.Parent = part
		bigPrompt(prompt)      -- big art; the 10-stud reach stays, you have to go to her
		prompt.Triggered:Connect(function() m:SetAttribute("Tapped", os.clock()) end)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 24; click.Parent = part
		click.MouseClick:Connect(function(who)
			if who == player then m:SetAttribute("Tapped", os.clock()) end
		end)
	end
	return m
end

-- ============================================================================
-- STEADY LIFT -- the per-egg minigame
-- ============================================================================
-- HOLD to raise the egg out of the straw; let go and it settles back. A hold (not a
-- tap) is the point: it's the one input a masher can't beat, and it reads as "careful"
-- rather than "frantic", which is what lifting an egg should feel like.
--
-- The rising ceiling still does the enforcing. `ceiling` climbs 0 -> 1 over exactly
-- EGG_LIFT_SECONDS and clamps the bar every frame, so even a perfect unbroken hold
-- takes the full time -- and slipping costs extra on top.
local EGG_LIFT_SECONDS = 15
local eggLiftOpen = false
local function openEggLift(eggPart, onDone)
	if eggLiftOpen then return end
	eggLiftOpen = true
	bottomHudHold("BakeryEgg", true)   -- the HOLD button lands on top of the fart button otherwise

	local baseSize = eggPart and eggPart.Size

	local gui = Instance.new("ScreenGui")
	gui.Name = "EggLift"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90; gui.Parent = PlayerGui

	local film = Instance.new("Frame")
	film.Size = UDim2.fromScale(1, 1); film.BackgroundColor3 = Color3.new(0, 0, 0)
	film.BackgroundTransparency = 0.5; film.BorderSizePixel = 0; film.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(400, 260); panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(25, 90, 185); panel.BorderSizePixel = 0; panel.Parent = gui
	-- HOUSE PANEL: the Pet Hub's 700x520 card in the Pet Hub's spot, and the bottom buttons hide
	-- while it is up. See HousePanel.client.luau.
	pcall(_G.housePanel, panel)   -- island15 bake-off minigame
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	local ps = Instance.new("UIStroke", panel); ps.Color = Color3.new(1, 1, 1); ps.Thickness = 3

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -60, 0, 40); title.Position = UDim2.fromOffset(18, 12)
	title.Font = Enum.Font.GothamBold; title.TextSize = 22; title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 215, 0); title.Text = "Lift it carefully"; title.Parent = panel

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1; hint.Size = UDim2.new(1, -36, 0, 22); hint.Position = UDim2.fromOffset(18, 48)
	hint.Font = Enum.Font.Gotham; hint.TextSize = 14; hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Color3.new(1, 1, 1); hint.Text = "Hold the button -- let go and it settles back"; hint.Parent = panel

	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(34, 34); close.Position = UDim2.new(1, -44, 0, 12)
	close.BackgroundColor3 = Color3.fromRGB(220, 70, 70); close.Text = "X"; close.TextColor3 = Color3.new(1, 1, 1)
	close.Font = Enum.Font.GothamBold; close.TextSize = 18; close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -36, 0, 26); track.Position = UDim2.fromOffset(18, 88)
	track.BackgroundColor3 = Color3.fromRGB(12, 50, 110); track.BorderSizePixel = 0; track.Parent = panel
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 8)
	local fillBar = Instance.new("Frame")
	fillBar.Size = UDim2.fromScale(0, 1); fillBar.BackgroundColor3 = Color3.fromRGB(255, 235, 190)
	fillBar.BorderSizePixel = 0; fillBar.Parent = track
	Instance.new("UICorner", fillBar).CornerRadius = UDim.new(0, 8)

	local holdBtn = Instance.new("TextButton")
	holdBtn.Size = UDim2.new(1, -36, 0, 100); holdBtn.Position = UDim2.fromOffset(18, 134)
	holdBtn.BackgroundColor3 = Color3.fromRGB(214, 92, 158); holdBtn.Text = "HOLD"
	holdBtn.TextColor3 = Color3.new(1, 1, 1); holdBtn.Font = Enum.Font.GothamBold; holdBtn.TextSize = 32
	holdBtn.AutoButtonColor = false; holdBtn.Parent = panel
	Instance.new("UICorner", holdBtn).CornerRadius = UDim.new(0, 10)
	local hst = Instance.new("UIStroke", holdBtn); hst.Color = Color3.new(1, 1, 1); hst.Thickness = 2

	local fill, ceiling = 0, 0
	local ceilRate = 1 / EGG_LIFT_SECONDS
	local down, finished = false, false
	local conn

	local function shut(success)
		if finished then return end
		finished = true; eggLiftOpen = false
		bottomHudHold("BakeryEgg", false)
		if conn then conn:Disconnect() end
		if eggPart and eggPart.Parent and baseSize then eggPart.Size = baseSize end
		gui:Destroy()
		onDone(success)
	end

	holdBtn.MouseButton1Down:Connect(function() down = true;  holdBtn.BackgroundColor3 = Color3.fromRGB(255, 140, 195) end)
	holdBtn.MouseButton1Up:Connect(function()   down = false; holdBtn.BackgroundColor3 = Color3.fromRGB(214, 92, 158) end)
	holdBtn.MouseLeave:Connect(function()       down = false; holdBtn.BackgroundColor3 = Color3.fromRGB(214, 92, 158) end)
	close.Activated:Connect(function() shut(false) end)

	conn = RunService.RenderStepped:Connect(function(dt)
		if finished then return end
		ceiling = math.min(1, ceiling + ceilRate * dt)
		-- rises while held, settles back slower than it rises so slipping is a setback, not a reset
		fill = math.clamp(fill + (down and dt * ceilRate or -dt * ceilRate * 0.6), 0, 1)
		fill = math.min(fill, ceiling)
		fillBar.Size = UDim2.fromScale(fill, 1)
		if eggPart and eggPart.Parent and baseSize then
			eggPart.Size = baseSize * (1 + math.sin(os.clock() * 18) * 0.03 * fill)
		end
		if fill >= 1 then shut(true) end
	end)
end

local function layEgg(fromCF)
	-- the egg pops out the BACK, arcs to the ground, and sits there with a prompt.
	-- With the base plate known, the egg seats on its stored top Y (clamped inside
	-- the footprint) rather than trusting a ray fired from inside the hen.
	local behind = fromCF * CFrame.new(0, 0.2, 2.0)
	local g
	if zoneCF and zoneTopY then
		local p = clampToZone(behind.Position)
		g = Vector3.new(p.X, zoneTopY, p.Z)
	else
		g = groundAt(behind.Position.X, behind.Position.Z, behind.Position.Y)
			or (behind.Position - Vector3.new(0, 1.5, 0))
	end
	local egg = mk({ Shape = Enum.PartType.Ball, Color = PAL.EGGSH,
		Size = Vector3.new(0.75, 0.95, 0.75), CanQuery = true })
	egg.CFrame = behind; egg.Parent = bakeFolder
	local glow = Instance.new("PointLight"); glow.Color = PAL.GLOW_H
	glow.Brightness = 1; glow.Range = 6; glow.Parent = egg
	tween(egg, 0.45, { CFrame = CFrame.new(g + Vector3.new(0, 0.5, 0)) }, Enum.EasingStyle.Bounce)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Lift Carefully"; prompt.ObjectText = "Egg"; prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = egg
	bigPrompt(prompt)
	local taken = false
	-- the reward half, unchanged -- it just runs after the lift now instead of on the tap
	local function takeEgg()
		if taken then return end
		if not egg.Parent then return end   -- despawned while the panel was open
		if step == 2 and stillNeeds("egg") then
			taken = true
			have.egg = (have.egg or 0) + 1
			poofAt(egg.Position, PAL.GLOW_H)
			playSound(SOUND_EGG, 0.5)
			tween(egg, 0.3, { Size = egg.Size * 0.1, Transparency = 1 })
			Debris:AddItem(egg, 0.4)
			refreshBanner()
			if refreshPrompts then refreshPrompts() end
			if allGathered() then
				flashBanner(E_BOWL .. " That's everything! To the MIXING BOWL!", 3)
				if bakerHead then showBubble(bakerHead, "That's the lot! Get mixing!", false) end
			end
		else
			flashBanner(ING.egg.emoji .. " You don't need more eggs right now!", 2)
		end
	end

	prompt.Triggered:Connect(function()
		if taken then return end
		-- the "you don't need eggs" nudge fires BEFORE the panel, not after 15s of holding
		if not (step == 2 and stillNeeds("egg")) then
			flashBanner(ING.egg.emoji .. " You don't need more eggs right now!", 2); return
		end
		prompt.Enabled = false
		openEggLift(egg, function(success)
			if success then takeEgg()
			-- re-arm behind the same guard the trigger uses
			elseif not taken and egg.Parent and prompt.Parent then prompt.Enabled = true end
		end)
	end)
	-- An unwanted egg tidies itself away. 45s, not 25s: taking one now costs a 15s lift on
	-- top of the walk over, and the old window could delete the egg out from under an open
	-- panel. The wait-loop is the belt to that braces -- never despawn mid-lift.
	task.delay(45, function()
		while eggLiftOpen do task.wait(0.5) end
		if egg.Parent and not taken then
			poofAt(egg.Position, PAL.EGGSH); egg:Destroy()
		end
	end)
end

-- one brain, driven by Heartbeat waits: stroll to a point near home, pause and
-- peck, repeat -- and on a tap, squawk + hop + egg + flee. All PivotTo on an
-- anchored model, so nothing here can be shoved off the island.
local function runChicken(rec)
	task.spawn(function()
		local m = rec.model
		while m and m.Parent do
			local dt = task.wait(0.05)
			rec.t += dt
			local now = os.clock()

			-- a tap? (attribute set by prompt/click handlers on THIS hen's parts)
			local tapped = m:GetAttribute("Tapped")
			if tapped and tapped > rec.lastTap and now - rec.lastLay >= EGG_COOLDOWN then
				rec.lastTap = tapped; rec.lastLay = now
				local cf = m:GetPivot()
				showBubble(m.PrimaryPart, "BAWK!!", false)
				playAt(SOUND_BAWK, m.PrimaryPart, 0.7, 130)
				if FX.send then FX.send("egg", cf.Position) end   -- everyone hears that hen
				poofAt(cf.Position + Vector3.new(0, 0.6, 0), PAL.FEATHER)   -- feathers fly
				-- hop first, THEN the egg -- the hop sells the effort
				task.spawn(function() task.wait(0.25); layEgg(m:GetPivot()) end)
				rec.fleeUntil = now + 1.6
				-- flee AWAY from the player -- but never out of the pen
				local hrp = hrpOf()
				local away = hrp and (cf.Position - hrp.Position) * Vector3.new(1, 0, 1) or Vector3.new(1, 0, 0)
				away = away.Magnitude > 0.5 and away.Unit or Vector3.new(1, 0, 0)
				rec.target = clampToPen(cf.Position + away * 18)
				rec.mode = "flee"
			end

			if rec.mode == "flee" and now >= rec.fleeUntil then rec.mode = "stroll" end
			if rec.mode == "pause" and now >= rec.pauseUntil then
				rec.mode = "stroll"
				rec.target = pickWanderTarget(now, rec)
			end

			local flat = (rec.target - rec.pos) * Vector3.new(1, 0, 1)
			local dist = flat.Magnitude
			if rec.mode ~= "pause" then
				if dist < 1.5 then
					rec.mode = "pause"
					rec.pauseUntil = now + 1.2 + ((now + rec.phase) % 2)
				else
					local speed = (rec.mode == "flee") and 16 or 6
					local stepv = flat.Unit * math.min(dist, speed * dt)
					if obstacleAhead(rec.pos, stepv) then
						-- something solid in the way: stop short and pick a new
						-- destination on the next tick rather than walking into it
						rec.mode = "pause"
						rec.pauseUntil = now + 0.4
					else
						-- ⚠ clampToPen ON EVERY STEP, not only on the destination. A boundary
						-- applied to targets alone is one the hen walks straight through on her
						-- way to a target that happens to be inside it -- and the flee dash, at
						-- 16 studs/sec, is exactly when she would leave.
						rec.pos = clampToPen(rec.pos + stepv)
						rec.yaw = math.atan2(-stepv.X, -stepv.Z)
					end
				end
			end

			local y
			if zoneCF and zoneTopY then
				y = zoneTopY + 1.55            -- the base plate IS the floor
			else
				local g = groundAt(rec.pos.X, rec.pos.Z, chickenOrigin.Y + 10)
				y = g and (g.Y + 1.55) or (chickenOrigin.Y + 1.55)
			end
			local t = rec.t
			local wob = (rec.mode == "pause") and 0 or 1
			local hopY = 0
			if now - rec.lastLay < 0.35 then hopY = math.sin((now - rec.lastLay) / 0.35 * math.pi) * 1.6 end
			local peck = (rec.mode == "pause") and math.max(0, math.sin(t * 3)) * 18 or 0
			m:PivotTo(CFrame.new(rec.pos.X, y + math.abs(math.sin(t * 9)) * 0.16 * wob + hopY, rec.pos.Z)
				* CFrame.Angles(0, rec.yaw, 0)
				* CFrame.Angles(math.rad(peck * 0.4), 0, math.sin(t * 9) * 0.06 * wob))

			-- ===== THE ODD CLUCK AS SHE TROTS PAST =====
			-- Same voice as the tap, quieter and shorter-ranged. Three gates, all needed: she has
			-- to be MOVING (a hen standing still pecking is not passing anybody), she has to be
			-- NEAR you, and each hen keeps her own cooldown. Without the cooldown three hens in a
			-- small pen on a 20-per-second tick is not a farmyard, it is a headache.
			local nearHrp = hrpOf()
			if nearHrp and rec.mode ~= "pause" and now - (rec.lastCluck or 0) >= 6 then
				local d = ((rec.pos - nearHrp.Position) * Vector3.new(1, 0, 1)).Magnitude
				if d < 26 and math.random() < 0.008 then
					rec.lastCluck = now
					playAt(SOUND_BAWK, m.PrimaryPart, 0.35, 70)
				end
			end
		end
	end)
end

-- build the whole flock around the coop and set them walking
local function spawnFlock()
	findPen()
	for i = 1, CHICKEN_COUNT do
		-- fanned out around the coop so they do not all appear inside each other on frame one
		local a = (i - 1) * (math.pi * 2 / CHICKEN_COUNT)
		local start = clampToPen(chickenOrigin + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5))
		local rec = {
			model = buildChicken(start, i),
			phase = (i - 1) * 2.1,      -- staggers every clock-derived decision she makes
			pos = start, yaw = a, t = i * 0.7,
			mode = "stroll", target = start,
			pauseUntil = 0, fleeUntil = 0, lastLay = 0, lastTap = 0,
		}
		chickens[#chickens + 1] = rec
		runChicken(rec)
	end
	print(("[Bakery] %d hen(s) roaming %s"):format(#chickens,
		penCF and "the drawn pen" or ("a " .. WANDER_R .. "-stud circle around the coop")))
end

-- ============================================================================
-- THE MIXING STATION -- built on your "Mixer" part
-- ============================================================================
local mixPrompt, batterDisc, spoonModel, spoonHome, bowlTopCF
local mixerModel                                   -- the whole station, for prompt reach
-- forward: the mixing HUD is built below doStir (it needs to call it), but startMixing and
-- doStir both sit above and drive it.
local openMixHUD, closeMixHUD, updateMixHUD

local function buildMixer(part)
	local at = baseFrameOf(part)
	hideMarker(part)
	mixerAt = at
	-- a Model, not a Folder: the whole station is scaled up MIXER_SCALE at the end,
	-- and ScaleTo needs a Model with its pivot on the ground line to grow in place
	local f = Instance.new("Model"); f.Name = "MixingStation"; f.Parent = bakeFolder
	local function piece(props, where, parent)
		props.Parent = parent or f
		local p = mk(props); p.CFrame = where; return p
	end

	-- sturdy wooden counter for the bowl to sit on
	piece({ Color = PAL.WOOD, Size = Vector3.new(7.5, 0.7, 6.0), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 2.4, 0))
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(7.9, 0.25, 6.4) }, at * CFrame.new(0, 2.85, 0))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.7, 2.2, 0.7), CanCollide = true },
				at * CFrame.new(sx * 3.2, 1.1, sz * 2.4))
		end
	end

	-- THE BOWL: a fat cream cylinder with a rolled rim and a batter disc inside.
	-- The batter starts invisible and fades in as the ingredients go in.
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.CREAM, Size = Vector3.new(2.6, 5.2, 5.2),
		CastShadow = true }, at * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.PINK, Size = Vector3.new(0.5, 5.5, 5.5) },
		at * CFrame.new(0, 5.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.CHOC_D, Size = Vector3.new(0.2, 4.6, 4.6) },
		at * CFrame.new(0, 5.35, 0) * CFrame.Angles(0, 0, math.rad(90)))
	batterDisc = piece({ Shape = Enum.PartType.Cylinder, Color = PAL.CHOC,
		Size = Vector3.new(0.3, 4.4, 4.4), Transparency = 1 },
		at * CFrame.new(0, 5.42, 0) * CFrame.Angles(0, 0, math.rad(90)))
	bowlTopCF = at * CFrame.new(0, 6.4, 0)

	-- the wooden spoon, standing in the bowl; it sweeps a lap on every stir
	spoonModel = Instance.new("Model"); spoonModel.Name = "Spoon"; spoonModel.Parent = f
	spoonHome = at * CFrame.new(1.2, 6.6, 0) * CFrame.Angles(0, 0, math.rad(-16))
	local shaft = piece({ Color = PAL.WOOD, Size = Vector3.new(0.28, 3.4, 0.28) }, spoonHome, spoonModel)
	piece({ Shape = Enum.PartType.Ball, Color = PAL.WOOD_D, Size = Vector3.new(0.85, 1.1, 0.55) },
		spoonHome * CFrame.new(0, -1.85, 0), spoonModel)
	spoonModel.PrimaryPart = shaft
	spoonModel.WorldPivot = at * CFrame.new(0, 6.0, 0)      -- pivot at the bowl centre: PivotTo
	                                                        -- with a yaw = the spoon orbits

	-- set dressing: flour sack, sugar jar, a recipe card on a little stand
	piece({ Color = PAL.CREAM, Size = Vector3.new(1.6, 2.0, 1.4), CanCollide = true },
		at * CFrame.new(-2.6, 1.0, 2.9) * CFrame.Angles(0, math.rad(15), 0))
	piece({ Color = PAL.CRUST, Size = Vector3.new(1.7, 0.4, 1.5) },
		at * CFrame.new(-2.6, 2.0, 2.9) * CFrame.Angles(0, math.rad(15), math.rad(6)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.SUGAR, Size = Vector3.new(1.1, 0.9, 0.9) },
		at * CFrame.new(2.8, 3.35, 2.2) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.15, 1.2, 1.6) },
		at * CFrame.new(3.3, 3.6, -1.8) * CFrame.Angles(0, math.rad(-25), math.rad(-12)))
	piece({ Color = PAL.CREAM, Size = Vector3.new(0.08, 1.0, 1.4) },
		at * CFrame.new(3.28, 3.62, -1.8) * CFrame.Angles(0, math.rad(-25), math.rad(-12)))

	-- pans and a rolling pin left out on the counter: a kitchen mid-shift, not a prop
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.3, 1.7, 1.7) },
		at * CFrame.new(-2.5, 3.05, -1.9) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.3, 1.4, 1.4) },
		at * CFrame.new(-2.3, 3.4, -1.7) * CFrame.Angles(0, 0, math.rad(90)))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD, Size = Vector3.new(2.4, 0.42, 0.42) },
		at * CFrame.new(2.4, 3.1, -0.9) * CFrame.Angles(0, math.rad(20), 0))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D, Size = Vector3.new(0.5, 0.3, 0.3) },
		at * CFrame.new(1.15, 3.1, -1.35) * CFrame.Angles(0, math.rad(20), 0))

	-- a hanging BAKERY sign over the walk-up side: at this scale the station is
	-- a landmark, so it should say what it is from across the island
	for _, sx in ipairs({ -1, 1 }) do
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.4, 6.2, 0.4), CanCollide = true },
			at * CFrame.new(sx * 2.6, 3.1, -3.6))
	end
	local board = piece({ Color = PAL.WOOD_D, Size = Vector3.new(6.4, 1.5, 0.3), CastShadow = true },
		at * CFrame.new(0, 5.6, -3.6))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(640, 150); sg.Parent = board
	local signText = Instance.new("TextLabel")
	signText.BackgroundTransparency = 1; signText.Size = UDim2.fromScale(1, 1)
	signText.Font = Enum.Font.FredokaOne; signText.TextScaled = true
	signText.TextColor3 = PAL.CREAM; signText.Text = "THE BAKERY"; signText.Parent = sg

	-- THE PROMPT BOX LIVES OUTSIDE THE SCALED MODEL, at player height in front of
	-- the counter. Inside the model it grew with the station, which hoisted the
	-- floating [E] to the giant bowl's rim -- pretty, and unreachable. A roomy
	-- (not huge) box at the walk-up side keeps the prompt at eye level.
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(16, 10, 9),
		CFrame = at * CFrame.new(0, 5, -(3.0 * MIXER_SCALE + 3)), Parent = bakeFolder })
	mixPrompt = Instance.new("ProximityPrompt")
	mixPrompt.ActionText = "Mix"; mixPrompt.ObjectText = "Mixing Bowl"
	mixPrompt.HoldDuration = 0.3
	mixPrompt.RequiresLineOfSight = false; mixPrompt.Enabled = false; mixPrompt.Parent = hit
	mixerModel = f

	-- GROW THE WHOLE STATION. Scaled about a pivot on the ground line, so the legs
	-- stay planted and everything above them gets bigger -- then every frame the
	-- animations rely on is recomputed at the same scale, or the blobs would pour
	-- into where the small bowl used to be.
	local S = MIXER_SCALE
	f.WorldPivot = at
	f:ScaleTo(S)
	-- NOT PASS-THROUGH-ABLE: every visible part goes solid, and queryable so the
	-- chicken's obstacle feeler can see the walls too. (The batter disc starts
	-- invisible, so it stays walk-through -- it lives inside the bowl anyway.)
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.CanCollide = true; d.CanQuery = true
		end
	end
	bowlTopCF  = at * CFrame.new(0, 6.4 * S, 0)
	spoonHome  = at * CFrame.new(1.2 * S, 6.6 * S, 0) * CFrame.Angles(0, 0, math.rad(-16))
	spoonModel.WorldPivot = at * CFrame.new(0, 6.0 * S, 0)

	-- ⚠ REACH IS MEASURED AFTER ScaleTo, NOT BEFORE. The station is five times bigger by this
	-- line, and a bounding box read one line earlier would size the trigger to the model as it
	-- was DRAWN rather than as it stands. Half the grown model's diagonal plus a walk-up margin
	-- means E answers from the far edge of the counter -- and it re-derives itself if
	-- MIXER_SCALE ever changes, instead of needing the old hand-tuned 18 re-tuned.
	bigPrompt(mixPrompt, f, 16)
	print(("[Bakery] mixing station built on '%s' (x%.1f, seated on the marker's base, "
		.. "E reaches %.0f studs)"):format(part:GetFullName(), S, mixPrompt.MaxActivationDistance))
end

-- ingredients arc into the bowl one at a time, then the stirring begins
local function startMixing()
	step = 3; stirs = 0
	refreshBanner(); refreshPrompts()
	mixPrompt.Enabled = false
	local R = RECIPES[recipe]
	task.spawn(function()
		local need, i = needOf(), 0
		for _, kind in ipairs(ING_ORDER) do
			for _ = 1, (need[kind] or 0) do
				i += 1
				local n = i     -- captured per blob: `i` itself has hit its final value
				                -- long before the first task.delay callback ever runs
				task.delay(n * 0.28, function()
					-- a stand-in prop pops above the bowl and drops in with a puff,
					-- sized to the GROWN bowl or it reads as a crumb falling in
					local MS = math.max(1, MIXER_SCALE * 0.55)
					local start = bowlTopCF
						* CFrame.new(math.cos(n * 2.4) * 2.5 * MS, 4 * MS, math.sin(n * 2.4) * 2.5 * MS)
					local blob = mk({ Shape = Enum.PartType.Ball,
						Color = (kind == "egg" and PAL.EGGSH) or (kind == "sugar" and PAL.SUGAR)
							or (kind == "butter" and PAL.BUTTER) or (kind == "dough" and PAL.DOUGHY)
							or PAL.CHOC,
						Size = Vector3.new(0.9, 0.9, 0.9) * MS })
					blob.CFrame = start; blob.Parent = bakeFolder
					-- sink to just above the batter disc: the rim-to-batter gap grows
					-- with the station, so the drop depth has to as well
					local drop = tween(blob, 0.4,
						{ CFrame = bowlTopCF * CFrame.new(0, -0.95 * MIXER_SCALE, 0) },
						Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					drop.Completed:Connect(function()
						poofAt(bowlTopCF.Position, blob.Color)
						playAt(SOUND_POUR, batterDisc, 0.45, 90)
						blob:Destroy()
						-- the batter creeps up as things go in
						batterDisc.Transparency = math.max(0, 1 - (n / 8) * 1.2)
					end)
				end)
			end
		end
		local total = 0
		for _, n in pairs(need) do total += n end
		task.delay(total * 0.28 + 0.7, function()
			batterDisc.Transparency = 0
			batterDisc.Color = R.batter:Lerp(Color3.new(1, 1, 1), 0.25)  -- pale until stirred
			mixPrompt.ActionText = "Stir!"; mixPrompt.HoldDuration = 0
			mixPrompt.Enabled = true
			-- THE HUD IS THE JOB NOW. You stand anywhere near the station and stir in the
			-- panel; the E prompt still works and does exactly the same thing, so nothing
			-- is lost for a player who never looks at the screen.
			if openMixHUD then openMixHUD(R.title) end
			flashBanner(E_BOWL .. " Now STIR!  Use the panel -- or press E!", 3)
		end)
	end)
end

local function doStir()
	stirs += 1
	refreshBanner()
	playSound(SOUND_STIR, 0.5)
	local R = RECIPES[recipe]
	-- the spoon takes a lap round the bowl; the batter darkens toward done
	local from = (stirs - 1) / STIRS_NEEDED
	batterDisc.Color = R.batter:Lerp(Color3.new(1, 1, 1), 0.25 * (1 - stirs / STIRS_NEEDED))
	if spoonModel and spoonModel.Parent then
		task.spawn(function()
			for a = 1, 10 do
				spoonModel:PivotTo(spoonModel.WorldPivot
					* CFrame.Angles(0, math.rad((from * 360) + a * 36), 0)
					* spoonModel.WorldPivot:ToObjectSpace(spoonHome))
				task.wait(0.03)
			end
		end)
	end
	poofAt(bowlTopCF.Position + Vector3.new(math.cos(stirs * 2.2) * 1.6, -0.4, math.sin(stirs * 2.2) * 1.6)
		* math.max(1, MIXER_SCALE * 0.55), R.batter)
	if FX.send then FX.send("stir", bowlTopCF.Position) end   -- the bowl splashes for everyone
	mixPrompt.ActionText = ("Stir!  (%d/%d)"):format(stirs, STIRS_NEEDED)
	if updateMixHUD then updateMixHUD() end

	-- the cooldown IS the enforcement: dead prompt between stirs, so mashing buys nothing.
	-- Re-armed behind the SAME guard the rest of the file uses, or a finished bowl re-arms.
	-- ⚠ THE HUD BUTTON READS mixPrompt.Enabled, so it goes dead on the same beat -- otherwise
	-- the panel would be a way to mash straight past the cadence the prompt exists to impose.
	if stirs < STIRS_NEEDED then
		mixPrompt.Enabled = false
		if updateMixHUD then updateMixHUD() end
		task.delay(STIR_CD, function()
			if step == 3 and stirs < STIRS_NEEDED then
				mixPrompt.Enabled = true
				if updateMixHUD then updateMixHUD() end
			end
		end)
	end

	if stirs >= STIRS_NEEDED then
		mixPrompt.Enabled = false
		mixPrompt.ActionText = "Mix"
		if closeMixHUD then closeMixHUD() end
		flashBanner(E_SPARK .. " Perfect batter! Into the pan it goes...", 3)
		-- the batter drains into a pan that lands in your hands
		tween(batterDisc, 0.8, { Transparency = 1 })
		task.delay(0.8, function()
			step = 4
			giveHeld("pan")
			refreshBanner(); refreshPrompts()
			if bakerHead then showBubble(bakerHead, "Beautiful! Now bake it -- either oven!", false) end
		end)
	end
end

-- ============================================================================
-- THE MIXING HUD -- FOLD THE BATTER ON THE BEAT
-- ============================================================================
-- ⚠ THE OLD TASK WAS A COOLDOWN WITH A BUTTON ON IT. Tap, wait a second, tap, fourteen times.
-- Nothing was ever asked of the player but patience, and the panel could not possibly be better
-- than the E prompt because it WAS the E prompt with a bigger hitbox.
--
-- THE TASK NOW: YOU ACTUALLY STIR IT. There is a bowl in the panel and a spoon in the bowl.
-- Hold the pointer down on it and drag round in circles -- mouse, finger, either -- and the spoon
-- follows your hand. Every full lap of the bowl is one fold of the batter.
--   * it is a real motion, not a button: the thing your hand does is the thing the spoon does,
--   * laps only count out near the rim, so scribbling in the middle earns nothing,
--   * going back the other way UNWINDS the lap you were on, exactly like stirring would,
--   * and a lap cannot be flicked through faster than 0.35s, which is as fast as a spoon goes.
--
-- The batter darkens and the swirl speeds up as it comes together, so the bowl itself tells you
-- how far along you are. The E prompt out in the world still does one plain fold per cooldown --
-- nothing is lost for a player who never opens the panel, and the STIR button on the panel is
-- that same cadence tap for anyone who would rather not drag.
local MH = { angle = 0, lastAngle = nil, turn = 0, spin = 0, drag = false, lockUntil = 0,
	streak = 0, lastStirs = 0 }
do
	local g = Instance.new("ScreenGui")
	g.Name = "BakeryMixHUD"; g.ResetOnSpawn = false; g.DisplayOrder = 12
	g.Enabled = false; g.Parent = PlayerGui
	MH.gui = g

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1); panel.Position = UDim2.new(0.5, 0, 1, -24)
	panel.Size = UDim2.new(0, 560, 0, 420); panel.BackgroundColor3 = PAL.PANEL
	panel.BorderSizePixel = 0; panel.Parent = g
	-- HOUSE PANEL: the Pet Hub's 700x520 card at (0.5,0),(0.5,-45), and the bottom
	-- buttons hide while it is up. One call does both -- see HousePanel.client.luau.
	-- The panel keeps its own size and every child keeps its own pixel coordinates;
	-- it is centred in the house shell and scaled to fit, so nothing inside moves.
	pcall(_G.housePanel, panel)   -- island15 mixing bowl
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	do local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 3; s.Parent = panel end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 20, 0, 12)
	title.Size = UDim2.new(1, -90, 0, 32); title.Font = Enum.Font.FredokaOne
	title.TextSize = 24; title.TextColor3 = PAL.TEXTC
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = panel
	MH.title = title

	-- X only. A stray tap on the backdrop must never shut a panel in this realm.
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0); close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(38, 38); close.BackgroundColor3 = PAL.CRUST
	close.Text = "X"; close.Font = Enum.Font.FredokaOne; close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1); close.BorderSizePixel = 0; close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
	close.Activated:Connect(function() if closeMixHUD then closeMixHUD() end end)

	local pLab = Instance.new("TextLabel")
	pLab.BackgroundTransparency = 1; pLab.Position = UDim2.new(0, 20, 0, 50)
	pLab.Size = UDim2.new(1, -40, 0, 18); pLab.Font = Enum.Font.GothamBold
	pLab.TextSize = 14; pLab.TextColor3 = PAL.HINTC
	pLab.TextXAlignment = Enum.TextXAlignment.Left; pLab.Text = "FOLDED  0/0"; pLab.Parent = panel
	MH.plabel = pLab
	local pTrack = Instance.new("Frame")
	pTrack.Position = UDim2.new(0, 20, 0, 72); pTrack.Size = UDim2.new(1, -40, 0, 24)
	pTrack.BackgroundColor3 = Color3.fromRGB(240, 224, 206); pTrack.BorderSizePixel = 0
	pTrack.Parent = panel
	Instance.new("UICorner", pTrack).CornerRadius = UDim.new(1, 0)
	local pFill = Instance.new("Frame")
	pFill.Size = UDim2.new(0, 0, 1, 0); pFill.BackgroundColor3 = PAL.CHOC_HI
	pFill.BorderSizePixel = 0; pFill.Parent = pTrack
	Instance.new("UICorner", pFill).CornerRadius = UDim.new(1, 0)
	MH.fill = pFill

	-- ===== THE BOWL =====
	-- Seen from above, and it is a real target: you press on it and drag round it. Everything in
	-- here is a circle made with a full-radius UICorner -- no images, nothing to load.
	local bowl = Instance.new("Frame")
	bowl.Name = "Bowl"
	bowl.AnchorPoint = Vector2.new(0.5, 0); bowl.Position = UDim2.new(0.5, 0, 0, 104)
	bowl.Size = UDim2.fromOffset(200, 200); bowl.BackgroundColor3 = Color3.fromRGB(228, 214, 196)
	bowl.BorderSizePixel = 0; bowl.Active = true; bowl.Parent = panel
	Instance.new("UICorner", bowl).CornerRadius = UDim.new(1, 0)
	do local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 5; s.Parent = bowl end
	MH.bowl = bowl

	local batter = Instance.new("Frame")
	batter.AnchorPoint = Vector2.new(0.5, 0.5); batter.Position = UDim2.fromScale(0.5, 0.5)
	batter.Size = UDim2.fromOffset(164, 164); batter.BackgroundColor3 = PAL.DOUGHY
	batter.BorderSizePixel = 0; batter.Parent = bowl
	Instance.new("UICorner", batter).CornerRadius = UDim.new(1, 0)
	MH.batter = batter

	-- three blobs riding the swirl. Rotating ONE ring of blobs is what makes the batter look
	-- turned rather than tinted -- a flat disc changing colour reads as a progress bar.
	local swirl = {}
	for i = 1, 3 do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5); b.Size = UDim2.fromOffset(38 - i * 6, 38 - i * 6)
		b.BackgroundColor3 = PAL.CHOC_HI; b.BackgroundTransparency = 0.25
		b.BorderSizePixel = 0; b.ZIndex = 2; b.Parent = batter
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		swirl[i] = b
	end

	local spoon = Instance.new("Frame")
	spoon.Name = "Spoon"
	spoon.AnchorPoint = Vector2.new(0.5, 0.5); spoon.Size = UDim2.fromOffset(20, 62)
	spoon.BackgroundColor3 = PAL.WOOD; spoon.BorderSizePixel = 0; spoon.ZIndex = 4
	spoon.Parent = bowl
	Instance.new("UICorner", spoon).CornerRadius = UDim.new(0, 9)
	do local s = Instance.new("UIStroke"); s.Color = PAL.WOOD_D; s.Thickness = 2; s.Parent = spoon end
	MH.spoon = spoon

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1; hint.Position = UDim2.new(0, 20, 0, 312)
	hint.Size = UDim2.new(1, -40, 0, 22); hint.Font = Enum.Font.GothamBold
	hint.TextSize = 15; hint.TextColor3 = PAL.HINTC; hint.Text = ""; hint.Parent = panel
	MH.hint = hint

	-- The button is the OLD way, kept: one fold per press on the same cooldown the E prompt uses,
	-- for anyone who would rather not drag (and for a controller, which has no drag).
	local stir = Instance.new("TextButton")
	stir.AnchorPoint = Vector2.new(0.5, 1); stir.Position = UDim2.new(0.5, 0, 1, -16)
	stir.Size = UDim2.new(0, 300, 0, 56); stir.BackgroundColor3 = PAL.CHOC_HI
	stir.Font = Enum.Font.FredokaOne; stir.TextSize = 22
	stir.TextColor3 = Color3.new(1, 1, 1); stir.BorderSizePixel = 0
	stir.AutoButtonColor = false
	stir.Text = E_BOWL .. " STIR"; stir.Parent = panel
	Instance.new("UICorner", stir).CornerRadius = UDim.new(0, 16)
	MH.stir = stir

	-- the panel's own task is live whenever there is batter to fold; the BUTTON additionally
	-- waits on the prompt's cooldown, because tapping it is the prompt with a bigger hitbox
	local function armed() return step == 3 and stirs < STIRS_NEEDED end
	MH.armed = armed

	local function fold()
		if not armed() then return end
		if os.clock() < (MH.lockUntil or 0) then return end
		MH.lockUntil = os.clock() + 0.35            -- a spoon does not go round faster than this
		MH.streak += 1
		doStir()
	end

	stir.Activated:Connect(function()
		if not (armed() and mixPrompt and mixPrompt.Enabled) then return end
		stir.Size = UDim2.new(0, 288, 0, 52)
		tween(stir, 0.18, { Size = UDim2.new(0, 300, 0, 56) }, Enum.EasingStyle.Back)
		MH.turn = 0                                  -- a tapped fold restarts the lap you were on
		fold()
	end)

	-- ===== DRAGGING ROUND THE BOWL =====
	-- (!) THE POINTER IS TRACKED GLOBALLY, not on the bowl. Circling drags the pointer off the
	-- bowl and back constantly, and a GUI object only reports input while the pointer is over it
	-- -- tracked that way the stir dies the first time your hand goes wide.
	--
	-- (!) AND THE INSET IS SUBTRACTED. InputObject.Position is raw screen space (it counts the
	-- 36px topbar); AbsolutePosition on a normal ScreenGui does not. Skip this and the bowl's
	-- centre is 36px off, which tilts every angle and makes laps near the top of the bowl count
	-- twice or not at all.
	local function pointerAngle(inputPos)
		local inset = game:GetService("GuiService"):GetGuiInset()
		local px, py = inputPos.X - inset.X, inputPos.Y - inset.Y
		local c = bowl.AbsolutePosition + bowl.AbsoluteSize * 0.5
		local dx, dy = px - c.X, py - c.Y
		local r = math.sqrt(dx * dx + dy * dy) / math.max(1, bowl.AbsoluteSize.X * 0.5)
		return math.atan2(dy, dx), r
	end

	bowl.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		MH.drag = true
		MH.lastAngle = (pointerAngle(input.Position))
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			MH.drag = false; MH.lastAngle = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not (g.Enabled and MH.drag) then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local a, r = pointerAngle(input.Position)
		MH.angle = a
		-- OUT NEAR THE RIM ONLY. Scribbling in the middle of the bowl covers a full circle in a
		-- few pixels; a spoon has to travel to fold anything.
		if r < 0.35 or r > 1.9 then MH.lastAngle = a; return end
		if MH.lastAngle then
			local d = a - MH.lastAngle
			while d > math.pi do d -= math.pi * 2 end       -- unwrap: -pi..pi is one hand movement
			while d < -math.pi do d += math.pi * 2 end
			if math.abs(d) < 1.2 then                       -- a bigger jump is a teleporting cursor
				MH.turn += d
				MH.spin += d
				if math.abs(MH.turn) >= math.pi * 2 then
					MH.turn -= (MH.turn > 0 and 1 or -1) * math.pi * 2
					fold()
				end
			end
		end
		MH.lastAngle = a
	end)

	-- ONE HEARTBEAT PAINTS THE BOWL, and it early-returns the moment the panel is shut, so a
	-- closed HUD costs one comparison a frame and nothing else.
	RunService.Heartbeat:Connect(function(dt)
		if not g.Enabled then return end
		-- a fold from ANY route (a lap, the button, E out in the world) resets the lap you are on,
		-- so the two never drift apart
		if stirs ~= MH.lastStirs then
			MH.lastStirs = stirs
			MH.turn = 0
		end
		-- the batter keeps turning for a moment after you stop, then settles
		if not MH.drag then MH.spin += dt * 1.2 * (0.3 + stirs / STIRS_NEEDED) end
		local done = stirs / STIRS_NEEDED
		local R = RECIPES[recipe]
		if R then
			batter.BackgroundColor3 = R.batter:Lerp(Color3.new(1, 1, 1), 0.3 * (1 - done))
		end
		-- the spoon sits where your hand is while you drag, and idles round the rim when you stop
		local a = MH.drag and MH.angle or (MH.spin * 0.6)
		local rad = bowl.AbsoluteSize.X * 0.29
		spoon.Position = UDim2.new(0.5, math.cos(a) * rad, 0.5, math.sin(a) * rad)
		spoon.Rotation = math.deg(a) + 90
		for i, b in ipairs(swirl) do
			local ba = MH.spin * (1 + i * 0.22) + i * 2.1
			local br = bowl.AbsoluteSize.X * (0.09 + i * 0.055)
			b.Position = UDim2.new(0.5, math.cos(ba) * br, 0.5, math.sin(ba) * br)
			b.BackgroundTransparency = 0.15 + 0.25 * (1 - done)
		end
		-- the lap you are on, drawn as the progress bar filling ahead of itself
		local lap = math.abs(MH.turn) / (math.pi * 2)
		MH.fill.Size = UDim2.new(math.min(1, (stirs + lap) / STIRS_NEEDED), 0, 1, 0)
	end)
end

openMixHUD = function(what)
	MH.title.Text = ("Mixing: %s"):format(what or "batter")
	MH.streak, MH.turn, MH.spin, MH.lockUntil, MH.lastStirs = 0, 0, 0, 0, stirs
	MH.drag, MH.lastAngle, MH.angle = false, nil, 0
	MH.gui.Enabled = true
	bottomHudHold("BakeryMix", true)
	updateMixHUD()
end
closeMixHUD = function()
	MH.gui.Enabled = false
	bottomHudHold("BakeryMix", false)
end
updateMixHUD = function()
	if not MH.gui.Enabled then return end
	MH.plabel.Text = ("FOLDED  %d/%d"):format(stirs, STIRS_NEEDED)
	-- (the bar itself is painted by the Heartbeat, which draws the lap you are part-way through)
	local live = MH.armed()
	local tappable = live and mixPrompt and mixPrompt.Enabled
	MH.stir.BackgroundColor3 = tappable and PAL.CHOC_HI or Color3.fromRGB(206, 194, 182)
	MH.stir.Text = tappable and (E_BOWL .. " STIR") or (E_BOWL .. " ...")
	MH.hint.Text = live and "Hold on the bowl and stir round and round!"
		or "That's the batter -- into the pan!"
	MH.hint.TextColor3 = PAL.HINTC
end

-- ============================================================================
-- THE OVEN HUD -- pops up when a pan goes in. One job, one button: heat bleeds
-- away on its own, STOKE throws it back up, and the bake bar only fills fast
-- while the needle holds the orange sweet zone. X closes it and the bake keeps
-- creeping along at the slow rate -- the oven's "Watch" prompt reopens it, so
-- a closed HUD can never strand a bake.
-- ============================================================================
local BH = { stokes = 0 }    -- widgets in one table (same register-budget trick as PAL)
do
	local g = Instance.new("ScreenGui")
	g.Name = "BakeryOvenHUD"; g.ResetOnSpawn = false; g.DisplayOrder = 12
	g.Enabled = false; g.Parent = PlayerGui
	BH.gui = g

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1); panel.Position = UDim2.new(0.5, 0, 1, -30)
	panel.Size = UDim2.new(0, 560, 0, 290); panel.BackgroundColor3 = PAL.PANEL
	panel.BorderSizePixel = 0; panel.Parent = g
	-- HOUSE PANEL: the Pet Hub's 700x520 card at (0.5,0),(0.5,-45), and the bottom
	-- buttons hide while it is up. One call does both -- see HousePanel.client.luau.
	-- The panel keeps its own size and every child keeps its own pixel coordinates;
	-- it is centred in the house shell and scaled to fit, so nothing inside moves.
	pcall(_G.housePanel, panel)   -- island15 oven
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	do local s = Instance.new("UIStroke"); s.Color = PAL.CRUST; s.Thickness = 3; s.Parent = panel end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 20, 0, 12)
	title.Size = UDim2.new(1, -90, 0, 32); title.Font = Enum.Font.FredokaOne
	title.TextSize = 24; title.TextColor3 = PAL.TEXTC
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = panel
	BH.title = title

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0); close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(38, 38); close.BackgroundColor3 = PAL.CRUST
	close.Text = "X"; close.Font = Enum.Font.FredokaOne; close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1); close.BorderSizePixel = 0; close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 12)
	close.Activated:Connect(function() if BH.close then BH.close() end end)

	-- ===== THE BAKE BAR -- how done it is =====
	-- The percentage moved OUT of the little grey caption and onto its own big number at the
	-- right of the row. "How far along am I" is the question this panel exists to answer, and it
	-- was being answered in 14px grey behind the word BAKED.
	local pLab = Instance.new("TextLabel")
	pLab.BackgroundTransparency = 1; pLab.Position = UDim2.new(0, 20, 0, 50)
	pLab.Size = UDim2.new(1, -140, 0, 18); pLab.Font = Enum.Font.GothamBold
	pLab.TextSize = 14; pLab.TextColor3 = PAL.HINTC
	pLab.TextXAlignment = Enum.TextXAlignment.Left; pLab.Text = "BAKED"; pLab.Parent = panel

	local pct = Instance.new("TextLabel")
	pct.BackgroundTransparency = 1; pct.AnchorPoint = Vector2.new(1, 0)
	pct.Position = UDim2.new(1, -20, 0, 42); pct.Size = UDim2.fromOffset(110, 30)
	pct.Font = Enum.Font.FredokaOne; pct.TextSize = 26; pct.TextColor3 = PAL.TEXTC
	pct.TextXAlignment = Enum.TextXAlignment.Right; pct.Text = "0%"; pct.Parent = panel
	BH.plabel = pct

	local pTrack = Instance.new("Frame")
	pTrack.Position = UDim2.new(0, 20, 0, 74); pTrack.Size = UDim2.new(1, -40, 0, 24)
	pTrack.BackgroundColor3 = Color3.fromRGB(240, 224, 206); pTrack.BorderSizePixel = 0
	pTrack.Parent = panel
	Instance.new("UICorner", pTrack).CornerRadius = UDim.new(1, 0)
	local pFill = Instance.new("Frame")
	pFill.Size = UDim2.new(0, 0, 1, 0); pFill.BackgroundColor3 = PAL.CRUST
	pFill.BorderSizePixel = 0; pFill.Parent = pTrack
	Instance.new("UICorner", pFill).CornerRadius = UDim.new(1, 0)
	BH.fill = pFill

	-- ===== THE HEAT BAR =====
	-- The track is painted cold-to-hot underneath, so where the sweet zone SITS is information
	-- too: you can see at a glance that it is the warm middle and not an arbitrary orange stripe.
	local hLab = pLab:Clone()
	hLab.Position = UDim2.new(0, 20, 0, 112); hLab.Text = "OVEN HEAT"; hLab.Parent = panel
	local hTrack = Instance.new("Frame")
	hTrack.Position = UDim2.new(0, 20, 0, 134); hTrack.Size = UDim2.new(1, -40, 0, 34)
	hTrack.BackgroundColor3 = Color3.new(1, 1, 1); hTrack.BorderSizePixel = 0
	hTrack.ClipsDescendants = true; hTrack.Parent = panel
	Instance.new("UICorner", hTrack).CornerRadius = UDim.new(0, 10)
	do
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(126, 172, 226)),   -- stone cold
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(252, 214, 140)),   -- warming
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 158,  70)),   -- baking
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(214,  66,  50)),   -- scorching
		})
		grad.Parent = hTrack
	end

	-- the sweet zone, called out by name -- "keep it in the green" needs no tutorial
	local zone = Instance.new("Frame")
	zone.Position = UDim2.new(ZONE_LO / 100, 0, 0, 0)
	zone.Size = UDim2.new((ZONE_HI - ZONE_LO) / 100, 0, 1, 0)
	zone.BackgroundColor3 = Color3.fromRGB(255, 255, 255); zone.BackgroundTransparency = 0.55
	zone.BorderSizePixel = 0; zone.Parent = hTrack
	Instance.new("UICorner", zone).CornerRadius = UDim.new(0, 8)
	do
		local zs = Instance.new("UIStroke"); zs.Color = Color3.fromRGB(72, 150, 60)
		zs.Thickness = 2.5; zs.Parent = zone
		local zt = Instance.new("TextLabel")
		zt.BackgroundTransparency = 1; zt.Size = UDim2.fromScale(1, 1)
		zt.Font = Enum.Font.GothamBold; zt.TextSize = 12
		zt.TextColor3 = Color3.fromRGB(48, 104, 40); zt.Text = "JUST RIGHT"; zt.Parent = zone
	end

	local needle = Instance.new("Frame")
	needle.AnchorPoint = Vector2.new(0.5, 0.5); needle.Position = UDim2.new(0.65, 0, 0.5, 0)
	needle.Size = UDim2.new(0, 8, 1, 10); needle.BackgroundColor3 = PAL.TEXTC
	needle.BorderSizePixel = 0; needle.ZIndex = 3; needle.Parent = hTrack
	Instance.new("UICorner", needle).CornerRadius = UDim.new(1, 0)
	do local ns = Instance.new("UIStroke"); ns.Color = Color3.new(1, 1, 1); ns.Thickness = 2
		ns.Parent = needle end
	BH.needle = needle

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1; hint.Position = UDim2.new(0, 20, 0, 176)
	hint.Size = UDim2.new(1, -40, 0, 20); hint.Font = Enum.Font.GothamBold
	hint.TextSize = 15; hint.TextColor3 = PAL.HINTC; hint.Text = ""; hint.Parent = panel
	BH.hint = hint

	local stoke = Instance.new("TextButton")
	stoke.AnchorPoint = Vector2.new(0.5, 1); stoke.Position = UDim2.new(0.5, 0, 1, -16)
	stoke.Size = UDim2.new(0, 300, 0, 76); stoke.BackgroundColor3 = PAL.GLOW
	stoke.Font = Enum.Font.FredokaOne; stoke.TextSize = 26
	stoke.TextColor3 = Color3.new(1, 1, 1); stoke.BorderSizePixel = 0
	stoke.AutoButtonColor = false
	stoke.Text = E_FIRE .. " STOKE THE FIRE"; stoke.Parent = panel
	Instance.new("UICorner", stoke).CornerRadius = UDim.new(0, 16)
	do local ss = Instance.new("UIStroke"); ss.Color = PAL.CRUST; ss.Thickness = 3
		ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ss.Parent = stoke end
	BH.stoke = stoke
	-- Activated, not MouseButton1Click: it fires for touch and controller too
	stoke.Activated:Connect(function()
		BH.stokes += 1
		playSound(SOUND_STOKE, 0.5)
		stoke.Size = UDim2.new(0, 288, 0, 70)   -- squash that pops back: the press reads
		tween(stoke, 0.18, { Size = UDim2.new(0, 300, 0, 76) }, Enum.EasingStyle.Back)
	end)
end

local function openBakeHUD(what)
	BH.stokes = 0
	BH.title.Text = ("%s Baking: %s"):format(E_FIRE, what)
	BH.gui.Enabled = true
	bottomHudHold("BakeryOven", true)
end
local function closeBakeHUD()
	BH.gui.Enabled = false
	bottomHudHold("BakeryOven", false)
end
BH.close = closeBakeHUD          -- the X inside the panel, built above this line, calls it
local function updateBakeHUD(heat, progress, inZone)
	BH.needle.Position = UDim2.new(heat / 100, 0, 0.5, 0)
	BH.needle.BackgroundColor3 = inZone and Color3.fromRGB(72, 150, 60) or PAL.TEXTC
	BH.fill.Size = UDim2.new(progress / 100, 0, 1, 0)
	BH.fill.BackgroundColor3 = inZone and PAL.GLOW or PAL.CRUST
	BH.plabel.Text = ("%d%%"):format(progress)
	BH.hint.Text = inZone and (E_FIRE .. " Perfect heat -- hold it there!")
		or (heat < ZONE_LO and "Too cold! STOKE the fire!" or "Too hot! Let it settle a moment...")
	BH.hint.TextColor3 = inZone and Color3.fromRGB(72, 150, 60) or PAL.CRUST
	-- THE BUTTON SAYS WHAT THE OVEN NEEDS. Cold, it goes red and shouts; too hot, it goes quiet
	-- and says so -- pressing anyway is still allowed, because a player who wants to overshoot
	-- should be able to, and the bar will tell them what it cost.
	if BH.stoke then
		BH.stoke.BackgroundColor3 = (heat < ZONE_LO and Color3.fromRGB(226, 88, 62))
			or (heat > ZONE_HI and Color3.fromRGB(196, 170, 150))
			or PAL.GLOW
		BH.stoke.Text = (heat < ZONE_LO and (E_FIRE .. " STOKE -- IT'S GOING OUT!"))
			or (heat > ZONE_HI and (E_FIRE .. " EASY -- IT'S HOT"))
			or (E_FIRE .. " STOKE THE FIRE")
	end
end

-- ============================================================================
-- THE OVENS -- one built on each "Oven" part; either one bakes the pan
-- ============================================================================
local ovens = {}     -- [{ prompt=, mouthCF=, rackCF=, door=, doorCF=, glow=, smoke= }]
local bakingNow = false
local currentOven = nil   -- which oven holds the current bake (its prompt = "Watch")
local bakeIn         -- forward-declared: buildOven's prompt closure calls it, and
                     -- the function body is defined just below buildOven

local function buildOven(part)
	local at = baseFrameOf(part)
	hideMarker(part)
	-- a Model, not a Folder: the whole oven is grown OVEN_SCALE about its base
	local f = Instance.new("Model"); f.Name = "BrickOven"; f.Parent = bakeFolder
	local function piece(props, where)
		props.Parent = f
		local p = mk(props); p.CFrame = where; return p
	end

	-- stone slab, brick body, a black mouth with a glow inside, and a chimney.
	-- The mouth faces the marker's -Z, so aim the block's FRONT where players stand.
	piece({ Color = PAL.STONE, Size = Vector3.new(8.4, 1.0, 7.0), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 0.5, 0))
	piece({ Color = PAL.BRICK, Size = Vector3.new(7.0, 4.6, 5.6), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 3.3, 0.2))
	piece({ Color = PAL.BRICK_D, Size = Vector3.new(7.4, 0.6, 6.0) }, at * CFrame.new(0, 5.8, 0.2))
	-- dome: three shrinking slabs read as a curve without a single mesh
	piece({ Color = PAL.BRICK, Size = Vector3.new(6.0, 1.0, 4.8) }, at * CFrame.new(0, 6.5, 0.2))
	piece({ Color = PAL.BRICK_D, Size = Vector3.new(4.4, 0.9, 3.6) }, at * CFrame.new(0, 7.3, 0.2))
	piece({ Color = PAL.BRICK, Size = Vector3.new(2.8, 0.8, 2.4) }, at * CFrame.new(0, 8.0, 0.2))
	-- brick coursing: thin dark bands so the body reads as brick, not plastic
	for i = 1, 3 do
		piece({ Color = PAL.BRICK_D, Size = Vector3.new(7.05, 0.16, 5.65) },
			at * CFrame.new(0, 1.6 + i * 1.05, 0.2))
	end

	-- the mouth: a dark recess with a neon glow slab hidden inside
	piece({ Color = PAL.CHOC_D, Size = Vector3.new(3.4, 2.6, 0.4) }, at * CFrame.new(0, 2.7, -2.65))
	local glow = piece({ Color = PAL.GLOW, Material = Enum.Material.Neon, Transparency = 1,
		Size = Vector3.new(3.0, 2.2, 0.25) }, at * CFrame.new(0, 2.7, -2.55))
	local light = Instance.new("PointLight")
	light.Color = PAL.GLOW; light.Brightness = 0; light.Range = 14; light.Parent = glow
	-- ember sparks spitting from the mouth -- rate rides the bake's heat
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40))
	embers.Lifetime = NumberRange.new(0.5, 1.1); embers.Rate = 0
	embers.Speed = NumberRange.new(2, 5); embers.SpreadAngle = Vector2.new(25, 25)
	embers.Size = NumberSequence.new(0.3); embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Parent = glow
	-- the door: an iron slab that slides up out of the way
	local doorCF = at * CFrame.new(0, 2.7, -2.9)
	local door = piece({ Color = PAL.IRON, Material = Enum.Material.Metal,
		Size = Vector3.new(3.5, 2.7, 0.3), CastShadow = true }, doorCF * CFrame.new(0, 3.1, 0))
	piece({ Color = PAL.STONE, Size = Vector3.new(4.6, 0.5, 1.6) }, at * CFrame.new(0, 1.2, -3.0)) -- hearth lip

	-- a bed of coals just inside the mouth: embers glowing even while it idles
	piece({ Color = Color3.fromRGB(46, 24, 16), Size = Vector3.new(2.8, 0.35, 1.6) },
		at * CFrame.new(0, 1.55, -2.2))
	for i = 1, 4 do
		piece({ Color = Color3.fromRGB(255, 96, 40), Material = Enum.Material.Neon,
			Size = Vector3.new(0.4, 0.22, 0.4) },
			at * CFrame.new(-0.9 + i * 0.45, 1.72, -2.15 + math.sin(i * 2.3) * 0.4))
	end
	-- arched bricks over the mouth so it reads as a proper hearth, not a slot
	for _, q in ipairs({ { -1.55, 4.15, 24 }, { -0.6, 4.45, 10 }, { 0.6, 4.45, -10 }, { 1.55, 4.15, -24 } }) do
		piece({ Color = PAL.BRICK_D, Size = Vector3.new(1.05, 0.6, 0.3) },
			at * CFrame.new(q[1], q[2], -2.5) * CFrame.Angles(0, 0, math.rad(q[3])))
	end
	-- split firewood stacked on the slab, waiting for the stoke
	for i = 1, 3 do
		piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D, Size = Vector3.new(2.2, 0.7, 0.7) },
			at * CFrame.new(3.6, 1.35 + (i - 1) * 0.62, -0.6 + (i % 2) * 0.6)
				* CFrame.Angles(0, math.rad(90), 0))
	end

	-- chimney with a smoke emitter that only runs while baking
	piece({ Color = PAL.BRICK_D, Size = Vector3.new(1.5, 3.2, 1.5), CastShadow = true },
		at * CFrame.new(2.0, 9.2, 1.4))
	piece({ Color = PAL.STONE, Size = Vector3.new(1.9, 0.4, 1.9) }, at * CFrame.new(2.0, 10.9, 1.4))
	local smokeHost = piece({ Transparency = 1, Size = Vector3.new(1, 1, 1) },
		at * CFrame.new(2.0, 11.3, 1.4))
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(PAL.SMOKE)
	-- the chimney is NEVER cold: a lazy idle wisp all day, thickening with the
	-- fire while a bake is on (the bake loop drives Rate off the heat)
	smoke.Lifetime = NumberRange.new(1.4, 2.4); smoke.Rate = 3
	smoke.Speed = NumberRange.new(2.5, 4.5); smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1) })
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Parent = smokeHost

	-- a side rack where the finished tray slides out
	local rackCF = at * CFrame.new(-3.2, 3.0, -1.6)
	piece({ Color = PAL.WOOD, Size = Vector3.new(2.6, 0.3, 2.0), CanCollide = true },
		rackCF * CFrame.new(0, -0.4, 0))
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.5, 2.6, 0.5), CanCollide = true },
		rackCF * CFrame.new(0, -1.8, 0))

	-- prompt box OUTSIDE the model (same reason as the mixer's): player height,
	-- in front of the mouth, roomy but not huge
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(16, 10, 10),
		CFrame = at * CFrame.new(0, 5, -3.3 * OVEN_SCALE), Parent = bakeFolder })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Bake"; prompt.ObjectText = "Brick Oven"; prompt.HoldDuration = 0.3
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false; prompt.Parent = hit

	-- GROW THE WHOLE OVEN about its base, then recompute every frame the bake
	-- sequence steers by -- door, mouth, rack -- at the same scale. The smoke is
	-- rescaled by hand: ScaleTo grows parts, not particles, and a wisp sized for
	-- a garden oven vanishes against a chimney five times as tall.
	local S = OVEN_SCALE
	f.WorldPivot = at
	f:ScaleTo(S)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1 * S),
		NumberSequenceKeypoint.new(1, 3.0 * S) })
	smoke.Speed = NumberRange.new(2.5 * S * 0.6, 4.5 * S * 0.6)
	smoke.Acceleration = Vector3.new(0, 3 * S * 0.5, 0)
	embers.Size = NumberSequence.new(0.3 * S)
	embers.Speed = NumberRange.new(2 * S * 0.5, 5 * S * 0.5)
	light.Range = 14 * S
	-- NOT PASS-THROUGH-ABLE, same as the mixer. The glow slab starts invisible
	-- so it stays walk-through; the door goes solid, as a door should.
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			d.CanCollide = true; d.CanQuery = true
		end
	end

	local ovenDoorCF = at * CFrame.new(0, 2.7 * S, -2.9 * S)
	local oven = {
		prompt = prompt, glow = glow, light = light, smoke = smoke, embers = embers,
		door = door, doorCF = ovenDoorCF, doorUpCF = ovenDoorCF * CFrame.new(0, 3.1 * S, 0),
		mouthCF = at * CFrame.new(0, 2.4 * S, -2.4 * S),
		rackCF  = at * CFrame.new(-3.2 * S, 3.0 * S, -1.6 * S),
		-- where you STAND to take the tray: player height, beside the tall rack
		rackTakeCF = at * CFrame.new(-3.2 * S, 5, -1.6 * S - 5),
	}
	table.insert(ovens, oven)
	prompt.Triggered:Connect(function()
		if step == 4 and not bakingNow then bakeIn(oven)
		-- "Watch" reopens the bake panel mid-bake: it goes through the same open as the first
		-- time so the bottom HUD ducks out of the way again (openBakeHUD would also zero the
		-- stokes queued this instant, which is why the flag is set directly and the hold with it)
		elseif step == 5 and oven == currentOven then
			BH.gui.Enabled = true
			bottomHudHold("BakeryOven", true)
		end
	end)
	-- reach measured off the GROWN oven (see the mixer's note): E answers from the far edge
	-- of the brickwork, so you never have to walk into the mouth to open the panel.
	bigPrompt(prompt, f, 16)
	print(("[Bakery] oven %d built on '%s' (x%d, seated on the marker's base, E reaches %.0f studs)")
		:format(#ovens, part:GetFullName(), S, prompt.MaxActivationDistance))
end

-- the bake itself: pan in, door down, glow up, smoke on, count down, DING
bakeIn = function(oven)
	bakingNow = true
	currentOven = oven
	step = 5
	refreshBanner(); refreshPrompts()
	local R = RECIPES[recipe]
	-- world props at the oven live at oven scale, or they vanish inside it
	local TS = math.max(1, OVEN_SCALE * 0.55)

	-- the pan leaves your hands, grows to oven size, and slides into the mouth
	local hrp = hrpOf()
	local pan = mk({ Color = PAL.IRON, Material = Enum.Material.Metal, Size = Vector3.new(1.7, 0.3, 1.25) })
	pan.CFrame = hrp and (hrp.CFrame * CFrame.new(0, 0, -2)) or oven.mouthCF * CFrame.new(0, 0, -4 * TS)
	pan.Parent = bakeFolder
	local fill = mk({ Color = R.batter, Size = Vector3.new(1.5, 0.18, 1.05) })
	fill.CFrame = pan.CFrame * CFrame.new(0, 0.16, 0); fill.Parent = bakeFolder
	dropHeld()
	tween(pan, 0.6, { CFrame = oven.mouthCF, Size = Vector3.new(1.7, 0.3, 1.25) * TS })
	tween(fill, 0.6, { CFrame = oven.mouthCF * CFrame.new(0, 0.16 * TS, 0),
		Size = Vector3.new(1.5, 0.18, 1.05) * TS })

	task.delay(0.7, function()
		-- door shuts, fire lights
		tween(oven.door, 0.4, { CFrame = oven.doorCF }, Enum.EasingStyle.Bounce)
		tween(oven.glow, 0.5, { Transparency = 0.3 })
		playAt(SOUND_DOOR, oven.door, 0.6, 110)
		pan:Destroy(); fill:Destroy()

		-- THE ROAR. Created when the fire lights and destroyed when the bake ends -- an oven
		-- still roaring after the DING is worse than one that never roared (the same rule the
		-- camp fire follows). Its volume rides the heat, so the bake is audible from outside
		-- the HUD: let the fire die and you HEAR it going out before the needle tells you.
		local roar
		if SOUND_FIRE ~= "" then
			roar = Instance.new("Sound")
			roar.SoundId = SOUND_FIRE; roar.Looped = true; roar.Volume = 0
			roar.RollOffMinDistance = FIRE_FULL; roar.RollOffMaxDistance = FIRE_RANGE
			roar.RollOffMode = Enum.RollOffMode.InverseTapered
			roar.Parent = oven.glow
			pcall(function() roar:Play() end)
		end
		local function hushRoar()
			if not roar then return end
			local r = roar; roar = nil
			tween(r, 0.6, { Volume = 0 }); Debris:AddItem(r, 0.8)
		end

		-- THE BAKE IS PLAYED, NOT WAITED OUT. The oven HUD opens: heat bleeds
		-- away, STOKE puts it back, and progress runs fast only while the needle
		-- holds the sweet zone. Glow, light and chimney smoke all answer the heat,
		-- so the oven itself shows how the bake is going from across the island.
		openBakeHUD(R.title)
		if FX.send then FX.send("ovenOn", oven.glow.Position) end   -- that oven lights up for all
		task.spawn(function()
			local heat, progress, last = 65, 0, os.clock()
			while progress < 100 and step == 5 do
				task.wait(0.05)
				local now = os.clock()
				local dt = math.min(now - last, 0.25); last = now
				heat = math.clamp(heat + BH.stokes * HEAT_STOKE - HEAT_DECAY * dt, 0, 100)
				BH.stokes = 0
				local inZone = heat >= ZONE_LO and heat <= ZONE_HI
				progress = math.min(100, progress + dt * (inZone and BAKE_FAST or BAKE_SLOW))
				updateBakeHUD(heat, progress, inZone)
				oven.glow.Transparency = 0.65 - 0.55 * (heat / 100)
				oven.light.Brightness = 0.6 + 2.6 * (heat / 100)
				oven.smoke.Rate = 3 + math.floor(heat / 8)
				oven.embers.Rate = math.floor(heat / 12)
				if roar then roar.Volume = FIRE_VOLUME * (0.25 + 0.75 * (heat / 100)) end
				objLabel.Text = ("%s Baking the %s...  %d%%"):format(E_FIRE, R.title, progress)
			end
			closeBakeHUD()
			hushRoar()
			if step ~= 5 then    -- /complete (or a reset) cut this bake short: stand down
				bakingNow = false; currentOven = nil
				oven.smoke.Rate = 3; oven.embers.Rate = 0
				tween(oven.glow, 0.5, { Transparency = 1 }); oven.light.Brightness = 0
				tween(oven.door, 0.5, { CFrame = oven.doorUpCF })
				return
			end
			-- DING! door up, fire down to an idle wisp, tray out onto the rack
			oven.smoke.Rate = 3; oven.embers.Rate = 0
			tween(oven.glow, 0.5, { Transparency = 1 })
			oven.light.Brightness = 0
			tween(oven.door, 0.5, { CFrame = oven.doorUpCF })
			flashBanner(E_BELL .. " DING! It's ready -- grab the tray!", 4)
			if FX.send then FX.send("ovenDone", oven.glow.Position) end   -- everyone hears the bell
			playAt(SOUND_DING, oven.glow, 0.7, 160)
			playAt(SOUND_DOOR, oven.door, 0.5, 110)
			poofAt(oven.mouthCF.Position, PAL.GLOW_H)

			-- the finished tray slides from the mouth to the side rack, at oven scale
			local tray = Instance.new("Model"); tray.Name = "DoneTray"; tray.Parent = bakeFolder
			local base = mk({ Color = PAL.BUTTER, Size = Vector3.new(1.9, 0.16, 1.35) * TS,
				Reflectance = 0.08, CanQuery = true, Parent = tray })
			base.CFrame = oven.mouthCF
			for gx = -1, 1 do
				for gz = 0, 1 do
					local isCookie = (recipe == "brookie") and ((gx + gz) % 2 == 0)
					local sq = mk({
						Color = isCookie and PAL.DOUGHY or PAL.CHOC,
						Shape = isCookie and Enum.PartType.Ball or Enum.PartType.Block,
						Size = (isCookie and Vector3.new(0.52, 0.34, 0.52) or Vector3.new(0.46, 0.3, 0.46)) * TS,
						Parent = tray })
					sq.CFrame = base.CFrame * CFrame.new(gx * 0.55 * TS, 0.25 * TS, (gz - 0.5) * 0.6 * TS)
				end
			end
			tray.PrimaryPart = base
			-- steam wisps off the fresh bake
			local steam = Instance.new("ParticleEmitter")
			steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
			steam.Color = ColorSequence.new(Color3.new(1, 1, 1))
			steam.Lifetime = NumberRange.new(0.7, 1.2); steam.Rate = 4
			steam.Speed = NumberRange.new(1, 2); steam.Size = NumberSequence.new(0.5)
			steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(1, 1) })
			steam.Parent = base
			task.spawn(function()
				local from, to = oven.mouthCF, oven.rackCF
				for a = 0, 1, 0.06 do
					if not tray.Parent then return end
					tray:PivotTo(from:Lerp(to, a))
					task.wait(0.03)
				end
			end)

			-- the take prompt sits in a ground-level box by the rack, not on the
			-- tray itself -- the tray rides 15 studs up where no [E] can be reached
			local takeBox = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(12, 9, 10),
				CFrame = oven.rackTakeCF, Parent = bakeFolder })
			local tprompt = Instance.new("ProximityPrompt")
			tprompt.ActionText = "Take Tray"; tprompt.ObjectText = R.title
			tprompt.HoldDuration = 0; tprompt.MaxActivationDistance = 16
			tprompt.RequiresLineOfSight = false; tprompt.Parent = takeBox
			bigPrompt(tprompt)
			-- ⚠ ONE E AT A TIME. Roblox fires only the NEAREST prompt bound to a key, and the
			-- oven's "Watch" now reaches from the far edge of the grown brickwork -- easily far
			-- enough to cover the rack. With both live, standing at the rack could re-open the
			-- bake panel instead of handing you the tray. The bake is over, so Watch goes off.
			-- (The HUD itself is already closed by the bake loop exiting, a few lines above.)
			oven.prompt.Enabled = false
			tprompt.Triggered:Connect(function()
				if step ~= 5 then return end
				step = 6
				bakingNow = false
				currentOven = nil
				tray:Destroy(); takeBox:Destroy()
				giveHeld("tray")
				refreshBanner(); refreshPrompts()
				if bakerHead then showBubble(bakerHead, "Ooooh, bring it here! Careful now!", false) end
			end)
		end)
	end)
end

-- ============================================================================
-- THE BAKER -- an existing *npc* model near the Mixer if you placed one,
-- otherwise a chef built beside the station
-- ============================================================================
local function findExistingNpc(nearPos)
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and string.find(norm(d.Name), "npc", 1, true)
			and not d:IsDescendantOf(bakeFolder) then
			local head = d:FindFirstChild("Head") or d.PrimaryPart
				or d:FindFirstChildWhichIsA("BasePart", true)
			if head then
				local dist = (head.Position - nearPos).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

local function buildBaker(at)
	-- stands beside the mixing station, facing where players walk up. The station
	-- is MIXER_SCALE times wider than built, so stand clear of the grown counter.
	local spot = at * CFrame.new(4.2 * MIXER_SCALE + 3, 0, -1.5) * CFrame.Angles(0, math.rad(140), 0)
	local g = seatOn(spot.Position.X, spot.Position.Z, at.Position.Y, 10)
	local base = CFrame.new(g and (g + Vector3.new(0, 0, 0)) or spot.Position) * (spot - spot.Position)

	local m = Instance.new("Model"); m.Name = "Baker Npc"   -- "npc" in the name: the island
	                                                        -- guide arrows will point at him
	local function bit(props, cf)
		props.Parent = m; props.CastShadow = true
		local p = mk(props); p.CFrame = base * cf; return p
	end
	for _, sx in ipairs({ -1, 1 }) do                        -- legs
		bit({ Color = PAL.CHOC_D, Size = Vector3.new(0.85, 1.9, 0.9) }, CFrame.new(sx * 0.5, 0.95, 0))
		bit({ Color = PAL.CHOC_D, Size = Vector3.new(0.9, 0.35, 1.3) }, CFrame.new(sx * 0.5, 0.18, -0.2))
	end
	bit({ Color = PAL.CREAM, Size = Vector3.new(2.2, 2.4, 1.4) }, CFrame.new(0, 3.1, 0))     -- jacket
	bit({ Color = PAL.PINK, Size = Vector3.new(1.7, 1.9, 0.2) }, CFrame.new(0, 2.8, -0.72))  -- apron
	bit({ Color = PAL.PINK, Size = Vector3.new(1.9, 0.35, 0.24) }, CFrame.new(0, 3.9, -0.7)) -- apron tie
	for i = 1, 3 do                                           -- jacket buttons
		bit({ Shape = Enum.PartType.Ball, Color = PAL.CHOC, Size = Vector3.new(0.18, 0.18, 0.18) },
			CFrame.new(0.55, 2.4 + i * 0.55, -0.72))
	end
	for _, sx in ipairs({ -1, 1 }) do                         -- arms: one on hip, one out
		bit({ Color = PAL.CREAM, Size = Vector3.new(0.7, 2.0, 0.7) },
			CFrame.new(sx * 1.45, 3.2, 0) * CFrame.Angles(0, 0, math.rad(sx * 14)))
		bit({ Shape = Enum.PartType.Ball, Color = PAL.SKIN, Size = Vector3.new(0.6, 0.6, 0.6) },
			CFrame.new(sx * 1.7, 2.15, 0))
	end
	local head = bit({ Color = PAL.SKIN, Size = Vector3.new(1.5, 1.4, 1.4), CanQuery = true },
		CFrame.new(0, 5.0, 0))
	head.Name = "Head"
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Shape = Enum.PartType.Ball, Color = Color3.new(0, 0, 0), Size = Vector3.new(0.18, 0.22, 0.1) },
			CFrame.new(sx * 0.34, 5.15, -0.68))
	end
	bit({ Color = PAL.CHOC, Size = Vector3.new(0.9, 0.22, 0.3) }, CFrame.new(0, 4.7, -0.68))  -- mustache
	bit({ Shape = Enum.PartType.Ball, Color = PAL.SKIN, Size = Vector3.new(0.3, 0.25, 0.3) },
		CFrame.new(0, 4.95, -0.75))                                                            -- nose
	-- the chef hat: band + puffy top
	bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CREAM, Size = Vector3.new(0.55, 1.5, 1.5) },
		CFrame.new(0, 5.85, 0) * CFrame.Angles(0, 0, math.rad(90)))
	bit({ Shape = Enum.PartType.Ball, Color = Color3.new(1, 1, 1), Size = Vector3.new(1.7, 1.2, 1.7) },
		CFrame.new(0, 6.5, 0))
	bit({ Shape = Enum.PartType.Ball, Color = Color3.new(1, 1, 1), Size = Vector3.new(0.9, 0.8, 0.9) },
		CFrame.new(0.5, 6.7, 0.3))
	m.PrimaryPart = head
	m.WorldPivot = base

	-- parent under the island model when there is one, so NpcGuideArrow's
	-- island-scoped scan can find him; Workspace otherwise
	m.Parent = islandModel() or bakeFolder

	-- a slow idle sway so he reads as alive, not a statue
	task.spawn(function()
		local t = 0
		while m.Parent do
			t += task.wait(0.06)
			m:PivotTo(base * CFrame.new(0, math.sin(t * 1.6) * 0.06, 0)
				* CFrame.Angles(0, math.sin(t * 0.8) * 0.04, 0))
		end
	end)
	print("[Bakery] no NPC nearby -- built the Baker beside the mixing station")
	return head
end

-- ============================================================================
-- DIALOGUE -- paged bubbles, same rhythm as every other island NPC
-- ============================================================================
local function questPages()
	if step >= 7 then
		if bonusDone then
			return { "Brownies AND Brookies. My hero!", "The bakery smells incredible. Thank you!" }
		end
		local other = (recipe == "brownie") and RECIPES.brookie or RECIPES.brownie
		return {
			"That was DELICIOUS. But you know what...",
			("I never got to taste the %s!"):format(other.title),
			("Bake me the %s too and there's %d more coins in it!"):format(other.title, BONUS_REWARD),
		}
	elseif step == 6 then
		return { "Is that it?! Hand it over, hand it over!" }
	elseif step == 5 then
		return { "Patience! Good baking takes time. Watch the oven!" }
	elseif step == 4 then
		return { "Don't just stand there holding batter -- OVEN. Either one!" }
	elseif step == 3 then
		return { "Stir stir stir! The bowl won't mix itself!" }
	elseif step == 2 then
		if allGathered() then return { "You've got everything! To the mixing bowl!" } end
		local pages = { "Still shopping? Here's what's left:", shoppingList() }
		if stillNeeds("egg") then
			pages[#pages + 1] = E_CHICK .. " Eggs? TAP any of my chickens. Gently! She'll lay one for you."
		end
		return pages
	end
	return {
		"Welcome to my bakery! Well... it WILL be a bakery.",
		"Two ovens, a giant bowl, my prize chickens -- and no baker's assistant!",
		"That's where YOU come in. Pick a recipe and we'll bake it together.",
		"Fetch the ingredients, mix them in my bowl, bake the pan golden...",
		("...and there's %d coins in it for you. Deal? Pick your bake!"):format(COIN_REWARD),
	}
end

local function completeBake()
	-- tray handed over: pay out, celebrate, and either open the bonus or wrap up
	dropHeld()
	local R = RECIPES[recipe]
	local reward = bonusRound and BONUS_REWARD or COIN_REWARD
	local ce = ReplicatedStorage:FindFirstChild("CoinEvent")
	if ce then pcall(function() ce:FireServer(reward) end) end
	if bonusRound then bonusDone = true end
	step = 7
	_G.bakeryQuestComplete = true
	-- CINEMATIC PAYOFF. RevealCommand resolves island15's subject itself and plays the shot, so this
	-- is one line and re-aiming it later is an edit to TARGETS there, not here. Delayed so the
	-- completion banner and the world change land FIRST -- the camera is going there to show you
	-- the result, and cutting away before it happens shows you the before.
	task.delay(1.2, function() pcall(_G.revealIsland, 15) end)
	_G.bakeryQuestStep = nil
	refreshBanner(); refreshPrompts()
	playSound(SOUND_DING, 0.7)
	if bakerHead then
		launchFireworks(bakerHead.Position + Vector3.new(0, 4, 0))
		showBubble(bakerHead, "Mmmmf-- mm! Divine. DIVINE!", false)
	end
	winBanner(("%s You baked the %s!  +%d coins %s"):format(E_SPARK, R.title, reward, E_SPARK))
	if _G.NotifyCenter then
		pcall(function() _G.NotifyCenter.push({
			text = ("%s %s baked! +%d coins"):format(E_SPARK, R.title, reward), color = PAL.CRUST }) end)
	end
	print(("[Bakery] %s delivered -- +%d coins%s"):format(R.title, reward,
		bonusRound and " (bonus round)" or ""))
end

local function startRound(key, isBonus)
	recipe = key
	bonusRound = isBonus or false
	have = {}
	stirs = 0
	step = 2
	-- WAIT FOR THE PLATE BEFORE SCATTERING. The player can accept the recipe within seconds of
	-- landing, and the plate is found by the same streaming scan as everything else -- so the
	-- one moment the ingredients get placed is exactly the moment the floor of record might
	-- still be a few hundred milliseconds away. Placing first and correcting later is worse
	-- than waiting: the pickups' bob loop captures its home pivot on the frame it starts, so a
	-- re-seat afterwards fights the animation. Bounded, so an island with no plate still plays.
	if zoneCF then
		scatterIngredients()
	else
		task.spawn(function()
			local t0 = os.clock()
			while not zoneCF and os.clock() - t0 < 8 do task.wait(0.2) end
			scatterIngredients()
		end)
	end
	refreshBanner(); refreshPrompts()
	flashBanner(("%s %s time! Find the ingredients -- and tap those chickens!")
		:format(RECIPES[key].title == "BROWNIE" and ING.cocoa.emoji or ING.dough.emoji, RECIPES[key].title), 3.5)
end

local function wireBaker(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "The Baker"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DIST; prompt.RequiresLineOfSight = false; prompt.Parent = head
	bigPrompt(prompt)

	local pages, index = nil, 0
	local watching = false
	local function closeDialogue() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local hrp = hrpOf()
				if not hrp or (hrp.Position - head.Position).Magnitude > TALK_DIST then
					closeDialogue(); break
				end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		-- delivering beats talking: with the tray in hand, one press hands it over
		if step == 6 then completeBake(); closeDialogue(); return end

		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then
			closeDialogue()
			-- finishing the intro (or the bonus offer) opens the recipe cards
			if step == 0 then
				openChooser(nil, function(key) startRound(key, false) end)
			elseif step >= 7 and not bonusDone then
				local other = (recipe == "brownie") and "brookie" or "brownie"
				openChooser(other, function(key) startRound(key, true) end)
			end
			return
		end
		local last = index >= #pages
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showBubble(head, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

-- ============================================================================
-- PROMPT REFRESH -- one place that decides what is pressable right now
-- ============================================================================
refreshPrompts = function()
	if mixPrompt then
		if step == 2 and allGathered() then
			mixPrompt.ActionText = "Mix"; mixPrompt.HoldDuration = 0.3; mixPrompt.Enabled = true
		elseif step == 3 and stirs < STIRS_NEEDED then
			-- startMixing manages the stir prompt itself; leave it be
		else
			if step ~= 3 then mixPrompt.Enabled = false end
		end
	end
	for _, o in ipairs(ovens) do
		if step == 4 and not bakingNow then
			o.prompt.ActionText = "Bake"; o.prompt.Enabled = true
		elseif step == 5 and o == currentOven then
			o.prompt.ActionText = "Watch"; o.prompt.Enabled = true   -- reopens the HUD
		else
			o.prompt.Enabled = false
		end
	end
end

-- ============================================================================
-- GO -- the streaming-safe scanner. Island 15 is a long flight from spawn, so
-- its marker parts appear late (and only when the player is near). Scan every
-- few seconds; each station is built exactly once, the moment its marker shows.
--
-- THREE THINGS IT DOES BEYOND "KEEP LOOKING":
--   * IT SCANS THE ISLAND, NOT THE WHOLE WORLD, once island15 has streamed in. A full
--     Workspace:GetDescendants() every three seconds forever is a real cost on a place
--     this size, and every marker it wants is inside that one model anyway.
--   * IT SAYS SO WHEN A MARKER NEVER COMES. Silence was the only symptom of a brick
--     that was never placed -- and a missing brick looks exactly like a broken script.
--   * IT BUILDS THE MISSING STATIONS ANYWAY. No chicken means no eggs means the
--     Bake-Off CANNOT BE FINISHED; nowhere to bake means the same. Those get built
--     beside the mixing station rather than leaving the quest dead -- the same way a
--     missing Baker has always been built. The Mixer is the one exception: it is what
--     decides where the bakery IS, so there is nothing to guess from. That one warns.
-- ============================================================================
local SCAN_FAST      = 3     -- seconds between scans while the island is still arriving
local SCAN_SLOW      = 10    -- ...and once it clearly is not coming right now
local SCAN_SETTLE    = 60    -- how long the fast cadence lasts
local ZONE_GRACE     = 90    -- give the base plate this long to stream in before the scan is
                             -- allowed to stop without it (see the break condition below)
local FALLBACK_AFTER = 40    -- seconds after the mixer is up before missing stations get built anyway.
                             -- Long enough that the rest of the island has certainly finished
                             -- streaming: a REAL brick arriving after this is one the fallback has
                             -- already stood in for, and the scan has stopped by then.

-- a stand-in marker for a brick nobody placed: invisible, unqueryable, seated so its BASE is
-- on the ground -- which is the line baseFrameOf() builds up from, so buildOven/buildChicken
-- take it exactly as they take a real one. It lives in bakeFolder, which the scanner skips
-- and the ground raycast ignores, so it can never be re-detected or stood on.
local function fakeMarker(at, size)
	local g = seatOn(at.Position.X, at.Position.Z, at.Position.Y, size.X)
	local p = g or at.Position
	local y = p.Y + size.Y * 0.5
	return mk({ Size = size, Transparency = 1, CanQuery = false, Parent = bakeFolder,
		CFrame = CFrame.new(p.X, y, p.Z) * (at - at.Position) })
end

task.spawn(function()
	local builtMixer, builtChicken = false, false
	local builtOvens = {}     -- [instance] = true
	local mixerPos = nil
	local t0, mixerAtClock = os.clock(), nil
	local warned45, warned300, fellBack = false, false, false

	while true do
		-- island15 is the only place these bricks can be, so once its model exists the scan
		-- narrows to it. Before then (and if it never streams) the world is the only scope
		-- there is. The same tick re-homes the quest folder under the island and re-anchors
		-- anything that somehow arrived loose.
		homeToIsland()
		anchorAll()
		local scope = islandModel() or Workspace
		for _, d in ipairs(scope:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Model")) and not d:IsDescendantOf(bakeFolder) then
				local key = norm(d.Name)
				if key == MIXER_NAME and not builtMixer then
					-- only latch once a real BasePart exists: a streamed-in Model can
					-- arrive EMPTY, with its parts following seconds later
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part then
						builtMixer = true
						mixerPos = part.Position
						mixerAtClock = os.clock()
						buildMixer(part)
						mixPrompt.Triggered:Connect(function()
							if step == 2 and allGathered() then startMixing()
							elseif step == 3 and stirs < STIRS_NEEDED then
								-- E re-opens a closed panel as well as stirring, exactly the way
								-- the oven's "Watch" does. A closed HUD can never strand you.
								if not MH.gui.Enabled then
									openMixHUD(RECIPES[recipe] and RECIPES[recipe].title)
								end
								doStir()
							end
						end)
						-- the Baker: an existing NPC if one is close, else built
						task.spawn(function()
							task.wait(2)          -- give a Studio-placed NPC a beat to stream in
							bakerHead = findExistingNpc(mixerPos) or buildBaker(mixerAt)
							wireBaker(bakerHead)
							refreshBanner()
						end)
					end
				elseif key == OVEN_NAME and not builtOvens[d] and mixerPos then
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part and (part.Position - mixerPos).Magnitude <= MARKER_RANGE then
						builtOvens[d] = true
						buildOven(part)
					end
				elseif key == CHICKEN_NAME and not builtChicken and mixerPos then
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part and (part.Position - mixerPos).Magnitude <= MARKER_RANGE then
						builtChicken = true
						hideMarker(d)
						chickenOrigin = part.Position
						spawnFlock()
						print("[Bakery] chicken loose at '" .. part:GetFullName() .. "'")
					end
				elseif key == ZONE_NAME and not zoneCF and mixerPos then
					local part = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart", true)
					if part and (part.Position - mixerPos).Magnitude <= MARKER_RANGE then
						-- the pen: remember its frame AND its top surface. NOT HIDDEN --
						-- despite being adopted like a marker, this part is island15's
						-- entire 300x357 base slab. hideMarker() here made the island's
						-- FLOOR invisible + non-collidable the moment the quest adopted
						-- it: every prop on it looked like it floated in mid-air and
						-- players fell straight through. The quest only needs the frame
						-- and top Y below, which work fine with the plate untouched.
						zoneCF, zoneHalf = part.CFrame, part.Size * 0.5
						zoneTopY = part.Position.Y + part.Size.Y * 0.5
						-- everything already built re-seats onto the plate: the hens follow
						-- on their next tick, the nest is moved here. Their pen is re-applied
						-- too -- until the plate existed, clampToPen had no plate to clamp to,
						-- so a hen could be standing wherever she had got to.
						if chickenOrigin then chickenOrigin = clampToZone(chickenOrigin) end
						for _, rec in ipairs(chickens) do
							rec.pos = clampToPen(rec.pos)
							rec.target = clampToPen(rec.target)
						end
						if nestModel and nestModel.Parent then
							local p = clampToZone(nestModel:GetPivot().Position)
							nestModel:PivotTo(CFrame.new(p.X, zoneTopY + 0.3, p.Z))
						end
						print(("[Bakery] chicken zone: %s (%.0f x %.0f studs, floor Y=%.0f)")
							:format(part:GetFullName(), part.Size.X, part.Size.Z, zoneTopY))
					end
				end
			end
		end
		local elapsed = os.clock() - t0

		-- everything the world was going to give: stop scanning entirely.
		--
		-- THE PLATE COUNTS AS A STATION. It is not one visually, but every prop this
		-- quest seats is placed against its top Y and clamped inside its footprint, so
		-- breaking out before it is found leaves the quest permanently without a floor
		-- of record: ingredients scatter onto whatever a raycast happens to hit and can
		-- ride the void down to an island thousands of studs below. Its branch needs
		-- mixerPos, so on a boot where the stations all latch in the pass BEFORE the
		-- plate is reached in descendant order, the old condition broke one pass early.
		-- The grace window means a world with no plate at all still stops scanning.
		if builtMixer and builtChicken and #ovens >= 2
			and (zoneCF or elapsed > ZONE_GRACE) then
			if not zoneCF then
				warn(("[Bakery] no part named '%s' within %d studs of the mixer -- props will be "
					.. "seated by raycast alone, with no island footprint to clamp them into")
					:format(ZONE_NAME, MARKER_RANGE))
			end
			break
		end

		-- NO MIXER = NO BAKERY. Say it out loud rather than sitting silent forever; the
		-- name is the thing to check, since norm() strips case, spaces and underscores.
		if not builtMixer then
			if not warned45 and elapsed > 45 then
				warned45 = true
				warn(("[Bakery] no part named '%s' found yet%s -- the Bake-Off cannot build until "
					.. "one exists on island15 (case/spaces/underscores are ignored)")
					:format(MIXER_NAME, islandModel() and " on island15" or " (island15 has not streamed in)"))
			elseif not warned300 and elapsed > 300 then
				warned300 = true
				warn("[Bakery] still no 'Mixer' brick after 5 minutes -- island 15's quest is INACTIVE. "
					.. "Place a block named Mixer (plus 2x Oven and a ChickenPart) and rejoin.")
			end
		end

		-- The mixer is up but a station never came. Build it beside the station rather than
		-- leaving a quest that cannot be completed -- an oven to bake in, and above all the
		-- chicken, which is the ONLY source of eggs and so the only hard blocker.
		if builtMixer and not fellBack and mixerAtClock
			and os.clock() - mixerAtClock > FALLBACK_AFTER then
			fellBack = true
			-- clear of the grown station (its counter is ~37 studs wide at MIXER_SCALE 5) and
			-- clear of the Baker, who stands at +X. Same heading as the mixer, so the oven
			-- mouths face the way players walk up.
			local placed = #ovens
			for i = placed + 1, 2 do
				local side = (i == 1) and -1 or 1
				buildOven(fakeMarker(mixerAt * CFrame.new(side * 58, 0, 6), Vector3.new(8, 1, 7)))
			end
			if placed < 2 then
				warn(("[Bakery] found %d 'Oven' brick(s), wanted 2 -- built %d beside the station so "
					.. "the pan has somewhere to go"):format(placed, 2 - placed))
			end
			if not builtChicken then
				builtChicken = true
				local marker = fakeMarker(mixerAt * CFrame.new(0, 0, 62), Vector3.new(6, 1, 6))
				chickenOrigin = marker.Position - Vector3.new(0, marker.Size.Y * 0.5, 0)
				spawnFlock()
				warn("[Bakery] no 'ChickenPart' brick found -- put the chicken behind the mixing "
					.. "station instead (eggs are unobtainable without her)")
			end
		end

		task.wait(elapsed > SCAN_SETTLE and SCAN_SLOW or SCAN_FAST)
	end
	-- once more after the last station: the loop stops here, so this is the final chance to
	-- catch anything built on the very last tick (and the Baker, who lands a beat later).
	homeToIsland()
	local loose = anchorAll()
	print(("[Bakery] all stations up: mixer, %d oven(s), %d hen(s) -- folder under %s%s")
		:format(#ovens, #chickens, bakeFolder.Parent and bakeFolder.Parent:GetFullName() or "?",
			loose > 0 and (", " .. loose .. " loose part(s) anchored") or ", all anchored"))
	-- RETAINER SIGNAL: the quest reached the end of its build with its world objects up. QuestRetainer
	-- watches this flag; anything still false once its island has streamed in gets force-streamed and
	-- re-run. It is set HERE, at the ready print, not at the top of the file -- a quest that bailed
	-- early on a missing marker must NOT look built. See QuestRetainer.client.luau.
	_G.questBuilt_bakery = true
end)

refreshBanner()

-- ============================================================================
-- THE SHARED HALF -- what SOMEBODY ELSE'S bake-off looks like from where you stand
-- ============================================================================
-- Everything above is one player's private copy of island 15. This is the part that makes the
-- island feel occupied: when another player lights an oven, YOUR copy of that oven lights; when
-- their hen lays, your hen bawks and puffs feathers; when they stir, your bowl splashes.
--
-- It is all cosmetic and none of it can touch your quest. The two guards that matter:
--   * messages from YOURSELF are dropped -- you already played the effect locally,
--   * an oven YOUR bake is using is never repainted by somebody else's news, or their bake
--     finishing would put your fire out halfway through yours.
-- The position in each message only ever picks WHICH nearby prop to animate, and props sit on
-- the same marker blocks for everybody, so the effect lands on the right one.
-- (in a task, not inline: WaitForChild would otherwise hold up the rest of this file's boot for
-- up to 20 seconds on a server where the relay script has not replicated yet)
task.spawn(function()
	local ev = ReplicatedStorage:FindFirstChild("BakeryFxEvent")
		or ReplicatedStorage:WaitForChild("BakeryFxEvent", 20)
	if ev then
		FX.send = function(kind, pos)
			pcall(function() ev:FireServer(kind, pos) end)
		end

		local function nearest(list, pos, reach, get)
			local best, bd
			for _, it in ipairs(list) do
				local p = get(it)
				if p then
					local d = (p - pos).Magnitude
					if not bd or d < bd then best, bd = it, d end
				end
			end
			if best and bd <= reach then return best end
			return nil
		end

		ev.OnClientEvent:Connect(function(who, kind, pos)
			if who == player then return end
			if typeof(pos) ~= "Vector3" then return end

			if kind == "ovenOn" or kind == "ovenDone" then
				local o = nearest(ovens, pos, 60, function(x)
					return x.glow and x.glow.Parent and x.glow.Position or nil end)
				if not o then return end
				if bakingNow and o == currentOven then return end   -- our own bake owns that oven
				if kind == "ovenOn" then
					tween(o.door, 0.5, { CFrame = o.doorCF })
					tween(o.glow, 0.6, { Transparency = 0.15 })
					o.light.Brightness = 2.6
					o.smoke.Rate = 12
					o.embers.Rate = 6
					playAt(SOUND_DOOR, o.door, 0.4, 110)
				else
					tween(o.door, 0.5, { CFrame = o.doorUpCF })
					tween(o.glow, 0.6, { Transparency = 1 })
					o.light.Brightness = 0
					o.smoke.Rate = 3
					o.embers.Rate = 0
					playAt(SOUND_DING, o.glow, 0.6, 160)
					poofAt(o.mouthCF.Position, PAL.GLOW_H)
				end

			elseif kind == "egg" then
				local rec = nearest(chickens, pos, 90, function(x)
					local m = x.model
					return m and m.PrimaryPart and m.PrimaryPart.Position or nil end)
				if rec and rec.model and rec.model.PrimaryPart then
					local head = rec.model.PrimaryPart
					playAt(SOUND_BAWK, head, 0.5, 110)
					poofAt(head.Position + Vector3.new(0, 0.6, 0), PAL.FEATHER)
					-- a cosmetic egg, theirs to pick up and not yours: it sits a moment and fades,
					-- with no prompt on it, so nobody can walk over and take somebody's else's egg
					local e = mk({ Shape = Enum.PartType.Ball, Color = PAL.EGGSH,
						Size = Vector3.new(0.75, 0.95, 0.75), CanQuery = false })
					e.CFrame = CFrame.new(pos) * CFrame.new(0, 0.5, -1.6)
					e.Parent = bakeFolder
					tween(e, 5, { Transparency = 1 })
					Debris:AddItem(e, 5.5)
				end

			elseif kind == "stir" then
				local R = RECIPES[recipe]
				poofAt(pos + Vector3.new(0, 1.2, 0), (R and R.batter) or PAL.DOUGHY)
				playSound(SOUND_STIR, 0.25)
			end
		end)
		print("[Bakery] shared effects live -- other players' ovens, hens and mixing show up here")
	else
		warn("[Bakery] no BakeryFxEvent in ReplicatedStorage -- other players' baking will be "
			.. "invisible. Is BakeryFxSync.server.lua synced into ServerScriptService?")
	end
end)

-- ============================================================================
-- /start    -- jump straight to the recipe cards, no Baker chat needed
-- /complete -- instantly finishes the CURRENT bake
-- (/done is island-wide and lives in DoneCommand.client.luau -- it calls the hook published at
--  the bottom of this file, which grants the shopping list. See the note down there.)
-- Both only fire standing at the bakery, so they can't trigger from elsewhere.
-- ============================================================================
local function onCommand(msg)
	local text = tostring(msg or ""):lower()
	if text:sub(1, 6) == "/start" then
		local hrp = hrpOf()
		if not (mixerAt and hrp) then return end
		if (hrp.Position - mixerAt.Position).Magnitude > BANNER_RANGE then return end
		if step == 0 then
			openChooser(nil, function(key) startRound(key, false) end)
		elseif step >= 7 and not bonusDone then
			local other = (recipe == "brownie") and "brookie" or "brownie"
			openChooser(other, function(key) startRound(key, true) end)
		else
			flashBanner(E_BOWL .. " The bake-off is already going -- check the banner!", 2.5)
		end
		print("[Bakery][TEST] /start -- recipe cards opened")
		return
	end
	if text:sub(1, 9) ~= "/complete" then return end
	local hrp = hrpOf()
	if not (mixerAt and hrp) then return end
	if (hrp.Position - mixerAt.Position).Magnitude > BANNER_RANGE then return end
	if step >= 7 and bonusDone then return end
	if not recipe then recipe = "brownie" end
	if step < 6 then step = 6; giveHeld("tray") end
	completeBake()
	print("[Bakery][TEST] /complete -- bake handed straight to the Baker")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)

-- ============================================================================
-- /done ON ISLAND 15 -- SKIP THE SHOPPING, KEEP THE COOKING
-- ============================================================================
-- DoneCommand.client.luau owns /done for the whole realm and calls this hook if a quest publishes
-- one. Here it grants the entire shopping list (chicken eggs included) and clears the props off
-- the plate, so the MIXING BOWL and the OVEN HUDs can be tested without walking the island five
-- times first. It deliberately stops there -- it does not mix, bake or deliver, which are the
-- things it exists to let you try.
--
-- RETURNING true MEANS "HANDLED -- DO NOT FLAG THE QUEST COMPLETE". Marking the Bake-Off finished
-- the moment you asked for the ingredients would tick the journal and pay the island token for a
-- bake that never happened. Past the shopping it returns nothing instead, so a second /done falls
-- through to the normal force-complete and the quest finishes as it always did.
_G.bakeryForceComplete = function()
	if step > 2 then return end               -- already mixing/baking: let /done complete it
	if step == 0 or not recipe then startRound("brownie", false) end
	for k, n in pairs(needOf() or {}) do have[k] = n end
	clearScattered()
	refreshBanner(); if refreshPrompts then refreshPrompts() end
	flashBanner(E_BOWL .. " Every ingredient granted -- to the MIXING BOWL!", 3)
	if bakerHead then showBubble(bakerHead, "That's the lot! Get mixing!", false) end
	print("[Bakery][TEST] /done -- shopping list granted, plate cleared, oven HUD next")
	return true
end
