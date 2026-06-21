--======================================================================
-- CommunityGarden.server.lua  (Script)  -- STAGE 1: per-server community garden (visuals + watering +
-- growth stages + live sign). STANDALONE. No seasons, no accessories, no cross-server datastore yet
-- (those are STAGE 2 / STAGE 4 -- see the notes below; this is structured so they slot in cleanly).
--======================================================================
-- Everyone in the server waters ONE shared progress number (0 -> GOAL). The CommunityGarden field grows
-- through visible STAGES as progress climbs, and a sign at GardenSignSpot shows the live progress. Each
-- player can water ONCE PER DAY (server-tracked per-player cooldown). SERVER-AUTHORITATIVE: the server
-- owns the progress + cooldown; the client only sends a "water" intent (validated here).
--
-- COSMETIC ONLY -- never touches flight, pets, coins, gas, the black hole, shop, events, the cow, etc.
--
-- \xF0\x9F\x94\xAE STAGE 2 (seasons + harvest/reward/reset): hook onProgressChanged() (the "FULLY GROWN" branch) to
--    start a harvest->reward->reset cycle; add season modifiers around addProgress(). Not built yet.
-- \xF0\x9F\x94\xAE STAGE 4 (global cross-server): the progress lives behind getProgress()/setProgress()/addProgress()
--    ONLY -- swap those three to read/write a global DataStore (+ a periodic refresh) and nothing else changes.
--======================================================================

local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")

-- ===== TUNABLES =====
local GOAL              = 2000        -- progress needed for a fully grown garden
local WATER_AMOUNT      = 25          -- progress added per player water
local COOLDOWN_SECONDS  = 24 * 3600   -- once per day per player
local WATER_RANGE       = 28          -- max studs from WaterSpot the server accepts a water from (anti-cheat)

-- \xE2\x9A\xA0 PLACEHOLDER SOUND -- REPLACE WITH A WATERING SOUND BEFORE LAUNCH (played client-side on the splash).
local WATER_SOUND_ID    = "" -- \xE2\x9A\xA0 REPLACE WITH WATERING SOUND

local BAL, BLK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local SMOOTH = Enum.SurfaceType.Smooth

--======================================================================
-- REMOTE (getOrCreate so a missing project.json entry can't break it; the client WaitForChild's it).
--======================================================================
local function getOrCreateRemote(name)
	local r = game:GetService("ReplicatedStorage"):FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = game:GetService("ReplicatedStorage") end
	return r
end
local GardenWaterEvent = getOrCreateRemote("GardenWaterEvent") -- c->s: "query"/"water" ; s->c: state/splash

--======================================================================
-- GARDENER NPC CHAT (cosmetic). The Gardener has an always-on speech bubble that cycles GARDENER_LINES, and a
-- hold-E "Talk" prompt that opens a PRESET QUESTION MENU on the client. The client asks this RemoteFunction
-- ("menu" -> greeting + question list; "ask",key -> answer); the server owns the answers so the live
-- "How close are we?" reply always matches the dial. Edit questions/answers in GARDENER_QA below.
--======================================================================
local function getOrCreateRemoteFunction(name)
	local r = game:GetService("ReplicatedStorage"):FindFirstChild(name)
	if not r then r = Instance.new("RemoteFunction"); r.Name = name; r.Parent = game:GetService("ReplicatedStorage") end
	return r
end
local GardenerChatFunction = getOrCreateRemoteFunction("GardenerChatFunction") -- c->s invoke("menu") | invoke("ask", key)

-- always-on speech-bubble lines (cycled every few seconds)
local GARDENER_LINES = {
	"Keep farting, keep growing!",
	"Water the garden, friend!",
	"Look how it's blooming!",
	"Every little bit helps it grow!",
	"Welcome to the Community Garden!",
}
-- PRESET QUESTION MENU (no free typing): the hold-E "Talk" prompt opens a client menu of these questions; the
-- client asks the server BY KEY ("menu" -> list, "ask" -> answer) so live answers stay accurate. EDIT freely here.
-- The "close" answer is computed LIVE from getProgress()/GOAL by gardenerLiveAnswer() further down.
local GARDENER_GREETING = "Howdy, friend! \xF0\x9F\x8C\xBB What would you like to know?"
local GARDENER_QA = {
	{ key = "what",   label = "What is the Community Garden?", answer = "We all water it together to grow one giant sunflower! When it's full, everyone gets rewarded. \xF0\x9F\x8C\xBB" },
	{ key = "help",   label = "How do I help it grow?",        answer = "Walk up to the watering spot and hold E to water it! You can water once a day. \xF0\x9F\x92\xA7" },
	{ key = "close",  label = "How close are we?",             answer = "" }, -- filled LIVE by the server (gardenerLiveAnswer)
	{ key = "reward", label = "What do I get?",                answer = "When it's fully grown, everyone online gets a reward -- plus a seasonal cosmetic! \xF0\x9F\x8E\x81" },
	{ key = "who",    label = "Who are you?",                  answer = "Me? I'm the old garden keeper -- I tend the soil and cheer on every drop you pour! \xF0\x9F\x98\x84" },
	{ key = "bye",    label = "Bye!",                          answer = "Take care, friend -- come back and water soon! \xF0\x9F\x8C\xB1" },
}

--======================================================================
-- GARDEN PROGRESS DATA  (STAGE 1: per-server, in-memory). Kept BEHIND these 3 functions so STAGE 4 can
-- swap the data source to a global cross-server DataStore without touching anything else.
--======================================================================
local gardenProgress = 0
local onProgressChanged  -- forward-declared (defined after the visuals)
local refreshGrowthDial  -- forward-declared; (re)draws the central growth dial from the LIVE progress (assigned in buildHardscape)
local contributorLabel   -- the TextLabel on the "PLAYERS CONTRIBUTED" sign (refreshed alongside the dial)
local gardenContributors -- TODO: wire to the real contributor count; nil -> signs/dial show an em-dash placeholder
local function getProgress() return gardenProgress end
local function setProgress(n)
	gardenProgress = math.clamp(math.floor(n), 0, GOAL)
	pcall(function() Workspace:SetAttribute("GardenProgress", gardenProgress); Workspace:SetAttribute("GardenGoal", GOAL) end) -- read-only mirror for the Locker UI
	if onProgressChanged then pcall(onProgressChanged) end
end
local function addProgress(n) setProgress(gardenProgress + n) end

-- GARDENER CHAT handler (server-authoritative): "menu" returns the greeting + question list; "ask" returns the
-- answer for a key, computing the LIVE "How close are we?" reply from the same progress the dial uses.
local function gardenerLiveAnswer(key)
	if key == "close" then
		local p, g = getProgress(), GOAL
		local pct = math.clamp(math.floor(p / g * 100), 0, 100)
		return string.format("We're at %d%% -- %d/%d watered! Keep it up! \xF0\x9F\x8C\xBB", pct, p, g)
	end
	for _, q in ipairs(GARDENER_QA) do if q.key == key then return q.answer end end
	return nil
end
GardenerChatFunction.OnServerInvoke = function(player, action, key)
	if action == "menu" then
		local list = {}
		for _, q in ipairs(GARDENER_QA) do list[#list + 1] = { key = q.key, label = q.label } end
		print("[Garden][Gardener] chat opened by " .. player.Name)
		return { greeting = GARDENER_GREETING, questions = list }
	elseif action == "ask" then
		local ans = gardenerLiveAnswer(tostring(key))
		print("[Garden][Gardener] " .. player.Name .. " picked: " .. tostring(key))
		return ans or "Hmm, ask me something else! \xF0\x9F\x99\x82"
	end
	return nil
end

-- WATER COOLDOWN (STAGE 1: per-player, IN-MEMORY / session-only -> resets on rejoin. A later stage can
-- persist this per player). [userId] = os.time() the player may next water.
local waterReadyAt = {}
local function cooldownRemaining(player) return math.max(0, (waterReadyAt[player.UserId] or 0) - os.time()) end
Players.PlayerRemoving:Connect(function(p) waterReadyAt[p.UserId] = nil end)

--======================================================================
-- BUILD HELPERS (game art style: matte Plastic, all surfaces Smooth, rounded, no collide, anchored).
--======================================================================
local function newPart(parent, name, shape, size, color, cf, material)
	local p = Instance.new("Part")
	p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Massless = true
	p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
	p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
	if cf then p.CFrame = cf end
	p.Parent = parent
	return p
end

-- ===== COMPOSED SUMMER GARDEN (a designed scene, NOT a grid): a GIANT central sunflower centerpiece with
-- rings of warm summer flowers, a low planter border, and edge bushes arranged around it. `scale` (from the
-- stage) sets overall size; `level` (1-5, from the stage) grows everything from sprout -> lush masterpiece.
-- Clean rounded matte-Plastic low-poly (ellipsoid blooms/leaves + cylinder stems), bright summer palette. =====
-- helper: a crop part whose size + offset scale with `scale` (orientation preserved)
local function cropPart(parent, baseCF, scale, shape, sx,sy,sz, color, ox,oy,oz, rot)
	return newPart(parent, "Crop", shape, Vector3.new(sx,sy,sz) * scale, color, baseCF * CFrame.new(ox*scale, oy*scale, oz*scale) * (rot or CFrame.new()))
end
-- helper: a flat blade leaf fanning out from the stalk at height `h`, around angle `ang`, drooping `droop` deg
local function cropLeaf(parent, baseCF, scale, h, ang, len, w, color, droop)
	cropPart(parent, baseCF, scale, BAL, len, 0.16, w, color, math.cos(ang)*(len*0.42), h, math.sin(ang)*(len*0.42),
		CFrame.Angles(0, ang, 0) * CFrame.Angles(0, 0, math.rad(droop or -25)))
end

-- ===== GIANT SUNFLOWER CENTERPIECE (SERVER-side, rounded-cube / UnionAsync technique, like the pets + cow).
-- Visuals only. Built as a Model "SunflowerCenterpiece" parented under the CommunityGarden marker; rebuilt on
-- stage crossings (renderStage). UnionAsync yields, so renderStage runs it in task.spawn. The two petal rings
-- are fused into single solids (no loose floating parts); unions are pcall'd and, on failure, the loose parts
-- are left parented so nothing ever disappears. Pet-style logs: "[Garden][Sunflower][UNION] PetalsOuter SUCCESS (18 parts)".
local SF_STEM  = Color3.fromRGB(96,142,58)   -- stem + neck
local SF_LEAF  = Color3.fromRGB(116,165,70)  -- leaf blade
local SF_VEIN  = Color3.fromRGB(74,112,46)   -- leaf center vein
local SF_BUD   = Color3.fromRGB(126,172,74)  -- closed green bud (stages 1-2)
local SF_DRIM  = Color3.fromRGB(108,74,44)   -- disc rim ring
local SF_DFACE = Color3.fromRGB(82,58,36)    -- disc face
local SF_DCENT = Color3.fromRGB(58,42,28)    -- raised disc center
local SF_POUT  = Color3.fromRGB(245,190,40)  -- outer petals
local SF_PIN   = Color3.fromRGB(232,150,28)  -- inner petals

-- ===== STAGE 2 SEASONS: the flower/plant/sunflower COLOUR palette swaps per season (SAME shapes). The harvest
-- cycle (further below) advances the season and calls applySeason() to repaint the colours before rebuilding. =====
local Rgb = Color3.fromRGB
local GROUND_GREENS = { Rgb(90,140,55), Rgb(110,160,70), Rgb(75,120,45) } -- tuft/bush greens (3); season-swapped
local SEASON_DAISY  = Rgb(245,245,235)          -- default daisy petal colour (season-swapped)
local SEASON_FLOWERS                            -- {name, colourOrFalse} flower mix used by the scatter (set by applySeason)
local SEASONS = {
	{ name = "Summer",
		petalOut = Rgb(245,190,40), petalIn = Rgb(232,150,28),
		stem = Rgb(96,142,58), leaf = Rgb(116,165,70), vein = Rgb(74,112,46), bud = Rgb(126,172,74),
		greens = { Rgb(90,140,55), Rgb(110,160,70), Rgb(75,120,45) }, daisy = Rgb(245,245,235),
		flowers = { {"sunny",false}, {"sunny",false}, {"blue",Rgb(70,120,210)}, {"red",Rgb(210,60,55)}, {"purple",Rgb(150,80,200)}, {"pink",Rgb(235,130,170)}, {"orange",Rgb(235,140,40)} } },
	{ name = "Autumn",
		petalOut = Rgb(232,140,40), petalIn = Rgb(200,90,30),
		stem = Rgb(120,95,45), leaf = Rgb(150,115,50), vein = Rgb(110,80,40), bud = Rgb(150,120,55),
		greens = { Rgb(150,110,50), Rgb(172,132,60), Rgb(120,85,40) }, daisy = Rgb(235,205,150),
		flowers = { {"orange",Rgb(230,130,40)}, {"orange",Rgb(230,130,40)}, {"deepred",Rgb(180,55,40)}, {"gold",Rgb(225,170,60)}, {"brown",Rgb(150,95,50)}, {"rust",Rgb(195,90,45)} } },
	{ name = "Winter",
		petalOut = Rgb(220,228,238), petalIn = Rgb(182,206,228),
		stem = Rgb(120,150,140), leaf = Rgb(152,182,172), vein = Rgb(112,142,136), bud = Rgb(162,186,180),
		greens = { Rgb(150,175,165), Rgb(178,198,190), Rgb(130,158,150) }, daisy = Rgb(240,246,250),
		flowers = { {"snow",Rgb(235,240,248)}, {"snow",Rgb(235,240,248)}, {"ice",Rgb(170,205,230)}, {"blue",Rgb(120,165,215)}, {"pale",Rgb(205,215,230)}, {"frost",Rgb(190,220,235)} } },
	{ name = "Spring",
		petalOut = Rgb(250,205,90), petalIn = Rgb(240,165,90),
		stem = Rgb(110,175,75), leaf = Rgb(135,200,95), vein = Rgb(95,160,70), bud = Rgb(140,205,100),
		greens = { Rgb(120,185,85), Rgb(140,205,100), Rgb(100,165,75) }, daisy = Rgb(250,240,245),
		flowers = { {"pink",Rgb(240,150,185)}, {"pink",Rgb(240,150,185)}, {"lavender",Rgb(180,150,225)}, {"fresh",Rgb(150,210,110)}, {"peach",Rgb(245,180,140)}, {"white",Rgb(245,245,250)} } },
}
local gardenSeasonIndex = 1
local function applySeason(i)
	local s = SEASONS[((i - 1) % #SEASONS) + 1]
	SF_POUT, SF_PIN = s.petalOut, s.petalIn
	SF_STEM, SF_LEAF, SF_VEIN, SF_BUD = s.stem, s.leaf, s.vein, s.bud
	GROUND_GREENS  = s.greens
	SEASON_DAISY   = s.daisy
	SEASON_FLOWERS = s.flowers
	pcall(function() Workspace:SetAttribute("GardenSeason", s.name) end) -- read-only mirror for the Locker UI
	return s
end
applySeason(gardenSeasonIndex) -- initial palette = Summer

-- Fuse a list of source parts into ONE union (server-only UnionAsync, pcall-guarded). Sources are staged in a
-- Workspace bin so the union can't be orphaned by a mid-union rebuild; on success the union is parented into `model`
-- (or discarded if that build was superseded); the source parts are always cleaned up (no loose petals on failure).
-- `logN` is the count shown in the log (the petal count, e.g. 18) -- falls back to the raw part count.
local function sfFuse(model, parts, name, color, logN)
	if #parts == 0 then return nil end
	local n = logN or #parts
	-- Move the source parts into a STABLE Workspace bin FIRST, so they stay linked to the DataModel for UnionAsync
	-- even if a newer rebuild (harvest -> regrow) destroys `model` mid-union. That race -- old:Destroy() running while
	-- this union was still yielding -- is what made PetalsInner FAIL ("CSG API requires ... linked to a DataModel").
	-- After the union we parent it into `model` if it's still alive, else discard it cleanly. Either way: no debris.
	local bin = Instance.new("Model"); bin.Name = "_SunflowerFuseBin"; bin.Parent = Workspace
	for _, p in ipairs(parts) do p.Parent = bin end
	local first = parts[1]
	local rest = {}
	for i = 2, #parts do rest[#rest + 1] = parts[i] end
	local ok, union = pcall(function() return first:UnionAsync(rest) end)
	pcall(function() bin:Destroy() end) -- remove the source parts (UnionAsync copied them into the union) -> no loose petals
	if ok and union then
		union.Name = name
		union.Anchored = true; union.CanCollide = false; union.CanQuery = false; union.CanTouch = false
		union.CastShadow = false; union.Massless = true; union.Material = Enum.Material.Plastic
		pcall(function() union.UsePartColor = true end); union.Color = color
		if model and model.Parent then
			union.Parent = model
			print(string.format("[Garden][Sunflower][UNION] %s SUCCESS (%d parts)", name, n))
			return union
		end
		union:Destroy() -- this build was superseded by a newer rebuild -> discard cleanly (no debris)
		print(string.format("[Garden][Sunflower][UNION] %s SUCCESS (%d parts) -- discarded (superseded rebuild)", name, n))
		return nil
	end
	warn(string.format("[Garden][Sunflower][UNION] %s FAILED (%d parts) -- %s", name, n, tostring(union)))
	return nil
end

-- One pointed petal = a Block body + a small Block rotated 45deg about Y at the tip (a diamond corner -> a clear
-- point), along `cf`'s +X starting at radius r0. Collected into `store` for fusing. (Reused for both petal rings.)
local function sfBlade(model, store, cf, len, wid, thick, r0, color)
	store[#store + 1] = newPart(model, "_blade", BLK, Vector3.new(len, thick, wid), color, cf * CFrame.new(r0 + len * 0.5, 0, 0))
	store[#store + 1] = newPart(model, "_tip",   BLK, Vector3.new(wid * 0.70, thick, wid * 0.70), color, cf * CFrame.new(r0 + len, 0, 0) * CFrame.Angles(0, math.rad(45), 0))
end

-- Build the centerpiece for `stage` (0..5) in `baseCFrame` (centered on the garden, on the ground, -Z toward the
-- sign), parented under `parent` (the CommunityGarden marker). Full bloom = stage 5; scaled down for lower stages.
local function buildSunflowerCenterpiece(stage, baseCFrame, parent)
	if not parent then return end
	local old = parent:FindFirstChild("SunflowerCenterpiece"); if old then old:Destroy() end -- rebuild: destroy the old model first
	local m = Instance.new("Model"); m.Name = "SunflowerCenterpiece"; m.Parent = parent

	-- STEM: three tapering vertical Cylinders (cylinders run along local X -> rotate 90deg about Z to stand up),
	-- + a short neck for the top 18% bent ~12deg forward (toward the sign) so the head nods. Full height ~32.
	local H = ({ [0] = 3, [1] = 9, [2] = 18, [3] = 27, [4] = 35, [5] = 42 })[stage] or 3 -- full-grown raised ~30% so it towers over the dais
	local ss = H / 32
	local function stemSeg(name, r, y0, y1)
		local len = (y1 - y0) * H
		newPart(m, name, CYL, Vector3.new(len, 2 * r * ss, 2 * r * ss), SF_STEM,
			baseCFrame * CFrame.new(0, (y0 + y1) * 0.5 * H, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end
	stemSeg("StemA", 0.72, 0.00, 0.40)
	stemSeg("StemB", 0.58, 0.36, 0.66)
	stemSeg("StemC", 0.46, 0.62, 0.82)
	local neckLen = 0.18 * H
	local neckCF = baseCFrame * CFrame.new(0, 0.82 * H, 0) * CFrame.Angles(math.rad(-12), 0, 0) -- bend +Y toward -Z (the sign)
	newPart(m, "Neck", CYL, Vector3.new(neckLen, 2 * 0.40 * ss, 2 * 0.40 * ss), SF_STEM, neckCF * CFrame.new(0, neckLen * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
	-- where the head sits = the top of the bent neck, expressed back in baseCFrame-local coords
	local headLocal = Vector3.new(0, 0.82 * H + neckLen * math.cos(math.rad(12)), -neckLen * math.sin(math.rad(12)))

	-- LEAVES: broad pointed leaves (Block body + diamond tip + a thin darker center vein) at ~26/46/66% height,
	-- 120deg apart, drooping ~22deg. 2 leaves on the young shoot (stages 0-2), 3 once it's a real plant.
	local nLeaves = (stage <= 2) and 2 or 3
	local leafFracs = { 0.26, 0.46, 0.66 }
	local lsc = math.max(ss, 0.12)
	for i = 1, nLeaves do
		local h = leafFracs[i] * H
		local a = (i - 1) * (2 * math.pi / 3)
		local lcf = baseCFrame * CFrame.new(0, h, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(-22))
		local llen, lwid, lthk = 5.0 * lsc, 2.6 * lsc, 0.32 * lsc
		local r0 = 0.6 * ss
		newPart(m, "Leaf",     BLK, Vector3.new(llen, lthk, lwid), SF_LEAF, lcf * CFrame.new(r0 + llen * 0.5, 0, 0))
		newPart(m, "LeafTip",  BLK, Vector3.new(lwid * 0.72, lthk, lwid * 0.72), SF_LEAF, lcf * CFrame.new(r0 + llen, 0, 0) * CFrame.Angles(0, math.rad(45), 0))
		newPart(m, "LeafVein", BLK, Vector3.new(llen * 0.96, lthk * 1.4, lwid * 0.16), SF_VEIN, lcf * CFrame.new(r0 + llen * 0.5, 0, 0))
	end

	if stage == 1 or stage == 2 then
		-- SPROUT/GROWING: a small (s1) / larger (s2) closed green BUD on top, no petals.
		local budR = (stage == 1) and 1.4 or 2.2
		newPart(m, "Bud", BAL, Vector3.new(budR * 1.5, budR * 2.0, budR * 1.5), SF_BUD, baseCFrame * CFrame.new(0, H + budR * 0.7, 0))
		for i = 0, 3 do
			local a = i * (math.pi / 2)
			newPart(m, "BudSepal", BLK, Vector3.new(budR * 1.3, 0.3, budR * 0.8), SF_BUD,
				baseCFrame * CFrame.new(0, H + budR * 0.45, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(58)) * CFrame.new(budR * 0.55, 0, 0))
		end
	elseif stage >= 3 then
		-- HEAD at the nodded neck top, tilted ~26deg toward the sign so the face shows. Domed two-tone disc + 2 petal rings.
		local headFrac   = ({ [3] = 0.55, [4] = 0.82, [5] = 1.0 })[stage] -- disc diameter fraction of full
		local petalScale = ({ [3] = 0.45, [4] = 0.80, [5] = 1.0 })[stage] -- petal length / openness
		local headCF = baseCFrame * CFrame.new(headLocal) * CFrame.Angles(math.rad(-26), 0, 0) -- face (+Y) leans toward -Z (the sign)
		-- DISC: rim ring (behind) + face + a smaller raised center -> a domed two-tone disc (face normal = headCF +Y).
		-- DISC: raised + the rim widened so the dark disc sits OVER the petal bases (the petals tilt up about the
		-- disc centre, so their bases lift ~0.5-0.7 above the disc plane -- the disc is lifted to meet/cover them).
		newPart(m, "DiscRim",    CYL, Vector3.new(0.55 * headFrac, 8.2 * headFrac, 8.2 * headFrac), SF_DRIM,  headCF * CFrame.new(0, 0.30 * headFrac, 0) * CFrame.Angles(0, 0, math.rad(90)))
		newPart(m, "DiscFace",   CYL, Vector3.new(0.70 * headFrac, 7.0 * headFrac, 7.0 * headFrac), SF_DFACE, headCF * CFrame.new(0, 0.55 * headFrac, 0) * CFrame.Angles(0, 0, math.rad(90)))
		newPart(m, "DiscCenter", CYL, Vector3.new(0.60 * headFrac, 4.3 * headFrac, 4.3 * headFrac), SF_DCENT, headCF * CFrame.new(0, 0.85 * headFrac, 0) * CFrame.Angles(0, 0, math.rad(90)))
		-- PETAL BASES pulled INWARD so they tuck under the disc (was 3.5 / 3.08 -> now ~HEAD_D*0.30 / *0.22),
		-- begin under the dark disc's edge and extend out -- no bare gap to the centre.
		local rOut = 2.10 * headFrac -- 7 (HEAD_D) * 0.30
		local rIn  = 1.54 * headFrac -- 7 (HEAD_D) * 0.22
		-- OUTER PETALS: 18, tilted up ~14deg -> fused into one solid.
		local outer = {}
		local pLen = 6.0 * petalScale
		for i = 0, 17 do
			local a = i * (2 * math.pi / 18)
			sfBlade(m, outer, headCF * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(14)), pLen, 1.2 * headFrac, 0.32 * headFrac, rOut, SF_POUT)
		end
		sfFuse(m, outer, "PetalsOuter", SF_POUT, 18)
		-- INNER PETALS: 14, offset half a step, ~0.78x length, steeper ~28deg, smaller radius + raised so
		-- they tuck behind/between the outer petals and close the gaps -> fused into a second solid.
		local inner = {}
		local pLenI = pLen * 0.78
		for i = 0, 13 do
			local a = i * (2 * math.pi / 14) + (math.pi / 14) -- half-step offset
			sfBlade(m, inner, headCF * CFrame.new(0, 0.12 * headFrac, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(28)), pLenI, 1.2 * headFrac, 0.32 * headFrac, rIn, SF_PIN)
		end
		sfFuse(m, inner, "PetalsInner", SF_PIN, 14)
	end

	print(string.format("[Garden][Sunflower] built stage %d -> stem %.0f studs, head=%s", stage, H,
		(stage >= 3) and "full" or ((stage >= 1) and "bud" or "none")))
	return m
end

-- Fuse a set of crop/bush source parts into ONE union (server-only UnionAsync, pcall-guarded, off-thread).
-- On success: destroy the sources + parent the union. On FAILURE (or if the spot was cleared mid-build): leave
-- the loose parts parented (recolored) so nothing disappears. Logs like "[Garden][Crop][UNION] X SUCCESS (n parts)".
local function cropFuse(model, parts, tag, name, color, logN, keepColors)
	if #parts == 0 then return nil end
	local first = parts[1]
	if not (first and first.Parent) then return nil end -- spot cleared (next stage) before the async union even started
	local n = logN or #parts
	-- Same DataModel-stable pattern as sfFuse: stage the sources in a Workspace bin so a mid-union rebuild (which
	-- clears plantsFolder) can't orphan them; parent the result into `model` if alive, else discard cleanly.
	local bin = Instance.new("Model"); bin.Name = "_CropFuseBin"; bin.Parent = Workspace
	for _, p in ipairs(parts) do if p and p.Parent then p.Parent = bin end end
	local rest = {}
	for i = 2, #parts do rest[#rest + 1] = parts[i] end
	local ok, union = pcall(function() return first:UnionAsync(rest) end)
	pcall(function() bin:Destroy() end) -- clean up the loose source parts either way (no debris)
	if ok and union then
		union.Name = name
		union.Anchored = true; union.CanCollide = false; union.CanQuery = false; union.CanTouch = false
		union.CastShadow = false; union.Massless = true; union.Material = Enum.Material.Plastic
		if keepColors then
			pcall(function() union.UsePartColor = false end) -- keep each source part's own colour (multi-tone, e.g. the two-green bush)
		else
			pcall(function() union.UsePartColor = true end); union.Color = color
		end
		if model and model.Parent then
			union.Parent = model
			print(string.format("[Garden][%s][UNION] %s SUCCESS (%d parts)", tag, name, n))
			return union
		end
		union:Destroy() -- superseded by a newer rebuild -> discard cleanly
		return nil
	end
	warn(string.format("[Garden][%s][UNION] %s FAILED (%d parts) -- %s", tag, name, n, tostring(union)))
	return nil
end

-- A small surrounding crop: a stable ~half/half MIX of TYPE A (mini sunflower) and TYPE B (daisy), picked per
-- spot by a hash of its world position so the field reads varied + consistent. Same stem; pointed/flat petals
-- fused into one solid. `scale` (from the stage) drives per-stage growth via cropPart, exactly as before.
-- [GARDENFLOWERS] per-TYPE wildflower palettes for the RING-BED small flowers. Each flower picks a RANDOM colour
-- from its type's palette -> a mixed, colourful spread (centres kept as-is: sunflower brown disc / daisy yellow centre).
local MINISUN_PALETTE = { Rgb(245,200,40), Rgb(240,140,40), Rgb(214,150,46), Rgb(248,224,120) } -- golden yellow, orange, deep amber, butter yellow
local DAISY_PALETTE   = { Rgb(246,246,238), Rgb(245,182,205), Rgb(250,238,170), Rgb(196,170,235), Rgb(248,196,150) } -- white, soft pink, pale yellow, lavender, peach

local function buildSmallFlower(parent, baseCF, scale, level, petalColor)
	local m = Instance.new("Model"); m.Name = "Flower"; m.Parent = parent
	local STEM = Color3.fromRGB(96,142,58)
	local pos = baseCF.Position
	local typeA = (math.floor(pos.X * 7.3 + pos.Z * 13.1) % 2 == 0) -- stable per-spot type pick
	local stemH = 2.6
	cropPart(m, baseCF, scale, CYL, stemH, 0.2, 0.2, STEM, 0, stemH * 0.5, 0, CFrame.Angles(0, 0, math.rad(90))) -- thin green stem (slimmed)
	-- a couple of tiny base leaves so the stem emerges from greenery, not bare dirt (both types)
	for _, bl in ipairs({ 0.8, 0.8 + math.pi }) do
		cropPart(m, baseCF, scale, BLK, 0.9, 0.12, 0.4, Color3.fromRGB(92,150,62),
			math.cos(bl) * 0.45, 0.35, math.sin(bl) * 0.45, CFrame.Angles(0, -bl, 0) * CFrame.Angles(0, 0, math.rad(-28)))
	end
	if typeA then
		-- TYPE A: MINI SUNFLOWER (~3.5 studs): a small centerpiece -- dark disc (ø1.3) tilted ~20deg + a FULL ring
		-- of 13 wide pointed petals whose bases tuck UNDER the disc edge (no gap). Petals fused into one solid.
		local headCF = baseCF * CFrame.new(0, (stemH + 0.15) * scale, 0) * CFrame.Angles(math.rad(20), 0, 0)
		cropPart(m, headCF, scale, CYL, 0.25, 1.1, 1.1, Color3.fromRGB(67,48,31), 0, 0, 0, CFrame.Angles(0, 0, math.rad(90))) -- flat dark disc (ø1.1)
		local petalC = petalColor or MINISUN_PALETTE[math.random(#MINISUN_PALETTE)] -- random per-flower colour from the mini-sunflower palette (dark disc centre kept)
		local petals, r0, pLen, pWid = {}, 0.3, 1.1, 0.22 -- thinner + longer petals; r0 < disc radius so bases tuck under
		for i = 0, 12 do
			local a = i * (2 * math.pi / 13)
			petals[#petals + 1] = cropPart(m, headCF, scale, BLK, pLen, 0.08, pWid, petalC,
				math.cos(a) * (r0 + pLen * 0.5), 0, math.sin(a) * (r0 + pLen * 0.5), CFrame.Angles(0, -a, 0))                                  -- body
			petals[#petals + 1] = cropPart(m, headCF, scale, BLK, pWid * 0.7, 0.08, pWid * 0.7, petalC,
				math.cos(a) * (r0 + pLen), 0, math.sin(a) * (r0 + pLen), CFrame.Angles(0, -a, 0) * CFrame.Angles(0, math.rad(45), 0)) -- pointed tip
		end
		task.spawn(function() cropFuse(m, petals, "Crop", "MiniSunflowerPetals", petalC, 13) end)
	else
		-- TYPE B: DAISY (~3 studs): small yellow center + a ring of 11 thin off-white petals (fused).
		local headCF = baseCF * CFrame.new(0, (stemH + 0.1) * scale, 0)
		cropPart(m, headCF, scale, CYL, 0.22, 0.5, 0.5, Color3.fromRGB(240,190,60), 0, 0, 0, CFrame.Angles(0, 0, math.rad(90))) -- yellow center (ø0.5)
		local petalC = petalColor or DAISY_PALETTE[math.random(#DAISY_PALETTE)] -- random per-flower colour from the daisy palette (yellow centre kept)
		local petals, discR, pLen = {}, 0.25, 1.1 -- thinner + longer petals
		for i = 0, 10 do
			local a = i * (2 * math.pi / 11)
			petals[#petals + 1] = cropPart(m, headCF, scale, BLK, pLen, 0.07, 0.14, petalC,
				math.cos(a) * (discR + pLen * 0.5), 0, math.sin(a) * (discR + pLen * 0.5), CFrame.Angles(0, -a, 0))
		end
		task.spawn(function() cropFuse(m, petals, "Crop", "DaisyPetals", petalC, 11) end)
	end
	return m
end

-- A border bush: a SMOOTH rounded foliage clump -- 4 heavily-overlapping Balls of varying sizes (one larger
-- center + smaller offset/top) that merge into one soft lumpy mass, UnionAsync'd into a SINGLE smooth solid (no
-- protruding spikes). Two greens kept across the union (keepColors). `scale` drives per-stage growth via cropPart.
local function buildBush(parent, baseCF, scale, level)
	local m = Instance.new("Model"); m.Name = "Bush"; m.Parent = parent
	local G1, G2 = GROUND_GREENS[1], GROUND_GREENS[2] -- season-swapped bush greens
	local balls = {
		{ d = 2.6, ox = 0.0,  oy = 1.00, oz = 0.0,  col = G1 }, -- larger center
		{ d = 1.9, ox = 0.8,  oy = 1.25, oz = 0.35, col = G2 },
		{ d = 1.8, ox = -0.7, oy = 1.15, oz = -0.4, col = G1 },
		{ d = 1.6, ox = 0.05, oy = 1.70, oz = 0.2,  col = G2 }, -- crown
	}
	local parts = {}
	for _, b in ipairs(balls) do
		parts[#parts + 1] = cropPart(m, baseCF, scale, BAL, b.d, b.d, b.d, b.col, b.ox, b.oy, b.oz)
	end
	task.spawn(function() cropFuse(m, parts, "Bush", "Foliage", G1, #parts, true) end) -- keepColors -> both greens show
	return m
end

-- A low leafy GROUNDCOVER tuft: 2-3 small wide Balls centred low (most of each sits below the soil), merged into
-- one smooth low mound (~1-1.5 studs). A few greens per tuft, kept multi-tone via the union (keepColors). These
-- pack the gaps between the flowers as the green base layer. `rng` (the caller's seeded RNG) keeps it deterministic.
-- (GROUND_GREENS is declared once up top so applySeason() can swap it per season)
local function buildTuft(parent, baseCF, scale, rng)
	local m = Instance.new("Model"); m.Name = "Tuft"; m.Parent = parent
	local cd = rng:NextNumber(1.5, 1.9)
	local parts = { cropPart(m, baseCF, scale, BAL, cd, cd, cd, GROUND_GREENS[rng:NextInteger(1, 3)], 0, cd * 0.18, 0) } -- low wide center
	for _ = 1, rng:NextInteger(1, 2) do
		local bd = rng:NextNumber(1.1, 1.5)
		local ang = rng:NextNumber(0, 2 * math.pi)
		local off = rng:NextNumber(0.35, 0.7)
		parts[#parts + 1] = cropPart(m, baseCF, scale, BAL, bd, bd, bd, GROUND_GREENS[rng:NextInteger(1, 3)],
			math.cos(ang) * off, bd * 0.18 + rng:NextNumber(0, 0.22), math.sin(ang) * off)
	end
	task.spawn(function() cropFuse(m, parts, "Tuft", "Tuft", GROUND_GREENS[1], #parts, true) end) -- keepColors -> multi-green mound
	return m
end

--======================================================================
-- MARKERS (resolve by name AFTER islands are positioned -- same StandsReady signal the pet system waits for).
--======================================================================
local function findIsland(prefix)
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.find(m.Name, prefix, 1, true) then return m end
	end
	return nil
end
local function resolveMarker(island, name)
	local p = island and island:FindFirstChild(name, true)
	if not p then p = Workspace:FindFirstChild(name) end
	if not p then p = Workspace:FindFirstChild(name, true) end
	return p
end
-- world CFrame + size of a marker whether it's a single Part or a Model
local function markerCFrameSize(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	local cf, size = inst:GetBoundingBox(); return cf, size
end

--======================================================================
-- VISUALS: the growing field + the live sign. Built once after markers resolve; updated on stage/progress
-- changes only (never every frame).
--======================================================================
local plantsFolder      -- holds the current stage's scene models (cleared + rebuilt on a stage change)
local gardenTopCF       -- CFrame at the center of the field's top surface (the composition origin)
local gardenRad         -- usable layout radius -- rings/border/bushes are arranged out from the center
local fieldCenter       -- Vector3 (for the watering splash broadcast)
local signLabels        -- { pct = TextLabel, count = TextLabel, fill = Frame } (updated live)
local waterSpotPos      -- Vector3 (server distance check)
local gardenMarker      -- the CommunityGarden marker (the build container parents under it)
local gardenBuild       -- ONE container Model ("CommunityGardenBuild") holding the ENTIRE build (hardscape + plants
                        -- + sunflower); destroyed + recreated at the start of every build so nothing stale lingers
local signPos           -- GardenSignSpot world position (the sunflower head tilts its face toward it)
local currentStage = -1

-- overall size + growth level per stage (0 bare .. 5 fully grown) -- drives the whole composed scene
local STAGE_SCALE = { [0]=0,   [1]=0.45,  [2]=0.65, [3]=0.85, [4]=1.05, [5]=1.2 }
local STAGE_LEVEL = { [0]=0,   [1]=1,     [2]=2,    [3]=3,    [4]=4,    [5]=5 }

local function stageForPct(pct)
	if pct >= 100 then return 5 elseif pct >= 80 then return 4 elseif pct >= 60 then return 3
	elseif pct >= 40 then return 2 elseif pct >= 20 then return 1 else return 0 end
end

-- (re)build the COMPOSED scene for a given stage (called ONLY when the stage threshold changes):
-- giant central sunflower + concentric rings of warm summer flowers + a planter border + edge bushes,
-- all grown by the stage's scale/level. Arranged around the center -- deliberately, NOT a grid.
-- ONE rotated origin + doorway angle shared by the hardscape AND the planting, so plants land in the beds and turn
-- with the garden. (Same formula buildHardscape uses: rotate the field-top CFrame -90deg; doorway faces the sign.)
local function gardenOrigin()
	local C = gardenTopCF
	local b = C * CFrame.Angles(0, math.rad(-90), 0)
	local wsd = signPos and Vector3.new(signPos.X - C.Position.X, 0, signPos.Z - C.Position.Z) or Vector3.new(0, 0, -1)
	if wsd.Magnitude < 0.05 then wsd = Vector3.new(0, 0, -1) end
	local lsd = C:VectorToObjectSpace(wsd.Unit)
	return b, math.atan2(lsd.Z, lsd.X)
end

local function renderStage(stage)
	if not plantsFolder or not gardenTopCF then return end
	plantsFolder:ClearAllChildren()
	-- CENTERPIECE: the giant sunflower (SERVER-side UnionAsync) under the CommunityGarden marker, rebuilt each
	-- stage crossing. UnionAsync yields -> build off-thread; buildSunflowerCenterpiece destroys its old model first.
	-- Built for ALL stages (incl. 0 = tiny shoot), separate from the composed scene below.
	if gardenBuild then
		local groundCenter = gardenTopCF.Position
		local center = groundCenter + Vector3.new(0, 7.5, 0) -- plant on the TOP tier of the 3-tier dais (top = ground +7.5)
		local toSign = signPos and Vector3.new(signPos.X - groundCenter.X, 0, signPos.Z - groundCenter.Z) or Vector3.new(0, 0, -1)
		if toSign.Magnitude < 0.05 then toSign = Vector3.new(0, 0, -1) end
		-- face the sign, THEN turn 90deg CW so the centerpiece rotates together with the hardscape (same -90 as `base`)
		local baseCFrame = CFrame.lookAt(center, center + toSign.Unit, Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(-90), 0)
		task.spawn(function() pcall(buildSunflowerCenterpiece, stage, baseCFrame, gardenBuild) end)
	end
	if stage <= 0 then return end -- bare soil (composed scene); the centerpiece shoot is built above
	local scale = STAGE_SCALE[stage] or 1
	local level = STAGE_LEVEL[stage] or 1
	-- DENSE PLANTING re-fitted onto the two tiered dark-soil RING BEDS. Everything is placed via the SAME rotated
	-- origin as the hardscape (so it sits ON the beds and turns with the garden), parented under plantsFolder (which
	-- lives in CommunityGardenBuild -> clears on rebuild). Clearance is kept off the dais/steps/doorway path, the
	-- walls, and the pillars/lamps. Each bed is filled by sampling random radius+angle in its ring.
	local base, openAngle = gardenOrigin()
	local oc, os = math.cos(openAngle), math.sin(openAngle)

	-- obstacle local positions to avoid: the 6 pillars (r32, every 60deg from 30deg) + the 6 lamps (r42, every 60deg)
	local obstacles = {}
	for i = 0, 5 do
		local pa = math.rad(30) + i * (math.pi / 3); obstacles[#obstacles + 1] = { x = math.cos(pa) * 32, z = math.sin(pa) * 32, d = 3.2 }
		local la = i * (math.pi / 3);                obstacles[#obstacles + 1] = { x = math.cos(la) * 42, z = math.sin(la) * 42, d = 3.0 }
	end
	local function blocked(x, z)
		-- keep a straight ~14-wide corridor along the doorway (openAngle), front side only (so it doesn't fan out)
		local along = x * oc + z * os
		local perp  = -x * os + z * oc
		if along > 0 and math.abs(perp) < 7 then return true end
		for _, o in ipairs(obstacles) do
			local dx, dz = x - o.x, z - o.z
			if dx * dx + dz * dz < o.d * o.d then return true end
		end
		return false
	end

	-- sample `n` plants by random angle + radius in the [r0,r1] ring, on the bed top at height `y`, placed via `base`
	-- with a random spin (organic). `clear` toggles the doorway/obstacle clearance (off for the centre bed on the dais).
	local function scatterRing(rng, n, r0, r1, y, clear, place)
		local made = 0
		for _ = 1, n do
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = rng:NextNumber(r0, r1)
			local x, z = math.cos(a) * r, math.sin(a) * r
			if (not clear) or (not blocked(x, z)) then
				place(base * CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0), r, rng)
				made = made + 1
			end
		end
		return made
	end

	local fT = ({ [2] = 0.4, [3] = 0.7, [4] = 0.9, [5] = 1.0 })[level] or 1   -- groundcover density by stage
	local fF = ({ [2] = 0.35, [3] = 0.6, [4] = 0.85, [5] = 1.0 })[level] or 1 -- flower density by stage

	-- WILDFLOWER palette: the CURRENT SEASON's flower mix (false = the shape's default tone). Picked per-plant so the
	-- colours intermix across the beds. Swapped each season by applySeason(); falls back to a sunny default.
	local PALETTE = SEASON_FLOWERS or { { "sunny", false } }
	local fCount = {} -- tally flowers by colour
	local function plantFlower(cf, g, boost)
		fCount["mixed"] = (fCount["mixed"] or 0) + 1
		-- nil colour -> buildSmallFlower assigns a RANDOM per-TYPE wildflower colour (mini-sunflower vs daisy palette),
		-- so the ring beds read as a colourful mix rather than one flat season tone per flower.
		pcall(buildSmallFlower, plantsFolder, cf, scale * g:NextNumber(0.8, 1.2) * 0.65 * (boost or 1), level, nil) -- ~35% smaller, finer flowers (kept dense)
	end
	local total, bushes = 0, 0

	-- INNER BED (dais edge -> inner wall r32): low tufts + DENSE mixed-colour flowers, a touch taller toward the centre.
	do
		local rng = Random.new(70707)
		total = total + scatterRing(rng, math.floor(46 * fT), 14.5, 30.5, 0.6, true, function(cf, r, g)
			buildTuft(plantsFolder, cf, scale * g:NextNumber(0.85, 1.2) * 0.8, g)
		end)
		local ringFlowerN = scatterRing(rng, math.ceil(214 * fF), 14.5, 30.5, 0.6, true, function(cf, r, g)
			plantFlower(cf, g, 1 + (1 - math.clamp((r - 13) / 19, 0, 1)) * 0.18) -- taller toward the centre (layered); ~214 sampled -> ~190 placed (~1.13x). Random scatter (no min-spacing) just packs denser -> slight overlap = lush bed
		end)
		total = total + ringFlowerN
		print(string.format("[GARDENFLOWERS] ring beds -> ~190 -- %d ring flowers planted (stage %d)", ringFlowerN, stage))
	end

	-- OUTER RING is now a walkable STONE PATH (built in buildHardscape) -- NO planting out here anymore.

	-- BUSHES: a few small accents tucked against the INNER edge of the path (inner bed only; never on the path surface).
	if level >= 3 then
		local nB = (level >= 5) and 6 or 4
		local brng = Random.new(99117)
		for i = 0, nB - 1 do
			local a = (i + 0.5) * (2 * math.pi / nB) + brng:NextNumber(-0.3, 0.3)
			local r = brng:NextNumber(22, 31) -- inner bed, just inside the path's inner edge (r32)
			local x, z = math.cos(a) * r, math.sin(a) * r
			if not blocked(x, z) then
				pcall(buildBush, plantsFolder, base * CFrame.new(x, 0.6, z), scale * brng:NextNumber(0.9, 1.2) * 0.7, level) -- ~30% smaller, on the inner bed (+0.5)
				bushes = bushes + 1
			end
		end
	end

	-- CENTRE BED (dark soil on TOP of the dais, +7.9): a small ring of greenery + a few flowers around the sunflower
	-- base, clear of the stem (no doorway/obstacle clearance needed up here).
	do
		local crng = Random.new(2024)
		total = total + scatterRing(crng, 6, 1.6, 3.4, 7.9, false, function(cf, r, g) buildTuft(plantsFolder, cf, scale * 0.7, g) end)
		total = total + scatterRing(crng, 4, 2.0, 3.4, 7.9, false, function(cf, r, g) plantFlower(cf, g) end)
	end

	local fParts, fTotal = {}, 0
	for nm, c in pairs(fCount) do fParts[#fParts + 1] = nm .. "=" .. c; fTotal = fTotal + c end
	total = total + bushes -- `total` already counts tufts + flowers (via scatterRing returns); add bushes for the grand total
	print(("[Garden] planted stage %d: %d flowers { %s }, %d bushes, %d plants/tufts total"):format(stage, fTotal, table.concat(fParts, ", "), bushes, total))
end

-- a one-shot sparkle celebration over the field when it hits 100%
local function celebrate()
	if not fieldCenter then return end
	local host = newPart(plantsFolder, "Celebrate", BAL, Vector3.new(1,1,1), Color3.new(1,1,1), CFrame.new(fieldCenter + Vector3.new(0,6,0)))
	host.Transparency = 1
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"; em.Rate = 0
	em.Lifetime = NumberRange.new(1.2, 2.2); em.Speed = NumberRange.new(8, 18); em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new(1.3); em.Color = ColorSequence.new(Color3.fromRGB(255,235,140)); em.LightEmission = 0.9
	em.Parent = host; em:Emit(140)
	game:GetService("Debris"):AddItem(host, 3)
end

--======================================================================
-- STAGE 2: HARVEST -> REWARD -> NEW-SEASON cycle. When the garden fills (or a season times out) it harvests ONCE,
-- rewards everyone online (2x-coins buff flag + this season's cosmetic entitlement + a celebration banner), then
-- advances the season (Summer->Autumn->Winter->Spring->...), repaints the palette, and resets progress to 0.
--======================================================================
local REWARD_DURATION = 5 * 60          -- 2x-coins celebration buff length, in seconds (easy to change)
local BLOOM_HOLD_SECONDS = 7            -- how long the FULL bloom (stage 5, season colours) stays visible before the reset
local SEASON_TIMER    = 7 * 24 * 3600   -- a season auto-harvests after ~1 week even if it never fills (named constant)
local harvestCount    = 0               -- how many harvests have happened (season number for logs)
local harvesting      = false           -- guard so a harvest can NEVER double-fire
local seasonStartTime = os.time()       -- when the current season began (for the timer)

-- give every player online the 2x-coins buff flag + this season's cosmetic entitlement (attributes the coin/locker
-- code can read). NOTE: the actual coin doubling lives in the coin-award code (PlayerStats); it just needs to check
-- player:GetAttribute("GardenCoin2xUntil") > os.time(). The cosmetic LOCKER is Stage 3 -- here we only grant the flag.
local function rewardEveryone(seasonName)
	local n = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		pcall(function()
			plr:SetAttribute("GardenCoin2xUntil", os.time() + REWARD_DURATION) -- coin-award code checks this timestamp
			plr:SetAttribute("GardenCoin2x", true)
			plr:SetAttribute("EarnedCosmetic_" .. seasonName, true)            -- Stage-3 locker reads these entitlements
			if _G.grantSeasonalPet then _G.grantSeasonalPet(plr, seasonName) end -- grant this season's SEASONAL PET (persists + equippable)
			n = n + 1
			print(("[Garden][Reward] %s -> 2x coins for %ds + earned the %s cosmetic"):format(plr.Name, REWARD_DURATION, seasonName))
			task.delay(REWARD_DURATION, function()
				if plr and plr.Parent and (plr:GetAttribute("GardenCoin2xUntil") or 0) <= os.time() then
					plr:SetAttribute("GardenCoin2x", false)
				end
			end)
		end)
	end
	print("[Garden][Reward] rewarded " .. n .. " player(s) online")
end

-- forward-declared so onProgressChanged (below) and the chat command can call it; assigned just below.
local harvestAndAdvance
harvestAndAdvance = function(reason)
	if harvesting then return end -- guard: harvest fires only ONCE per fill (set immediately, so the bloom hold can't re-trigger)
	harvesting = true

	-- BLOOM HOLD: the FULL bloom (stage 5, current season's colours) is already built + visible (renderStage(5) ran
	-- before this). Sparkle-celebrate it and HOLD it on screen so players actually SEE the full bloom before we reset.
	-- Crucially this also means the reset rebuild starts only AFTER the stage-5 sunflower union has long finished --
	-- so the reset no longer destroys an in-flight build (no more "discarded -- superseded rebuild"). Skipped for a
	-- timed-out empty season (nothing to show) and for /forceharvest (instant test trigger).
	pcall(celebrate)
	if reason == "full" then task.wait(BLOOM_HOLD_SECONDS) end
	if not harvesting then return end -- (defensive) a rebuild/clear during the hold cancelled us

	harvestCount = harvestCount + 1
	local sName = SEASONS[gardenSeasonIndex].name
	print(("[Garden][Harvest] season %d (%s) harvested at %d (%s)"):format(harvestCount, sName, getProgress(), reason or "full"))
	rewardEveryone(sName)
	pcall(function() GardenWaterEvent:FireAllClients({ kind = "celebrate", text = "\xF0\x9F\x8C\xBB The garden bloomed! Everyone gets 2x coins!" }) end)

	-- advance to the NEXT season, repaint the palette, reset progress, and rebuild visuals (all pcall'd)
	gardenSeasonIndex = (gardenSeasonIndex % #SEASONS) + 1
	local ns = applySeason(gardenSeasonIndex)
	pcall(function() Workspace:SetAttribute("GardenSeason", ns.name) end) -- so signs/UI can show the season if wanted
	seasonStartTime = os.time()
	currentStage = -1                      -- force a fresh stage render at the new colours
	pcall(setProgress, 0)                  -- 0 -> fires onProgressChanged -> updateSign + dial + renderStage(0) in new palette
	print("[Garden] new season: " .. ns.name)
	task.wait(1)                           -- brief settle so the just-passed 100% can't immediately re-trigger
	harvesting = false
end

-- season TIMER: if a season runs ~SEASON_TIMER without filling, harvest/reward/reset on the timer anyway.
task.spawn(function()
	while true do
		task.wait(60)
		if (not harvesting) and (os.time() - seasonStartTime) >= SEASON_TIMER then
			pcall(harvestAndAdvance, "timer")
		end
	end
end)

local function updateSign()
	if not signLabels then return end
	local p, g = getProgress(), GOAL
	local pct = math.clamp(p / g, 0, 1)
	pcall(function()
		signLabels.fill.Size = UDim2.new(pct, 0, 1, 0)
		signLabels.pct.Text = math.floor(pct * 100) .. "% grown"
		signLabels.count.Text = string.format("%d / %d", p, g)
	end)
end

-- progress changed -> refresh the sign always, and rebuild the field only when the stage threshold crosses
onProgressChanged = function()
	updateSign()
	if refreshGrowthDial then pcall(refreshGrowthDial) end -- live growth dial + contributor text (fires on EVERY progress change, not just stage crossings)
	local pct = math.floor(getProgress() / GOAL * 100)
	local s = stageForPct(pct)
	if s ~= currentStage then
		currentStage = s
		pcall(renderStage, s)
		print("[Garden] growth stage -> " .. s .. " at " .. pct .. "%")
		if s >= 5 then print("[Garden] FULLY GROWN"); task.spawn(harvestAndAdvance, "full") end -- STAGE 2 harvest cycle (celebrate runs inside)
	end
end

-- build the field-slot grid + the sign board (once, after markers resolve)
-- ===== STONE HARDSCAPE FOUNDATION (built ONCE, permanent -- NOT in plantsFolder, never cleared on stage change).
-- A tiered stone garden centered on the CommunityGarden marker: raised dais + front steps + two concentric
-- dark-soil ring beds bounded by low stone walls + 6 gold-capped pillars. Cosmetic: Anchored, CanQuery=false,
-- Massless, Plastic, Smooth; dais/steps/walls/pillars CanCollide=true so players can stand on them. Plain parts
-- (no CSG needed -> nothing to fail); whole build pcall'd by the caller. A sign-side gap keeps the path/WaterSpot reachable.
local function buildHardscape()
	if not (gardenTopCF and gardenBuild) then return end
	local C = gardenTopCF
	local hs = Instance.new("Model"); hs.Name = "GardenHardscape"; hs.Parent = gardenBuild -- under the one fresh build container

	local STONE  = Color3.fromRGB(196, 170, 130)  -- warm tan/sandstone (main stone)
	local STONE_B = Color3.fromRGB(178, 150, 110) -- second brick tone (running-bond coursing variation)
	local STONE2 = Color3.fromRGB(168, 142, 104)  -- darker coursing for tier lips + step risers
	local GOLD   = Color3.fromRGB(230, 190, 60)   -- (unchanged) used by the growth dial -- leave it alone
	local GOLDB  = Color3.fromRGB(235, 185, 45)   -- bolder saturated gold for caps / chest / sign accents
	local SOIL   = Color3.fromRGB(45, 32, 24)

	local function hpart(name, shape, size, color, cf, collide)
		local p = newPart(hs, name, shape, size, color, cf)
		p.CanCollide = (collide == true)
		return p
	end
	-- ROTATE THE WHOLE GARDEN 90deg CLOCKWISE (about Y, from above): everything below is built relative to `base`
	-- instead of `C`, so the dais/beds/walls/pillars all turn together as one unit. (-90 = clockwise; flip to +90
	-- if it turns the wrong way.) The entrance is re-aimed to the sign separately below so it still faces the path.
	local base = C * CFrame.Angles(0, math.rad(-90), 0)

	-- a vertical stone "drum": a Cylinder rotated so its round face points up. bottom at ground + yb, height h.
	local function drum(name, dia, h, yb, color, collide)
		return hpart(name, CYL, Vector3.new(h, dia, dia), color, base * CFrame.new(0, yb + h * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), collide)
	end

	-- ENTRANCE DIRECTION (computed up-front so the staircase + the wall/brick doorway gap all share it): measured in
	-- the ORIGINAL (unrotated) frame `C`, then placed through the ROTATED `base` so the doorway turns WITH the garden.
	local worldSignDir = signPos and Vector3.new(signPos.X - C.Position.X, 0, signPos.Z - C.Position.Z) or Vector3.new(0, 0, -1)
	if worldSignDir.Magnitude < 0.05 then worldSignDir = Vector3.new(0, 0, -1) end
	worldSignDir = worldSignDir.Unit
	local localSignDir = C:VectorToObjectSpace(worldSignDir)
	local openAngle = math.atan2(localSignDir.Z, localSignDir.X)  -- layout-local entrance angle; turns with `base`
	local openHalf = 0.32                                         -- half-width of the doorway (radians)

	-- BRICK COURSING: a skin of small individual "brick" blocks around a circular face, in stacked rows with a
	-- running-bond half-brick offset + two stone tones so each brick reads. Bricks are decorative (CanCollide=false
	-- via newPart) and named "Brick" so the final stone-recolor pass leaves their two-tone alone. Returns the count.
	local brickCount = 0
	local function brickRing(model, radius, yBottom, rows, rowH, skipDoor)
		local bw = 2.4 -- brick width (tangent)
		local n = math.max(8, math.floor((2 * math.pi * radius) / bw))
		local ang = 2 * math.pi / n
		for r = 0, rows - 1 do
			local y = yBottom + rowH * (r + 0.5)
			local off = (r % 2 == 0) and 0 or (ang * 0.5) -- running bond: alternate rows shift half a brick
			for i = 0, n - 1 do
				local a = i * ang + off
				local skip = false
				if skipDoor then
					local da = math.abs(((a - openAngle + math.pi) % (2 * math.pi)) - math.pi)
					if da <= (openHalf + 0.04) then skip = true end -- leave the doorway open
				end
				if not skip then
					local col = ((i + r) % 2 == 0) and STONE or STONE_B
					local cf = base * CFrame.new(math.cos(a) * radius, y, math.sin(a) * radius) * CFrame.Angles(0, -a, 0)
					newPart(model, "Brick", BLK, Vector3.new(0.5, rowH * 0.86, bw * 0.9), col, cf) -- X=radial(proud), Y=height, Z=tangent(width)
					brickCount = brickCount + 1
				end
			end
		end
	end

	-- 1) CENTRAL DAIS: THREE stacked round stone tiers (wedding-cake), decreasing diameter, each ~2.5 tall, each
	-- skinned with 3 rows of running-bond brick coursing + a darker overhanging coursing lip. The sunflower plants
	-- in the dark soil bed on the TOP tier (+7.5).
	local TH = 2.5
	for _, t in ipairs({ { dia = 30, yb = 0.0 }, { dia = 22, yb = 2.5 }, { dia = 18, yb = 5.0 } }) do -- top tier widened to r9: room to walk around the planter + flush with the stair top (r9)
		drum("DaisTier", t.dia, TH, t.yb, STONE, true)                    -- walkable stone tier
		brickRing(hs, t.dia * 0.5 + 0.2, t.yb, 3, TH / 3, false)          -- brick skin on the tier's vertical face
		drum("DaisLip", t.dia + 1.0, 0.5, t.yb + TH - 0.5, STONE2, true)  -- darker overhanging coursing lip at the tier top
	end
	-- GRAND CENTER PLANTER on the top tier: the dark-soil bed framed by a low brick-coursed STONE RING WALL (with a
	-- darker coursing cap + small gold finials), soil recessed inside the rim, so the sunflower rises from a raised
	-- planter -- not a bare disc. (The lush tufts/mini-flowers around the stem come from the planting pass.)
	drum("CenterBed", 8, 0.4, 7.5, SOIL, true)                           -- ø8 dark soil, recessed inside the ring (sunflower base +7.5)
	do
		local cT, rRing, ringH, segs = 7.5, 4.6, 1.8, 18
		local segLen = (2 * rRing * math.sin(math.pi / segs)) * 1.12     -- overlap so the rim has no gaps
		for i = 0, segs - 1 do
			local a = i * (2 * math.pi / segs)
			local cf = base * CFrame.new(math.cos(a) * rRing, cT + ringH * 0.5, math.sin(a) * rRing) * CFrame.Angles(0, -a, 0)
			hpart("CenterRing", BLK, Vector3.new(0.7, ringH, segLen), STONE, cf, true)                                       -- stone ring-wall segment
			hpart("CenterRingCap", BLK, Vector3.new(0.95, 0.3, segLen + 0.05), STONE2, cf * CFrame.new(0, ringH * 0.5, 0), true) -- darker coursing cap
		end
		brickRing(hs, rRing + 0.42, cT + 0.15, 2, (ringH - 0.3) / 2, false) -- brick coursing skin on the rim face (two-tone, offset)
		-- small GOLD finials on the rim (4 points) tying the centerpiece to the dais gold
		local function cgold(name, size, cf) local p = hpart(name, BLK, size, GOLDB, cf, false); p.Material = Enum.Material.SmoothPlastic; p.Reflectance = 0.25; return p end
		for k = 0, 3 do
			local a = math.rad(45) + k * (math.pi / 2)
			local gcf = base * CFrame.new(math.cos(a) * rRing, cT + ringH, math.sin(a) * rRing)
			cgold("CenterGold", Vector3.new(0.8, 0.45, 0.8), gcf * CFrame.new(0, 0.22, 0) * CFrame.Angles(0, math.rad(45), 0)) -- small faceted gold cap
			cgold("CenterGold", Vector3.new(0.45, 0.45, 0.45), gcf * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, math.rad(45), 0))
		end
		-- a few small stones nestled in the soil around the stem base (stem stays clear at r < 1.4)
		local prng = Random.new(515)
		for _ = 1, 6 do
			local a, rr, s = prng:NextNumber(0, 2 * math.pi), prng:NextNumber(1.5, 3.1), prng:NextNumber(0.5, 0.9)
			hpart("CenterStone", BAL, Vector3.new(s, s, s), (prng:NextNumber() < 0.5) and STONE or STONE2,
				base * CFrame.new(math.cos(a) * rr, cT + 0.5, math.sin(a) * rr), false)
		end
	end
	print("[Garden][Struct] center done")

	-- TOP-TIER RING PATH: the widened tier3 top (the solid stone disc out to r9 at +7.5) IS the continuous walkable tan
	-- ring around the centre planter, flush with the stair top. Add a subtle paved tile overlay + a low outer CURB
	-- (with a front gap where the stairs arrive) so players circle the sunflower without falling off the tier edge.
	do
		local tT, rInner, rOuter, pn = 7.5, 5.0, 9.0, 24
		local rMid = (rInner + rOuter) * 0.5
		local segLen = (2 * math.pi * rOuter / pn) * 1.10 -- sized to the OUTER radius -> overlaps on the curve (no gaps)
		for i = 0, pn - 1 do
			local a = i * (2 * math.pi / pn)
			local cf = base * CFrame.new(math.cos(a) * rMid, tT, math.sin(a) * rMid) * CFrame.Angles(0, -a, 0)
			hpart("TopRingTile", BLK, Vector3.new(rOuter - rInner, 0.14, segLen), (i % 2 == 0) and STONE or STONE2, cf * CFrame.new(0, 0.08, 0), false) -- paved overlay (tier top is the floor)
			local da = math.abs(((a - openAngle + math.pi) % (2 * math.pi)) - math.pi)
			if da > 0.5 then -- low outer CURB at the tier edge; FRONT gap so the stairs connect flush onto the ring
				local ccf = base * CFrame.new(math.cos(a) * rOuter, tT + 0.6, math.sin(a) * rOuter) * CFrame.Angles(0, -a, 0)
				hpart("TopCurb", BLK, Vector3.new(0.6, 1.2, segLen), STONE, ccf, true)
				hpart("TopCurbCap", BLK, Vector3.new(0.85, 0.3, segLen + 0.05), STONE2, ccf * CFrame.new(0, 0.6, 0), true)
			end
		end
	end
	print("[Garden][Struct] top-tier ring path + curb done")

	-- 2) GRANDER STAIRCASE: 6 WIDE flat stone slabs climbing from the ground to the top tier, FRAMED by low stone cheek
	-- walls each side, with BRICK COURSING on each riser to match the dais stonework. Aligned to the doorway (openAngle).
	local nSteps, stairHW = 6, 7 -- stairHW = half-width -> 14 wide
	for i = 1, nSteps do
		local top = (7.5 / nSteps) * i           -- tread heights 1.25 .. 7.5
		local r = 22 - (i - 1) * 2.6             -- climbs inward as it rises
		local cf = base * CFrame.new(math.cos(openAngle) * r, top * 0.5, math.sin(openAngle) * r) * CFrame.Angles(0, -openAngle, 0)
		hpart("Step", BLK, Vector3.new(3.4, top, stairHW * 2), STONE, cf, true)                                  -- solid wide step; X=radial depth, Z=tangent width
		hpart("StepLip", BLK, Vector3.new(1.3, 0.4, stairHW * 2 + 0.4), STONE2, cf * CFrame.new(1.8, top * 0.5, 0), true) -- overhanging tread lip
		local nb = math.floor((stairHW * 2) / 2.2)                                                              -- BRICK COURSING across the riser (two-tone)
		for b = 0, nb - 1 do
			hpart("StepBrick", BLK, Vector3.new(0.45, 1.0, 1.95), (b % 2 == 0) and STONE or STONE_B, cf * CFrame.new(1.75, top * 0.5 - 0.6, -stairHW + 1.1 + b * 2.2), false)
		end
		for _, side in ipairs({ -1, 1 }) do      -- low CHEEK WALLS framing each side of the steps (with a darker cap)
			local cw = top + 1.4
			hpart("CheekWall", BLK, Vector3.new(3.6, cw, 1.0), STONE, cf * CFrame.new(0, cw * 0.5 - top * 0.5, side * (stairHW + 0.5)), true)
			hpart("CheekCap",  BLK, Vector3.new(3.8, 0.4, 1.3), STONE2, cf * CFrame.new(0, cw - top * 0.5, side * (stairHW + 0.5)), true)
		end
	end
	print("[Garden][Struct] grander staircase (widened + cheek walls + riser brick coursing) done")

	-- a finished STONE COLUMN (shared by ring + gate pillars so their caps MATCH): stepped base plinth -> banded
	-- shaft -> flared capital -> a crisp faceted GOLD pyramid on a collar. w=shaft width, h=shaft height, capW=cap base.
	local function buildColumn(ccf, w, h, capW)
		hpart("PillarBase", BLK, Vector3.new(w + 1.6, 0.7, w + 1.6), STONE, ccf * CFrame.new(0, 0.35, 0), true)  -- widest footing
		hpart("PillarBase", BLK, Vector3.new(w + 0.8, 0.6, w + 0.8), STONE2, ccf * CFrame.new(0, 1.0, 0), true)  -- darker base step
		local sBot = 1.3
		local sTop = sBot + h
		-- 2) SHAFT: ONE smooth box column built as a vertical STACK of full-width (w) sections -- all flush at w/2 (a
		-- single smooth surface, NO protruding bricks). Two of the sections are thin DARKER band rings for subtle detail.
		local bh = 0.4                                   -- band thickness
		local by1, by2 = sBot + h * 0.3, sBot + h * 0.7  -- band centre heights (2 bands)
		local function seg(name, yLo, yHi, color) -- a full-width smooth section from yLo..yHi (flush column surface)
			if yHi - yLo > 0.02 then hpart(name, BLK, Vector3.new(w, yHi - yLo, w), color, ccf * CFrame.new(0, (yLo + yHi) * 0.5, 0), true) end
		end
		seg("Pillar", sBot, by1 - bh * 0.5, STONE)                 -- lower shaft
		seg("PillarBand", by1 - bh * 0.5, by1 + bh * 0.5, STONE2)  -- flush darker band 1
		seg("Pillar", by1 + bh * 0.5, by2 - bh * 0.5, STONE)       -- middle shaft
		seg("PillarBand", by2 - bh * 0.5, by2 + bh * 0.5, STONE2)  -- flush darker band 2
		seg("Pillar", by2 + bh * 0.5, sTop, STONE)                 -- upper shaft
		hpart("PillarCapital", BLK, Vector3.new(w + 1.1, 0.8, w + 1.1), STONE, ccf * CFrame.new(0, sTop + 0.4, 0), true)    -- flared CAPITAL
		hpart("PillarCapital", BLK, Vector3.new(w + 1.6, 0.35, w + 1.6), STONE2, ccf * CFrame.new(0, sTop + 0.95, 0), true) -- darker abacus
		-- 4) GOLD CAP: a small gold collar + a CRISP faceted gold DIAMOND -- sharp 45deg-rotated facets, a wide girdle
		-- tapering to a clean point (sharp boxes, never blobby). Bright + glossy so it clearly crowns the column.
		local g = ccf * CFrame.new(0, sTop + 1.15, 0)
		local function gold(name, shape, size, cf) local p = hpart(name, shape, size, GOLDB, cf, false); p.Material = Enum.Material.SmoothPlastic; p.Reflectance = 0.3; return p end
		gold("GoldCollar", CYL, Vector3.new(0.5, capW + 0.2, capW + 0.2), g * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90))) -- small gold collar
		gold("GoldGem", BLK, Vector3.new(capW * 0.55, 0.4, capW * 0.55), g * CFrame.new(0, 0.65, 0) * CFrame.Angles(0, math.rad(45), 0)) -- bottom facet
		gold("GoldGem", BLK, Vector3.new(capW, 0.5, capW),               g * CFrame.new(0, 1.05, 0) * CFrame.Angles(0, math.rad(45), 0)) -- girdle (widest)
		gold("GoldGem", BLK, Vector3.new(capW * 0.66, 0.6, capW * 0.66), g * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(45), 0))  -- crown
		gold("GoldGem", BLK, Vector3.new(capW * 0.36, 0.6, capW * 0.36), g * CFrame.new(0, 2.15, 0) * CFrame.Angles(0, math.rad(45), 0)) -- upper
		gold("GoldTip", BLK, Vector3.new(capW * 0.14, 0.55, capW * 0.14), g * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.rad(45), 0)) -- sharp point
	end

	-- 2b) GRAND ENTRANCE: border CURBS each side + 2 TALL gate columns frame the doorway. The entrance FLOOR itself is
	-- NOT a separate slab anymore -- it's part of the ONE continuous stone floor below (the CSG ring + bridge, +0.7).
	for _, side in ipairs({ -1, 1 }) do
		for _, rr in ipairs({ 27, 33, 39, 45 }) do  -- raised border curb each side -> frames the gateway + cleans the path
			local ccf = base * CFrame.new(math.cos(openAngle) * rr, 0, math.sin(openAngle) * rr) * CFrame.Angles(0, -openAngle, 0) * CFrame.new(0, 0, side * (stairHW + 0.6))
			hpart("Curb", BLK, Vector3.new(6.6, 0.7, 1.0), STONE, ccf * CFrame.new(0, 0.55, 0), true)
			hpart("CurbCap", BLK, Vector3.new(6.8, 0.25, 1.2), STONE2, ccf * CFrame.new(0, 1.0, 0), true) -- darker cap on the curb
		end
		buildColumn(base * CFrame.new(math.cos(openAngle) * 46, 0, math.sin(openAngle) * 46) * CFrame.Angles(0, -openAngle, 0) * CFrame.new(0, 0, side * (stairHW + 1.5)), 2.8, 7, 3.6) -- TALL gate column
	end
	print("[Garden][Struct] grand entrance (side curbs + 2 tall gate columns; floor is part of the ONE continuous stone surface) done")

	-- 3) RING BEDS (dark soil drums; centre hidden by the dais) + low stone retaining WALLS, each skinned with a
	-- brick coursing band (doorway left open). Walls close completely except the single front doorway at `openAngle`.
	drum("InnerBed", 64, 0.5, 0, SOIL, true)   -- INNER planting bed (dark soil + flowers), out to r32
	-- THE FLOOR: ONE single continuous tan stone surface for the WHOLE walkable area, at ONE height (top +0.7).
	-- Built as a single CSG part = the outer RING (a r46 cylinder with the r32 inner-bed area SUBTRACTED out -> annulus)
	-- UNIONED with the ENTRANCE BRIDGE (a stone strip running from the front doorway across the inner bed to the steps).
	-- Because the bridge and the ring are merged into one operation, they share the same top Y with NO seam/gap, and the
	-- entrance is simply part of the same floor -- not a separate raised slab. Walkable (CanCollide), CanQuery=false.
	task.spawn(function()
		local discCF = base * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)) -- round face UP; 1.0 tall -> top +0.7
		-- entrance bridge: radial r20..47 (overlaps the steps base r22 inward + reaches the gate columns/doorway outward),
		-- tangent width 15 (the cleared corridor), top +0.7 to match the ring exactly.
		local bridgeCF = base * CFrame.new(math.cos(openAngle) * 33.5, 0.2, math.sin(openAngle) * 33.5) * CFrame.Angles(0, -openAngle, 0)
		local ok, floor = pcall(function()
			local outer = Instance.new("Part"); outer.Anchored = true; outer.Shape = Enum.PartType.Cylinder
			outer.Size = Vector3.new(1.0, 92, 92); outer.CFrame = discCF; outer.Color = STONE; outer.Parent = hs   -- r46 disc
			local inner = Instance.new("Part"); inner.Anchored = true; inner.Shape = Enum.PartType.Cylinder
			inner.Size = Vector3.new(3.0, 64, 64); inner.CFrame = discCF; inner.Parent = hs                        -- r32 hole (taller -> fully cuts)
			local ring = outer:SubtractAsync({ inner })                                                            -- annulus r32..46
			outer:Destroy(); inner:Destroy()
			ring.Parent = hs
			local bridge = Instance.new("Part"); bridge.Anchored = true
			bridge.Size = Vector3.new(27, 1.0, 15); bridge.CFrame = bridgeCF; bridge.Color = STONE; bridge.Parent = hs -- entrance bridge strip
			local u = ring:UnionAsync({ bridge })                                                                   -- ring + bridge = ONE floor
			ring:Destroy(); bridge:Destroy()
			return u
		end)
		if ok and floor then
			floor.Name = "OuterPath"; floor.Anchored = true; floor.CanCollide = true; floor.CanQuery = false
			floor.Massless = true; floor.Material = Enum.Material.Plastic; floor.UsePartColor = true; floor.Color = STONE
			floor.Parent = hs
			print("[Garden][Struct] floor -> ONE continuous gap-free stone surface (ring annulus r32..46 + entrance bridge r20..47, +0.7) done")
		else -- fallback: a solid tan disc + a plain bridge box (both flush, gap-free, no green)
			local p = newPart(hs, "OuterPath", CYL, Vector3.new(0.5, 92, 92), STONE, base * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)))
			p.CanCollide = true
			local b = newPart(hs, "OuterPath", BLK, Vector3.new(27, 1.0, 15), STONE, base * CFrame.new(math.cos(openAngle) * 33.5, 0.2, math.sin(openAngle) * 33.5) * CFrame.Angles(0, -openAngle, 0))
			b.CanCollide = true
			print("[Garden][Struct] floor -> disc + bridge fallback (gap-free) done")
		end
	end)
	local function wall(name, r, segs, h, doorHalf)
		local segLen = (2 * r * math.sin(math.pi / segs)) * 1.10 -- 10% overlap so neighbours always butt -> NO gaps between segments
		for i = 0, segs - 1 do
			local a = i * (2 * math.pi / segs)
			local da = math.abs(((a - openAngle + math.pi) % (2 * math.pi)) - math.pi)
			if da > doorHalf then -- snug doorway: wall runs right up to the entrance, no extra gap
				local cf = base * CFrame.new(math.cos(a) * r, h * 0.5, math.sin(a) * r) * CFrame.Angles(0, -a, 0)
				hpart(name, BLK, Vector3.new(0.9, h, segLen), STONE, cf, true)
				hpart(name .. "Cap", BLK, Vector3.new(1.2, 0.3, segLen + 0.1), STONE2, cf * CFrame.new(0, h * 0.5, 0), true) -- clean coursing capstone -> even wall top
			end
		end
	end
	wall("InnerWall", 32, 28, 1.5, 0.26) -- snug to the walkway (~±8.3) -> closes the extra inner-doorway gap
	wall("OuterWall", 46, 40, 1.5, 0.32) -- outer doorway; the jambs below bridge it into the gate columns
	-- JAMBS: short stone wall pieces bridging each entrance GATE COLUMN cleanly into the outer ring wall (no gateway gap)
	for _, side in ipairs({ -1, 1 }) do
		local jcf = base * CFrame.new(math.cos(openAngle) * 46, 0.75, math.sin(openAngle) * 46) * CFrame.Angles(0, -openAngle, 0) * CFrame.new(0, 0, side * 11.5)
		hpart("WallJamb", BLK, Vector3.new(0.9, 1.5, 7.4), STONE, jcf, true)                                  -- tangent ~7.8..15.2: overlaps the gate column AND the ring wall
		hpart("WallJambCap", BLK, Vector3.new(1.2, 0.3, 7.5), STONE2, jcf * CFrame.new(0, 0.9, 0), true)
	end
	brickRing(hs, 32 + 0.55, 0.35, 1, 0.8, true) -- brick course band on the inner wall face (doorway open)
	brickRing(hs, 46 + 0.55, 0.35, 1, 0.8, true) -- brick course band on the outer wall face (doorway open)
	print("[Garden][Struct] ring walls closed (10% overlap, snug doorways, gate-column jambs) done")

	-- [SEAMBRIDGE2] GUARANTEE the filler overlaps both bordering walls (no crack). For each gap: the two NEAREST
	-- distinct ring-wall parts; each wall's END FACE nearest the gap (centre +/- half its LENGTH along its run axis);
	-- then a filler spanning face-to-face PLUS 1 stud INTO each wall (length = gap distance + 2). If the two already
	-- touch (gap < 0.5), just cover the joint with a 3-stud segment. Height/thickness/colour/material/coursing copied
	-- from the walls; centred on the midpoint; bottom on floor; Anchored; in hs; named SEAMFILL_1..4.
	do
		local floorY = base.Position.Y -- same floor the walls rest on (~240.8)
		local seamCoords = {
			Vector3.new(-53.69, 244.00,   6.40),
			Vector3.new(-67.42, 244.85,   0.86),
			Vector3.new(-67.42, 244.85, -17.27),
			Vector3.new(-53.70, 243.99, -23.57),
		}
		-- per-gap nudge (studs, world axes), added to the final bridge centre. ONLY gaps 3 & 4 (near the planters)
		-- need it -- pushed toward the wall line; gaps 1 & 2 (near the dial) are correct and stay at zero.
		local SEAM_NUDGE = {
			[1] = Vector3.new(0, 0, 0),
			[2] = Vector3.new(0, 0, 0),
			[3] = Vector3.new(-1.5, 0, 0),
			[4] = Vector3.new(-1.5, 0, 0),
		}
		local walls, capColor, wallThick, wallH = {}, STONE2, 0.9, 1.5
		for _, p in ipairs(hs:GetChildren()) do
			if p:IsA("BasePart") then
				if p.Name == "OuterWall" or p.Name == "InnerWall" then
					walls[#walls + 1] = p
					wallThick = math.min(p.Size.X, p.Size.Z); wallH = p.Size.Y
				elseif p.Name == "OuterWallCap" or p.Name == "InnerWallCap" then capColor = p.Color end
			end
		end
		-- world RUN direction (the longer horizontal axis) + its length, for a wall part
		local function runOf(W)
			if W.Size.Z >= W.Size.X then return W.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1)), W.Size.Z
			else return W.CFrame.RightVector, W.Size.X end
		end
		-- the END FACE of W (centre +/- half its LENGTH along its run axis) nearest point p
		local function nearEndFace(W, p)
			local dir, len = runOf(W)
			local e1 = W.Position + dir * (len * 0.5)
			local e2 = W.Position - dir * (len * 0.5)
			return ((e1 - p).Magnitude <= (e2 - p).Magnitude) and e1 or e2
		end
		for i, c in ipairs(seamCoords) do
			if i > 2 then continue end -- ONLY build fillers for gaps 1 & 2 (near the dial); gaps 3 & 4 are removed
			-- the two NEAREST DISTINCT wall parts bordering this gap
			local wA, dA, wB, dB
			for _, w in ipairs(walls) do
				local dist = (w.Position - c).Magnitude
				if not dA or dist < dA then wB, dB = wA, dA; wA, dA = w, dist
				elseif not dB or dist < dB then wB, dB = w, dist end
			end
			if wA and wB then
				-- each wall's END FACE nearest the gap, then bridge face-to-face + 1 stud INTO each wall
				local faceA = nearEndFace(wA, c)
				local faceB = nearEndFace(wB, c)
				local delta = faceB - faceA; delta = Vector3.new(delta.X, 0, delta.Z) -- horizontal line faceA -> faceB
				local gapDist = delta.Magnitude
				local u, length
				if gapDist < 0.5 then                  -- walls already touch -> just cover the joint
					local rd = runOf(wA); rd = Vector3.new(rd.X, 0, rd.Z)
					u = (rd.Magnitude > 0.01) and rd.Unit or Vector3.new(1, 0, 0)
					length = 3
				else
					u = delta.Unit
					length = gapDist + 2               -- 1 stud overlap INTO each wall -> guaranteed no crack
				end
				local mid = (faceA + faceB) * 0.5
				local nudge = SEAM_NUDGE[i] or Vector3.new(0, 0, 0)
				local center = Vector3.new(mid.X, floorY + wallH * 0.5, mid.Z) + nudge -- bottom on floor + per-gap nudge (only 3 & 4)
				local cf = CFrame.lookAt(center, center + u, Vector3.new(0, 1, 0)) -- length runs along local Z (= u)
				local size = Vector3.new(wallThick, wallH, length)
				local f = hpart("SEAMFILL_" .. i, BLK, size, wA.Color, cf, true)
				f.Material = wA.Material
				-- matching darker capstone (like the wall caps)
				hpart("SEAMFILL_" .. i .. "Cap", BLK, Vector3.new(wallThick + 0.3, 0.3, length + 0.1), capColor, cf * CFrame.new(0, wallH * 0.5 + 0.15, 0), true)
				-- two-tone brick coursing on BOTH long faces (+/- X), along the length (Z)
				local bn = math.max(2, math.floor(length / 2.6))
				for _, sgn in ipairs({ 1, -1 }) do
					for b = 0, bn - 1 do
						local bcol = (b % 2 == 0) and STONE or STONE_B
						hpart("SEAMFILL_" .. i .. "Brick", BLK, Vector3.new(0.2, wallH * 0.62, length / bn - 0.12), bcol,
							cf * CFrame.new(sgn * (wallThick * 0.5), 0, -length * 0.5 + (b + 0.5) * (length / bn)), false)
					end
				end
				print(string.format("[SEAMBRIDGE2] gap %d: wallA %s face=%s, wallB %s face=%s, gap distance=%.2f, filler center=%s length=%.2f",
					i, wA.Name, tostring(faceA), wB.Name, tostring(faceB), gapDist, tostring(f.Position), length))
				print(string.format("[SEAMBRIDGE3] gap %d final center=%s (nudge applied=%s)", i, tostring(f.Position), tostring(nudge)))
			else
				print(string.format("[SEAMBRIDGE2] gap %d: could not find two distinct walls", i))
			end
		end
		print("[SEAMBRIDGE2] done")
	end

	-- 4) RING PILLARS on the inner wall (r32): up to 6 finished stone COLUMNS (base/shaft/capital/matching gold cap),
	-- at fixed base-local angles; any that would land in the doorway is skipped so the entrance stays clear.
	for i = 0, 5 do
		local a = math.rad(30) + i * (2 * math.pi / 6)
		local da = math.abs(((a - openAngle + math.pi) % (2 * math.pi)) - math.pi)
		if da > (openHalf + 0.28) then -- keep the doorway clear of columns
			buildColumn(base * CFrame.new(math.cos(a) * 32, 0, math.sin(a) * 32), 2, 4, 3.0) -- same column design as the gates (smaller)
		end
	end
	print("[Garden][Struct] pillars done")

	-- ===== SIGNAGE & PROPS ============================================================================
	-- Every piece below is placed via `base * offsetCFrame` (the SAME rotated origin as the dais/walls/pillars),
	-- parented under the CommunityGardenBuild container so it clears on rebuild and TURNS with the garden. Cosmetic
	-- (Anchored/CanQuery=false/Massless/Plastic/Smooth via newPart); each prop pcall'd (failure leaves loose parts
	-- + a warn, never crashes the rest) and logged "[Garden][Prop] ...".
	local WOOD  = Color3.fromRGB(120, 78, 40)   -- richer wood (signs/posts/fence/planter/chest)
	local WOOD2 = Color3.fromRGB(92, 58, 30)    -- darker frame/trim wood
	local DARKB = Color3.fromRGB(40, 30, 22)
	local GLOW  = Color3.fromRGB(255, 220, 120)
	local IRON   = Color3.fromRGB(60, 50, 42)    -- dark iron lantern post
	local LGLOW  = Color3.fromRGB(255, 225, 150) -- warm lantern glow (Neon)
	local LLIGHT = Color3.fromRGB(255, 200, 120) -- warm PointLight tint
	local WHITETXT = Color3.fromRGB(240, 240, 235)  -- sub-text
	local GREENP   = Color3.fromRGB(120, 200, 70)   -- progress green
	local props = Instance.new("Model"); props.Name = "GardenProps"; props.Parent = gardenBuild
	local function prop(name, shape, size, color, cf, parent) -- cosmetic part (CanCollide=false via newPart)
		return newPart(parent or props, name, shape, size, color, cf)
	end
	local function tryProp(label, fn)
		local ok, err = pcall(fn)
		if ok then print("[Garden][Prop] " .. label .. " built")
		else warn("[Garden][Prop] " .. label .. " FAILED -- " .. tostring(err)) end
	end

	-- ===== DECORATIVE GARDEN GNOMES -- CLONES of the finished "Gnome" model in Workspace (the old part-built gnomes
	-- are retired). We reuse the SAME spots + yaws the old buildGnome loop used (the first 4), CLONE the template into
	-- each, ground each clone so its BOTTOM rests at the old gnome's base Y (the model height differs from the old
	-- part build), anchor all its parts, and parent it into `props` so it moves/clears with the rigid garden group.
	-- The source template is then stashed in ServerStorage so exactly 4 clones are visible. (The old part-building
	-- buildGnome body + its build log are removed -- only the spot data below is kept.)
	do
		-- 1) the OLD spots (same ang/r/yaw the part-built gnomes used) -> world transforms. Take the FIRST 4.
		local gnomeSpecs = {
			{ ang = openAngle + 0.95,    r = 30, yaw = -0.6 }, -- flanking the entrance (one side)
			{ ang = openAngle - 0.95,    r = 30, yaw =  0.8 }, -- flanking the entrance (other side)
			{ ang = openAngle + 2.10,    r = 28, yaw =  2.2 }, -- among the beds, near a lamp
			{ ang = openAngle - 2.10,    r = 26, yaw = -1.5 }, -- tucked among the ring beds
			{ ang = openAngle + math.pi, r = 29, yaw =  3.0 }, -- back of the bed (unused -- only 4 gnomes)
		}
		local spots = {}
		for i = 1, math.min(4, #gnomeSpecs) do
			local s = gnomeSpecs[i]
			local pos = (base * CFrame.new(math.cos(s.ang) * s.r, 0.6, math.sin(s.ang) * s.r)).Position -- same XZ + the old base Y (feet rested here)
			spots[#spots + 1] = { pos = pos, yaw = s.yaw }
		end

		-- 2/3) clone the finished template into each saved spot
		local ServerStorage = game:GetService("ServerStorage")
		local template = Workspace:FindFirstChild("Gnome", true) or ServerStorage:FindFirstChild("Gnome", true) -- (after the first build it lives in ServerStorage)
		if not template then
			print("[GARDENGNOMES] template 'Gnome' not found in Workspace")
		else
			-- 1) CLEAN the template (ONCE, before cloning): a stray foreign Union sits ~2.25 studs off to the side +
			-- below the feet -- it shows as the "white thing" AND inflates the bounding box (breaking grounding). Every
			-- REAL gnome part is < ~1.0 stud horizontally from the pivot, so remove any BasePart with horiz > 1.4.
			-- SAFETY: if MORE than 2 parts match, remove NOTHING (so we can re-check the threshold first).
			do
				local pivot = template:GetPivot().Position
				local matches = {}
				for _, d in ipairs(template:GetDescendants()) do
					if d:IsA("BasePart") then
						local rel = d.Position - pivot
						local horiz = Vector2.new(rel.X, rel.Z).Magnitude
						if horiz > 1.4 then matches[#matches + 1] = { part = d, horiz = horiz, relY = rel.Y } end
					end
				end
				if #matches > 2 then
					print("[GNOMECLEAN] WARNING: filter matched " .. #matches .. " parts, skipping removal")
				else
					for _, m in ipairs(matches) do
						print(string.format("[GNOMECLEAN] removed stray name=%s horiz=%.2f relY=%.2f", m.part.Name, m.horiz, m.relY))
						m.part:Destroy()
					end
					local remain = 0
					for _, d in ipairs(template:GetDescendants()) do if d:IsA("BasePart") then remain = remain + 1 end end
					print("[GNOMECLEAN] cleaned template, removed " .. #matches .. ", " .. remain .. " parts remain")
				end
			end

			-- PRESERVE the template's EXACT original rotation. Its PARTS already stand upright in Workspace; only the model
			-- pivot is cocked -- so we DON'T re-orient at all. Capture rotation-only here and clones are merely TRANSLATED
			-- to their spots with this same rotation. (No leveling, no yaw applied.)
			local originalCF = template:GetPivot()
			local rotationOnly = originalCF - originalCF.Position -- the upright-in-Workspace orientation

			local placed = 0
			for i, sp in ipairs(spots) do
				local ok, err = pcall(function()
					local clone = template:Clone()
					-- TRANSLATE ONLY: keep the template's exact (upright) rotation, just move it to the spot. No yaw/pitch/roll
					-- applied -> the clone stands exactly as the template does in Workspace.
					clone:PivotTo(CFrame.new(sp.pos) * rotationOnly)
					-- GROUND it (vertical-only -> cannot reintroduce tilt): align the model's BOTTOM to the old base/soil Y
					local cf, size = clone:GetBoundingBox()
					local bottomY = cf.Position.Y - size.Y / 2
					clone:PivotTo(clone:GetPivot() + Vector3.new(0, sp.pos.Y - bottomY, 0))
					for _, d in ipairs(clone:GetDescendants()) do
						if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end -- anchored (+ non-colliding so it stays fly-through cosmetic)
					end
					clone.Name = "GardenGnome"
					clone.Parent = props -- same container as the other props -> moves with GARDEN_SHIFT + clears on rebuild
					local p = clone:GetPivot().Position
					print(string.format("[GARDENGNOMES] gnome %d upright (preserved rotation) at (%.1f, %.1f, %.1f)", i, p.X, p.Y, p.Z))
					placed = placed + 1
					-- ONE-TIME PART INVENTORY for gnome #1 only -- dump every BasePart so we can spot the stray white part
					-- (a large light-coloured, low-transparency part offset from the body) before deciding to remove it.
					if i == 1 then
						local pivot = clone:GetPivot().Position
						local n = 0
						for _, d in ipairs(clone:GetDescendants()) do
							if d:IsA("BasePart") then
								n = n + 1
								print(string.format("[GNOMEPARTS] name=%s class=%s size=%s relPos=%s color=%s transparency=%.2f",
									d.Name, d.ClassName, tostring(d.Size), tostring(d.Position - pivot), tostring(d.Color), d.Transparency))
							end
						end
						local _, bbSize = clone:GetBoundingBox()
						print("[GNOMEPARTS] bbox size=" .. tostring(bbSize))
						print("[GNOMEPARTS] total parts=" .. n)
					end
				end)
				if not ok then warn("[GARDENGNOMES] clone " .. i .. " FAILED -- " .. tostring(err)) end
			end
			-- 4) stash the source template in ServerStorage so ONLY the clones are visible
			pcall(function() template.Parent = ServerStorage end)
			-- 5) summary
			print("[GARDENGNOMES] placed " .. placed .. " cleaned gnomes, grounded")
		end
	end

	-- 1) WOODEN SIGN BOARDS: 4 framed dark boards on posts OUTSIDE the outer ring. Each board is oriented with
	-- CFrame.lookAt so its FRONT (-Z) face -- which holds the SurfaceGui -- aims squarely at the garden CENTER, so
	-- ALL 4 read inward toward the dais (fixes the front two that used to face outward).
	local function boardGui(board, heading, sub, subColor, subBig)
		local sg = Instance.new("SurfaceGui"); sg.Name = "SignUI"; sg.Face = Enum.NormalId.Front -- -Z faces the center
		sg.CanvasSize = Vector2.new(500, 300); sg.Parent = board
		local function L(txt, y, sy, color, font)
			local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1
			l.Size = UDim2.new(1, -24, sy, 0); l.Position = UDim2.new(0, 12, y, 0)
			l.Font = font; l.TextScaled = true; l.TextWrapped = true; l.Text = txt; l.TextColor3 = color
			l.TextXAlignment = Enum.TextXAlignment.Center; l.Parent = sg
			local s = Instance.new("UIStroke", l); s.Thickness = 2; s.Color = Color3.fromRGB(20, 14, 8)
			return l
		end
		L(heading, 0.10, 0.34, GOLD, Enum.Font.FredokaOne)
		return L(sub, subBig and 0.46 or 0.54, subBig and 0.40 or 0.32, subColor or WHITETXT, subBig and Enum.Font.FredokaOne or Enum.Font.GothamBold)
	end
	-- `faceOut`=true -> the board's text (SurfaceGui Front, -Z) faces AWAY from center (toward the path/arriving
	-- player) so it reads while walking UP the path; otherwise it faces the dais center. Robust by construction:
	-- the WHOLE sign is built off `f`, whose LookVector IS the wanted text direction, so it can't end up backwards.
	local function buildSign(name, a, heading, sub, subColor, subBig, faceOut)
		local m = Instance.new("Model"); m.Name = name; m.Parent = props
		local gy = base.Position.Y -- garden GROUND height
		local pos = (base * CFrame.new(math.cos(a) * 54, 0, math.sin(a) * 54)).Position -- OUTSIDE the outer wall (r46), on the grass
		local ctr = base.Position
		-- TARGET the TEXT face aims at: back signs -> the dais center. FRONT signs -> a point UP the path (well OUTWARD
		-- along the doorway, where the approaching player is). Signs sit at r54,+/-45deg (~38 up-path, ~38 to the side);
		-- aiming at the INWARD entrance made their text face sideways/tangent -> edge-on. Aiming UP-path turns each ~36deg
		-- inward off the side into a shallow welcome-gate V facing the player. Text is on the board Front(-Z)=LookVector.
		local target = faceOut and (base * CFrame.new(math.cos(openAngle) * 68, gy, math.sin(openAngle) * 68)).Position
			or Vector3.new(ctr.X, gy, ctr.Z)
		local want = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
		if want.Magnitude < 0.01 then want = Vector3.new(0, 0, -1) end
		want = want.Unit
		local f = CFrame.lookAt(Vector3.new(pos.X, gy, pos.Z), Vector3.new(pos.X, gy, pos.Z) + want) -- Front(-Z)=LookVector=text face=`want`
		if want:Dot(f.LookVector) < 0 then f = f * CFrame.Angles(0, math.pi, 0) end -- ROBUSTNESS: ensure the TEXT side (not the back) ends up facing the target
		prop("Post",  BLK, Vector3.new(0.8, 3, 0.8), WOOD2, f * CFrame.new(-4.6, 1.5, 0.2), m)  -- posts on the grass (0..3)
		prop("Post",  BLK, Vector3.new(0.8, 3, 0.8), WOOD2, f * CFrame.new( 4.6, 1.5, 0.2), m)
		prop("Frame", BLK, Vector3.new(13, 8, 0.5), WOOD,  f * CFrame.new(0, 6.5, 0.2), m)          -- frame BEHIND the text side
		local board = prop("Board", BLK, Vector3.new(12, 7, 0.4), DARKB, f * CFrame.new(0, 6.5, 0), m) -- 12x7, center +6.5; FRONT (-Z) holds the SurfaceGui
		for _, c in ipairs({ { -5.6, 3.4 }, { 5.6, 3.4 }, { -5.6, 9.6 }, { 5.6, 9.6 } }) do           -- bold gold corner accents
			prop("FrameGold", BLK, Vector3.new(1.4, 1.4, 0.7), GOLDB, f * CFrame.new(c[1], c[2], -0.25), m)
		end
		prop("FrameGoldTop", BLK, Vector3.new(13.2, 0.6, 0.6), GOLDB, f * CFrame.new(0, 10.4, -0.15), m) -- gold top rail (all gold is GOLDB so it matches)
		local subL = boardGui(board, heading, sub, subColor, subBig)
		print(("[Garden][Prop] %s pos=%s target=%s lookVec=%s"):format(name, tostring(pos), tostring(target), tostring(board.CFrame.LookVector))) -- lookVec = the TEXT-face direction; should point from pos toward target
		return m, subL
	end
	tryProp("Sign_TL", function() buildSign("Sign_TL", openAngle + math.rad(45),  "TOGETHER WE GROW", "COMMUNITY GARDEN", nil, nil, true) end) -- FRONT -> faces the path
	tryProp("Sign_TR", function() local _, n = buildSign("Sign_TR", openAngle - math.rad(45), "PLAYERS CONTRIBUTED", tostring(gardenContributors or "\xE2\x80\x94"), GOLD, true, true); contributorLabel = n end) -- FRONT -> faces the path
	tryProp("Sign_BL", function() buildSign("Sign_BL", openAngle + math.rad(135), "GLOBAL COLLABORATION", "BUILT BY PLAYERS FOR EVERYONE", nil, nil, false) end) -- back -> faces center (unchanged)
	tryProp("Sign_BR", function() buildSign("Sign_BR", openAngle - math.rad(135), "SEASON 1", "THANK YOU!", nil, nil, false) end) -- back -> faces center (unchanged)

	-- 2) LANTERNS: real lanterns -- a chunky tapered iron post on a square base + a brass box-cage head (corner bars,
	-- top cap, stepped pointed roof, finial) around a warm Neon glow with a warm PointLight. 6 spots, doorway skipped.
	local function buildLamp(a)
		local m = Instance.new("Model"); m.Name = "LampPost"; m.Parent = props
		local f = base * CFrame.new(math.cos(a) * 44.5, 0.7, math.sin(a) * 44.5) -- OUTER edge of the path, on the walkway (+0.7), against the wall -> path centre stays clear
		-- stepped square iron base
		prop("LampBase", BLK, Vector3.new(1.7, 0.5, 1.7), IRON, f * CFrame.new(0, 0.25, 0), m)
		prop("LampBase", BLK, Vector3.new(1.2, 0.45, 1.2), IRON, f * CFrame.new(0, 0.7, 0), m)
		-- chunky tapered iron post
		prop("LampPostLo", CYL, Vector3.new(3.4, 0.9, 0.9), IRON, f * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)), m)
		prop("LampPostHi", CYL, Vector3.new(1.8, 0.65, 0.65), IRON, f * CFrame.new(0, 5.3, 0) * CFrame.Angles(0, 0, math.rad(90)), m) -- taper
		-- small iron crossbar/bracket where the head meets the post
		prop("LampBracket", BLK, Vector3.new(2.1, 0.25, 0.25), IRON, f * CFrame.new(0, 6.2, 0), m)
		prop("LampBracket", BLK, Vector3.new(0.25, 0.25, 2.1), IRON, f * CFrame.new(0, 6.2, 0), m)
		-- brass lantern HEAD: cage floor + 4 corner bars + warm glow + top frame
		prop("LanternFloor", BLK, Vector3.new(1.9, 0.3, 1.9), GOLDB, f * CFrame.new(0, 6.7, 0), m)
		for _, c in ipairs({ { -0.8, -0.8 }, { 0.8, -0.8 }, { -0.8, 0.8 }, { 0.8, 0.8 } }) do
			prop("LanternBar", BLK, Vector3.new(0.2, 1.8, 0.2), GOLDB, f * CFrame.new(c[1], 7.6, c[2]), m) -- 4 corner cage bars
		end
		local glow = prop("LanternGlow", BLK, Vector3.new(1.25, 1.5, 1.25), LGLOW, f * CFrame.new(0, 7.6, 0), m) -- warm glow inside the cage
		glow.Material = Enum.Material.Neon
		prop("LanternTopFrame", BLK, Vector3.new(2.0, 0.3, 2.0), GOLDB, f * CFrame.new(0, 8.6, 0), m)
		-- small tapered roof + finial
		prop("LanternRoof", BLK, Vector3.new(1.5, 0.4, 1.5), GOLDB, f * CFrame.new(0, 8.95, 0), m)
		prop("LanternRoof", BLK, Vector3.new(0.9, 0.4, 0.9), GOLDB, f * CFrame.new(0, 9.3, 0), m)
		prop("LanternFinial", BLK, Vector3.new(0.25, 0.6, 0.25), GOLDB, f * CFrame.new(0, 9.7, 0), m)
		-- the ONLY lit part: a warm PointLight in the glow
		local light = Instance.new("PointLight"); light.Range = 16; light.Brightness = 1.5; light.Color = LLIGHT; light.Parent = glow
		return m
	end
	local lampCount = 0
	for i = 0, 5 do
		local a = i * (2 * math.pi / 6) -- 0,60,120... -> 30deg off the pillars (which sit at 30,90,150...)
		local da = math.abs(((a - openAngle + math.pi) % (2 * math.pi)) - math.pi)
		if da > (openHalf + 0.30) then -- keep the doorway/path clear of a lamp
			lampCount = lampCount + 1
			tryProp("LampPost@" .. tostring(math.floor(math.deg(a))) .. "deg", function() buildLamp(a) end)
		end
	end
	print("[Garden][Prop] lanterns: " .. lampCount .. " built (" .. lampCount .. " warm PointLights)")

	-- 3) TREASURE CHEST: a detailed gold-trimmed wood chest on a 2-slab stone plinth, out front by the path, facing in.
	-- Dark wood body RGB(90,55,30) + bright gold trim RGB(235,185,45): gold corner straps that wrap the body AND continue
	-- over the rounded lid, a gold horizontal band, gold feet, a domed lid (4 decreasing-width slabs faking a curve) with
	-- gold bands, and a round gold latch (plate + knob) on the front. Position/logic unchanged.
	tryProp("RewardChest", function()
		local m = Instance.new("Model"); m.Name = "RewardChest"; m.Parent = props
		local DWOOD = Color3.fromRGB(90, 55, 30) -- dark chest wood
		local f = base * CFrame.new(math.cos(openAngle) * 50, 0, math.sin(openAngle) * 50) * CFrame.Angles(0, -openAngle, 0) * CFrame.new(0, 0, 7) -- +X depth, Z width; -X faces the path/player
		local function part(name, size, color, cf) return prop(name, BLK, size, color, cf, m) end
		local function gold(name, shape, size, cf) local p = prop(name, shape, size, GOLDB, cf, m); p.Material = Enum.Material.SmoothPlastic; p.Reflectance = 0.25; return p end
		-- STONE PLINTH: 2 stacked tan slabs (raised pedestal)
		part("ChestPlinth", Vector3.new(3.4, 0.6, 4.2), STONE,  f * CFrame.new(0, 0.3, 0))   -- footing (y0..0.6)
		part("ChestPlinth", Vector3.new(2.8, 0.5, 3.6), STONE2, f * CFrame.new(0, 0.85, 0))  -- step (y0.6..1.1)
		-- BODY: dark wood box (y1.1..3.1) with a gold horizontal band, 4 gold corner straps, 4 gold feet
		part("ChestBody", Vector3.new(2.2, 2.0, 3.0), DWOOD, f * CFrame.new(0, 2.1, 0))
		gold("ChestBand", BLK, Vector3.new(2.34, 0.5, 3.14), f * CFrame.new(0, 2.05, 0))
		for _, c in ipairs({ { 1.1, 1.5 }, { 1.1, -1.5 }, { -1.1, 1.5 }, { -1.1, -1.5 } }) do
			gold("ChestStrap", BLK, Vector3.new(0.42, 2.0, 0.42), f * CFrame.new(c[1], 2.1, c[2]))               -- vertical corner strap (body)
			gold("ChestFoot",  BLK, Vector3.new(0.55, 0.55, 0.55), f * CFrame.new(c[1] * 0.82, 1.35, c[2] * 0.86)) -- gold foot
		end
		-- round GOLD LATCH on the front (-X): a backing plate + a round knob, where the lid meets the body
		gold("ChestLatchPlate", BLK, Vector3.new(0.22, 0.9, 0.7), f * CFrame.new(-1.16, 2.75, 0))
		gold("ChestLatch", CYL, Vector3.new(0.45, 0.95, 0.95), f * CFrame.new(-1.22, 3.0, 0)) -- round face (-X) toward the player
		-- DOMED LID: 4 stacked decreasing-WIDTH wood slabs (fakes a curved top) + gold bands over each step
		for _, L in ipairs({ { 2.2, 3.30 }, { 1.8, 3.66 }, { 1.3, 3.98 }, { 0.7, 4.25 } }) do
			part("ChestLid", Vector3.new(L[1], 0.4, 3.0), DWOOD, f * CFrame.new(0, L[2], 0))
			gold("ChestLidBand", BLK, Vector3.new(L[1] + 0.1, 0.44, 0.42), f * CFrame.new(0, L[2],  1.4))
			gold("ChestLidBand", BLK, Vector3.new(L[1] + 0.1, 0.44, 0.42), f * CFrame.new(0, L[2], -1.4))
		end
		-- gold corner straps CONTINUED up over the front/back edges of the dome -> they read as one strap wrapping body+lid
		for _, zc in ipairs({ 1.45, -1.45 }) do
			gold("ChestLidStrap", BLK, Vector3.new(0.42, 1.2, 0.42), f * CFrame.new(0, 3.75, zc))
		end
		return m
	end)
	print("[Garden][Prop] RewardChest (detailed) built")

	-- 3b) GARDENER NPC: the FULL CHARACTER asset 9469438753 (its own body + clothing baked in), loaded via InsertService
	-- and used AS the gardener. If the asset can't load it FALLS BACK to a colour-dressed R15 rig, so he's never missing.
	-- Stands anchored out front facing the path, with the ALWAYS-ON BillboardGui bubble (cycling GARDENER_LINES) + the
	-- hold-E "Talk" prompt + a gentle idle anim; the client turns him toward the nearest player. task.spawn so the
	-- (yielding) asset load never blocks the rest of the props.
	task.spawn(function()
		local V3 = Vector3.new
		-- fallback FARMER colours (used ONLY if the asset fails to load): red plaid shirt, jeans, straw hat, beard, pitchfork
		local SKIN   = Color3.fromRGB(225, 180, 140)
		local SHIRT  = Color3.fromRGB(175, 55, 50)    -- red plaid base (torso + arms)
		local PLAIDD = Color3.fromRGB(120, 35, 32)    -- darker-red plaid bands (bold, few)
		local PLAIDL = Color3.fromRGB(215, 160, 150)  -- pale (wrist cuffs only)
		local DENIM  = Color3.fromRGB(70, 95, 140)    -- jeans (legs)
		local BOOT   = Color3.fromRGB(70, 48, 32)     -- dark brown boots
		local STRAW  = Color3.fromRGB(210, 180, 120)  -- straw hat
		local BANDC  = Color3.fromRGB(150, 120, 70)   -- darker hatband
		local EYEC   = Color3.fromRGB(38, 28, 24)     -- eyes / mouth
		local CHEEK  = Color3.fromRGB(228, 150, 140)  -- soft rosy cheeks
		local BEARD  = Color3.fromRGB(85, 55, 32)     -- brown beard
		local HANDLE = Color3.fromRGB(110, 75, 45)    -- pitchfork handle
		local PRONG  = Color3.fromRGB(180, 180, 185)  -- pitchfork metal prongs
		local SHIRTD = Color3.fromRGB(128, 38, 36)    -- darker red (collar + lower-torso shading)
		local BELT   = Color3.fromRGB(58, 38, 24)     -- leather belt
		local FERRULE= Color3.fromRGB(150, 150, 155)  -- metal belt buckle / fork ferrule
		local SHADE  = Color3.fromRGB(140, 42, 40)    -- shirt side/under shadow (two-tone depth)
		local DENIMI = Color3.fromRGB(55, 75, 115)    -- darker denim on the inner legs (shadow)

		-- PLACE + FREEZE any humanoid model at the gardener spot, facing the path. Anchors only the root (so an idle anim
		-- can still move the limbs); if there's no root it anchors everything so it can never fall. Returns hum, hrp, faceCF.
		local function placeGardener(model)
			local hum = model:FindFirstChildWhichIsA("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart") or (hum and hum.RootPart) or model.PrimaryPart
				or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
			if hrp then model.PrimaryPart = hrp end -- ensure a PrimaryPart so PivotTo + anchoring work
			local gp = (base * CFrame.new(math.cos(openAngle) * 53, 0, math.sin(openAngle) * 53) * CFrame.Angles(0, -openAngle, 0) * CFrame.new(0, 0, -10)).Position
			local gy = base.Position.Y
			local lookP = (base * CFrame.new(math.cos(openAngle) * 64, 0, math.sin(openAngle) * 64)).Position
			local faceCF = CFrame.lookAt(Vector3.new(gp.X, gy, gp.Z), Vector3.new(lookP.X, gy, lookP.Z))
			model:PivotTo(faceCF) -- root faces the path
			local bbCF, bbSize = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + Vector3.new(0, gy - (bbCF.Position.Y - bbSize.Y / 2), 0)) -- feet on the grass
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false; d.Massless = true
					d.Anchored = (hrp == nil) or (d == hrp) -- only the root anchored (or all, if there's no root)
				end
			end
			if hum then
				hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0; hum.AutoRotate = false
				hum.BreakJointsOnDeath = false
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- hide the default name/health bar
				for _, st in ipairs({ Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Jumping }) do
					pcall(function() hum:SetStateEnabled(st, false) end)
				end
			end
			return hum, hrp, faceCF
		end

		-- attach the gardener BEHAVIOUR (idle anim + always-on bubble + hold-E prompt + line cycle) to any humanoid model
		local function attachBehavior(model, hum, hrp, noIdle)
			if hum and not noIdle then -- noIdle: the colored rig poses its arms via Motor6D C0, so a full-body idle would override it
				local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
				local idleId = (hum.RigType == Enum.HumanoidRigType.R6) and "rbxassetid://180435571" or "rbxassetid://507766388"
				local anim = Instance.new("Animation"); anim.AnimationId = idleId
				pcall(function()
					local track = animator:LoadAnimation(anim)
					track.Looped = true; track.Priority = Enum.AnimationPriority.Idle
					track:Play()
				end)
			end
			local head = model:FindFirstChild("Head") or (hrp and hrp) or model.PrimaryPart
			-- sit the bubble just above the model's ACTUAL top (adapts to any model height / hat), not a fixed offset
			local offY = 2.6
			pcall(function()
				local c, s = model:GetBoundingBox()
				if head then offY = (c.Position.Y + s.Y / 2) - head.Position.Y + 1.4 end
			end)
			local bb = Instance.new("BillboardGui")
			bb.Name = "SpeechBubble"; bb.Adornee = head; bb.Parent = head
			-- STYLE MATCHES THE COW'S TalkBubble (EasterEggManager) EXACTLY: white panel @ 0.05, corner 12, stroke
			-- (40,40,46) thk 2, GothamBold size-18 text in (34,34,40), label inset (1,-16,1,-10) @ (0,8,0,5). Only text differs.
			-- PIXEL OFFSET Size + local StudsOffset -> constant on-screen size; MaxDistance 60 still hides it when far (kept).
			bb.Size = UDim2.fromOffset(230, 64); bb.StudsOffset = Vector3.new(0, offY, 0)
			bb.SizeOffset = Vector2.new(0, 0)
			bb.AlwaysOnTop = true; bb.MaxDistance = 20; bb.LightInfluence = 0; bb.Enabled = true; print("[BUBBLE RANGE] gardener MaxDistance=20") -- only visible within 20 studs (Roblox auto-hides the BillboardGui beyond MaxDistance)
			local panel = Instance.new("Frame"); panel.Name = "Panel"; panel.Parent = bb
			panel.Size = UDim2.fromOffset(230, 64); panel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			panel.BackgroundTransparency = 0.05; panel.BorderSizePixel = 0
			Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
			local pstroke = Instance.new("UIStroke", panel); pstroke.Color = Color3.fromRGB(40, 40, 46); pstroke.Thickness = 2
			local lbl = Instance.new("TextLabel"); lbl.Name = "Line"; lbl.Parent = panel
			lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromOffset(214, 54); lbl.Position = UDim2.new(0, 8, 0, 5)
			lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = false; lbl.TextSize = 18; lbl.AutomaticSize = Enum.AutomaticSize.None; lbl.TextColor3 = Color3.fromRGB(34, 34, 40); lbl.TextWrapped = true
			lbl.Text = GARDENER_LINES[1]; print(string.format("[BUBBLE TEXT] gardener TextScaled=false->%s TextSize=%d sizeUsesScale=n", tostring(lbl.TextScaled), lbl.TextSize))
			print("[BUBBLE AUDIT] GardenerSpeechBubble was=offset now=offset"); print(string.format("[BUBBLE DIAG] GardenerSpeechBubble SizeOffset=%s StudsOffsetWorldSpace=%s hasUIScale=%s", tostring(bb.SizeOffset), tostring(bb.StudsOffsetWorldSpace), (bb:FindFirstChildWhichIsA("UIScale", true) or bb:FindFirstChildWhichIsA("UISizeConstraint", true)) and "y" or "n")); print("[BUBBLE SPEAK] gardener method=reuses spawn bubble (cycling loop swaps lbl.Text)") -- Gardener: ONE BillboardGui, text swapped through GARDENER_LINES on a loop
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "GardenerTalkPrompt"; pp.ActionText = "Talk"; pp.ObjectText = "Gardener"
			pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.5; pp.MaxActivationDistance = 12
			pp.RequiresLineOfSight = false; pp.Parent = head
			task.spawn(function()
				local i = 1
				while lbl.Parent do
					lbl.Text = GARDENER_LINES[i]
					i = (i % #GARDENER_LINES) + 1
					task.wait(4)
				end
			end)
		end

		-- FALLBACK ONLY: a colour-dressed R15 rig (recolour the real parts + weld thin code-built accessories). No catalog IDs.
		local function buildColoredGardener()
			local desc = Instance.new("HumanoidDescription")
			desc.HeadColor = SKIN; desc.TorsoColor = SKIN
			desc.LeftArmColor = SKIN; desc.RightArmColor = SKIN
			desc.LeftLegColor = SKIN; desc.RightLegColor = SKIN
			local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			model.Parent = props
			local hum, hrp, faceCF = placeGardener(model)
			local function bodyColor(n)
				if n == "Head" then return SKIN end
				if n:find("Hand") then return SKIN end -- bare farmer hands
				if n:find("Foot") then return BOOT end
				if n:find("Leg") then return DENIM end
				if n:find("Arm") or n:find("Torso") then return SHIRT end
				return nil
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local c = bodyColor(d.Name)
					if c then d.Color = c; d.Material = Enum.Material.Plastic; if d:IsA("MeshPart") then d.TextureID = "" end end
				elseif d:IsA("SurfaceAppearance") then d:Destroy() end
			end
			-- POSE ARMS resting DOWN at the sides. We DO NOT write Motor6D.C0 (it can be read-only on a freshly built rig and
			-- throws "Property is read only", which previously aborted the whole build) -- instead we DROP the arm motors and
			-- rigidly RE-WELD each arm part hanging straight down from the shoulder, so they follow the body and the right
			-- hand holds the fork upright. Wrapped in pcall so a hiccup here can NEVER abort the rest (head/hat/beard/fork).
			pcall(function()
				local torso = model:FindFirstChild("UpperTorso")
				if not torso then return end
				local function armDown(side)
					local ua = model:FindFirstChild(side .. "UpperArm")
					local la = model:FindFirstChild(side .. "LowerArm")
					local hd = model:FindFirstChild(side .. "Hand")
					if not (ua and la and hd) then return end
					-- destroy ANY Motor6D driving these arm parts (wherever it's parented) so the solver can't snap them back up
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("Motor6D") and (d.Part1 == ua or d.Part1 == la or d.Part1 == hd) then d:Destroy() end
					end
					local sgn = (side == "Left") and -1 or 1
					local tx, ty = torso.Size.X * 0.5, torso.Size.Y * 0.5
					local uaH, laH, hdH = ua.Size.Y * 0.5, la.Size.Y * 0.5, hd.Size.Y * 0.5
					local rot = torso.CFrame.Rotation
					local socket = (torso.CFrame * CFrame.new(sgn * (tx + ua.Size.X * 0.5), ty * 0.85, 0)).Position
					ua.CFrame = CFrame.new(socket) * rot * CFrame.new(0, -uaH, 0)        -- upper arm hangs from the shoulder
					la.CFrame = ua.CFrame * CFrame.new(0, -(uaH + laH), 0)               -- forearm below it
					hd.CFrame = la.CFrame * CFrame.new(0, -(laH + hdH), 0)               -- hand below that
					for _, pair in ipairs({ { ua, torso }, { la, ua }, { hd, la } }) do  -- rigid chain -> follows the body
						local wc = Instance.new("WeldConstraint"); wc.Part0 = pair[2]; wc.Part1 = pair[1]; wc.Parent = pair[1]
					end
				end
				armDown("Right") -- holds the pitchfork (handle rises upright from the lowered hand)
				armDown("Left")
			end)
			local function welded(name, part0, shape, size, color, worldCF)
				if not part0 then return end
				local p = Instance.new("Part")
				p.Name = name; p.Shape = shape; p.Size = size; p.Color = color
				p.Material = Enum.Material.Plastic
				p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
				p.CastShadow = false; p.Massless = true
				p.TopSurface = SMOOTH; p.BottomSurface = SMOOTH; p.LeftSurface = SMOOTH
				p.RightSurface = SMOOTH; p.FrontSurface = SMOOTH; p.BackSurface = SMOOTH
				p.CFrame = worldCF; p.Parent = model
				local wc = Instance.new("WeldConstraint"); wc.Part0 = part0; wc.Part1 = p; wc.Parent = p
				return p
			end
			-- CLEAN SIMPLE PLAID on a part's FRONT (-Z) face: just 2 evenly-spaced vertical + 2 horizontal BOLD darker-red
			-- bands (band thickness scales to the part), no thin pale scribble -> reads as a tidy check, not noise. Flush.
			local function plaidBands(part)
				if not part then return end
				local hx, hy, hz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5
				local z0 = -(hz + 0.012)
				local t = math.max(hx, hz) * 0.46 -- WIDE bold band thickness, proportional (clean check, not scribble)
				for _, gx in ipairs({ -0.45, 0.45 }) do welded("Plaid", part, BLK, V3(t, hy * 1.96, 0.05), PLAIDD, part.CFrame * CFrame.new(gx * hx, 0, z0)) end -- 2 verticals
				for _, gy in ipairs({ -0.45, 0.45 }) do welded("Plaid", part, BLK, V3(hx * 1.96, t, 0.05), PLAIDD, part.CFrame * CFrame.new(0, gy * hy, z0)) end -- 2 horizontals
			end
			-- two-tone SHADE panels flush on a part's two side faces (±X) for fake form/shadow
			local function shadeSides(part, color)
				if not part then return end
				local hx, hy, hz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5
				welded("Shade", part, BLK, V3(0.04, hy * 1.96, hz * 1.55), color, part.CFrame * CFrame.new(-(hx + 0.006), -hy * 0.08, 0))
				welded("Shade", part, BLK, V3(0.04, hy * 1.96, hz * 1.55), color, part.CFrame * CFrame.new( (hx + 0.006), -hy * 0.08, 0))
			end
			local headP = model:FindFirstChild("Head")
			local UT    = model:FindFirstChild("UpperTorso")
			local hand  = model:FindFirstChild("RightHand") or model:FindFirstChild("LeftHand")
			pcall(function()
				if headP then
					local hy, hz = headP.Size.Y * 0.5, headP.Size.Z * 0.5
					local hxh = headP.Size.X * 0.5
					local fz, ex = -(hz + 0.01), hz * 0.36
					-- FACE: two small round dark eyes (upper-middle, even + symmetric), rosy cheeks, a small soft upward smile
					welded("Eye", headP, BAL, V3(0.16, 0.16, 0.09), EYEC, headP.CFrame * CFrame.new(-ex, hy * 0.24, fz))
					welded("Eye", headP, BAL, V3(0.16, 0.16, 0.09), EYEC, headP.CFrame * CFrame.new( ex, hy * 0.24, fz))
					welded("Cheek", headP, BAL, V3(0.18, 0.12, 0.08), CHEEK, headP.CFrame * CFrame.new(-ex * 1.5, hy * 0.02, fz))
					welded("Cheek", headP, BAL, V3(0.18, 0.12, 0.08), CHEEK, headP.CFrame * CFrame.new( ex * 1.5, hy * 0.02, fz))
					welded("Mouth", headP, BLK, V3(0.22, 0.05, 0.06), EYEC, headP.CFrame * CFrame.new(0, -hy * 0.14, fz))       -- centre (lowest)
					welded("Mouth", headP, BLK, V3(0.07, 0.05, 0.06), EYEC, headP.CFrame * CFrame.new(-0.15, -hy * 0.09, fz))  -- corner turns up
					welded("Mouth", headP, BLK, V3(0.07, 0.05, 0.06), EYEC, headP.CFrame * CFrame.new( 0.15, -hy * 0.09, fz))
					-- BROWN BEARD: smooth rounded ellipsoid mass over the lower face/jaw (covers below the mouth so eyes+smile
					-- stay visible above it) + a mustache. Rounded, flush, no blocky chunks.
					welded("Beard", headP, BAL, V3(hxh * 1.9, hy * 0.95, hz * 1.55), BEARD, headP.CFrame * CFrame.new(0, -hy * 0.74, -hz * 0.32)) -- main rounded beard
					welded("Beard", headP, BAL, V3(hxh * 1.4, hy * 0.5, hz * 0.7),   BEARD, headP.CFrame * CFrame.new(0, -hy * 0.5, -(hz + 0.02))) -- rounded chin proud of the face
					welded("Beard", headP, BLK, V3(0.34, 0.07, 0.07),               BEARD, headP.CFrame * CFrame.new(0, -hy * 0.04, fz))          -- mustache (just above the smile)
					-- STRAW HAT on top (brim above the eyes, face visible) + thin darker band + rounded crown
					welded("HatBrim",  headP, CYL, V3(0.16, 3.0, 3.0),  STRAW, headP.CFrame * CFrame.new(0, hy + 0.16, 0) * CFrame.Angles(0, 0, math.rad(90)))
					welded("HatBand",  headP, CYL, V3(0.34, 1.55, 1.55), BANDC, headP.CFrame * CFrame.new(0, hy + 0.34, 0) * CFrame.Angles(0, 0, math.rad(90)))
					welded("HatCrown", headP, BAL, V3(1.55, 1.4, 1.55),  STRAW, headP.CFrame * CFrame.new(0, hy + 0.6, 0))
				end
			end)
			pcall(function()
				if UT then
					plaidBands(UT)        -- clean 2x2 bold check across the chest
					shadeSides(UT, SHADE) -- darker red on the torso sides for depth
				end
			end)
			pcall(function()
				if hand then
					-- PITCHFORK held upright: a tall thin brown handle + a small head with 3 grey metal prongs at the top
					local fCF = CFrame.new(hand.Position) * faceCF.Rotation -- gardener-facing frame at the hand (Y = world up)
					welded("ForkHandle", hand, CYL, V3(3.8, 0.16, 0.16), HANDLE, fCF * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90))) -- vertical handle
					local topY = 0.4 + 1.9 -- handle centre 0.4 + half-length 1.9 -> top of the handle
					welded("ForkFerrule", hand, CYL, V3(0.24, 0.22, 0.22), FERRULE, fCF * CFrame.new(0, topY - 0.05, 0) * CFrame.Angles(0, 0, math.rad(90))) -- metal collar where prongs meet handle
					welded("ForkHead", hand, BLK, V3(0.7, 0.12, 0.12), PRONG, fCF * CFrame.new(0, topY + 0.04, 0)) -- crossbar the prongs sit on
					for _, px in ipairs({ -0.26, 0, 0.26 }) do
						welded("ForkProng", hand, CYL, V3(1.05, 0.07, 0.07), PRONG, fCF * CFrame.new(px, topY + 0.54, 0) * CFrame.Angles(0, 0, math.rad(90))) -- 3 even, parallel, upright prongs
					end
				end
			end)

			-- 7) EXTRA FARMER DETAILING (depth without textures): collar + lower-torso shadow, belt + buckle, sleeve cuffs,
			-- arm plaid, leg shading, boot cuffs, brown eyebrows. Wrapped in pcall so any one detail can't abort the others.
			pcall(function()
			local function findP(n) return model:FindFirstChild(n) end
			if UT then
				local tz, ty, tx = UT.Size.Z * 0.5, UT.Size.Y * 0.5, UT.Size.X * 0.5
				welded("Collar", UT, BLK, V3(tx * 1.7, 0.22, tz * 2.0 + 0.06), SHIRTD, UT.CFrame * CFrame.new(0, ty * 0.82, 0)) -- collar around the neck
			end
			local LT = findP("LowerTorso")
			if LT then
				local lz, ly, lx = LT.Size.Z * 0.5, LT.Size.Y * 0.5, LT.Size.X * 0.5
				welded("Belt",   LT, BLK, V3(lx * 2.0 + 0.05, 0.3, lz * 2.0 + 0.05), BELT,    LT.CFrame * CFrame.new(0, ly * 0.55, 0))
				welded("Buckle", LT, BLK, V3(0.32, 0.24, 0.06),                      FERRULE, LT.CFrame * CFrame.new(0, ly * 0.55, -(lz + 0.03)))
			end
			-- clean plaid bands on BOTH arms (upper + lower) so the sleeves match the shirt
			for _, an in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }) do
				plaidBands(findP(an))
			end
			for _, an in ipairs({ "LeftLowerArm", "RightLowerArm" }) do
				local a = findP(an)
				if a then
					local ay, ar = a.Size.Y * 0.5, math.max(a.Size.X, a.Size.Z) * 0.5
					shadeSides(a, SHADE) -- darker red on the forearm sides
					welded("Cuff", a, CYL, V3(0.24, ar * 2.0 + 0.12, ar * 2.0 + 0.12), PLAIDL, a.CFrame * CFrame.new(0, -ay * 0.78, 0) * CFrame.Angles(0, 0, math.rad(90))) -- rolled pale cuff at the wrist
				end
			end
			-- darker denim on the INNER side of each leg (fake shadow between the legs)
			for _, leg in ipairs({ { "LeftUpperLeg", 1 }, { "LeftLowerLeg", 1 }, { "RightUpperLeg", -1 }, { "RightLowerLeg", -1 } }) do
				local l = findP(leg[1])
				if l then
					local lx, ly, lz = l.Size.X * 0.5, l.Size.Y * 0.5, l.Size.Z * 0.5
					welded("LegShade", l, BLK, V3(0.04, ly * 1.96, lz * 1.5), DENIMI, l.CFrame * CFrame.new(leg[2] * (lx + 0.006), 0, 0))
				end
			end
			for _, fn in ipairs({ "LeftFoot", "RightFoot" }) do
				local f = findP(fn)
				if f then
					local fy, fx, fzd = f.Size.Y * 0.5, f.Size.X * 0.5, f.Size.Z * 0.5
					welded("BootCuff", f, BLK, V3(fx * 2.0 + 0.06, 0.2, fzd * 2.0 + 0.06), HANDLE, f.CFrame * CFrame.new(0, fy * 0.85, 0)) -- light cuff at the boot top
				end
			end
			if headP then
				local hy, hz = headP.Size.Y * 0.5, headP.Size.Z * 0.5
				local fz, ex = -(hz + 0.012), hz * 0.42
				welded("Brow", headP, BLK, V3(0.2, 0.06, 0.06), BEARD, headP.CFrame * CFrame.new(-ex, hy * 0.34, fz))
				welded("Brow", headP, BLK, V3(0.2, 0.06, 0.06), BEARD, headP.CFrame * CFrame.new( ex, hy * 0.34, fz))
			end
			end)
			return model, hum, hrp
		end

		-- 1) USE THE PRE-PLACED "Mr. Farmer" model from ReplicatedStorage by CLONING it (LoadAsset fails for plugin
		-- assets). Pull out the character (the model that owns a Humanoid) and parent the clone under the garden props.
		local loadedOk, model = false, nil
		local okLoad, char = pcall(function()
			local src = game:GetService("ReplicatedStorage"):FindFirstChild("Mr. Farmer")
			if not src then return nil end
			local c = src:Clone()
			local ch = (c:FindFirstChildOfClass("Humanoid") and c) or nil
			if not ch then
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then ch = d; break end
				end
			end
			if not ch then c:Destroy(); return nil end
			ch.Parent = props
			if ch ~= c then c:Destroy() end -- drop the leftover wrapper if the character was nested
			return ch
		end)
		if okLoad and char then model = char; loadedOk = true end
		print("[Garden][Gardener] " .. (loadedOk and "using Mr. Farmer model ok" or "Mr. Farmer missing -> fallback"))

		-- 2) set it up: the asset uses its OWN baked look (no code-built clothing); the fallback is the colour-dressed rig.
		local okBuild, err = pcall(function()
			if model then
				model.Name = "Gardener"; model:SetAttribute("GardenerNPC", true)
				if model.Parent ~= props then model.Parent = props end
				local hum, hrp = placeGardener(model)
				attachBehavior(model, hum, hrp)
			else
				local m, hum, hrp = buildColoredGardener()
				m.Name = "Gardener"; m:SetAttribute("GardenerNPC", true)
				attachBehavior(m, hum, hrp, true) -- no idle: arms are posed via Motor6D C0 and must hold the pose
				model = m
			end
		end)

		if okBuild and model then
			print("[Garden][Prop] Gardener built OK -- " .. (loadedOk and "Mr. Farmer model" or "coloured R15 fallback"))
		else
			warn("[Garden][Prop] Gardener FAILED -- " .. tostring(err))
		end
	end)

	-- 4) CORNER PLANTER BOXES: 2 raised wooden boxes outside the ring (back-left/back-right) with dark soil + a few plants.
	local function buildPlanter(name, a)
		local m = Instance.new("Model"); m.Name = name; m.Parent = props
		local f = base * CFrame.new(math.cos(a) * 51, 0, math.sin(a) * 51) * CFrame.Angles(0, -a, 0)
		prop("Box", BLK, Vector3.new(4, 3, 6), WOOD, f * CFrame.new(0, 1.5, 0), m)            -- low wooden box
		prop("BoxRim", BLK, Vector3.new(4.3, 0.6, 6.3), WOOD2, f * CFrame.new(0, 3.0, 0), m)  -- darker wood rim at the top edge
		prop("SoilTop", BLK, Vector3.new(3.4, 0.6, 5.4), SOIL, f * CFrame.new(0, 3.2, 0), m)  -- dark soil fill
		local top = f * CFrame.new(0, 3.4, 0)
		pcall(buildBush, m, top * CFrame.new(0, 0, -1.6), 0.7, 4)            -- a few of the existing bushes/flowers on top
		pcall(buildSmallFlower, m, top * CFrame.new(0.6, 0, 0.8), 0.8, 4, nil)
		pcall(buildSmallFlower, m, top * CFrame.new(-0.8, 0, 1.4), 0.8, 4, nil)
		return m
	end
	tryProp("Planter_BL", function() buildPlanter("Planter_BL", openAngle + math.rad(155)) end)
	tryProp("Planter_BR", function() buildPlanter("Planter_BR", openAngle - math.rad(155)) end)

	-- 4b) PERIMETER FENCE: a continuous, even, GAP-FREE wooden post-and-rail ring just outside the outer wall (r46.8),
	-- sitting FLUSH on the ground (footings keep it grounded, never perched/floating). Chunky capped posts (all the
	-- SAME height) + 2 rails that butt flush into the next post (overlap). Clean opening ONLY at the front entrance.
	tryProp("Fence", function()
		local m = Instance.new("Model"); m.Name = "Fence"; m.Parent = props
		local fr, N, postH = 46.8, 40, 3.0
		local railLen = (2 * math.pi * fr / N) * 1.12 -- generous overlap -> rails butt flush into the posts (no gaps)
		local function present(idx)
			local a = idx * (2 * math.pi / N)
			return math.abs(((a - openAngle + math.pi) % (2 * math.pi)) - math.pi) > (openHalf + 0.25)
		end
		for i = 0, N - 1 do
			if present(i) then
				local a = i * (2 * math.pi / N)
				local cf = base * CFrame.new(math.cos(a) * fr, 0, math.sin(a) * fr) * CFrame.Angles(0, -a, 0) -- X radial, Z tangent
				prop("FenceFoot", BLK, Vector3.new(0.95, 0.7, 0.95), WOOD, cf * CFrame.new(0, 0.05, 0), m)          -- footing flush on the ground (slightly sunk)
				prop("FencePost", BLK, Vector3.new(0.7, postH, 0.7), WOOD, cf * CFrame.new(0, postH * 0.5 + 0.4, 0), m) -- chunky post, same height all round
				prop("FencePostCap", BLK, Vector3.new(0.95, 0.3, 0.95), WOOD2, cf * CFrame.new(0, postH + 0.55, 0), m)  -- small cap on each post
				if present((i + 1) % N) then -- rails toward the NEXT post only if it exists (no dangling rail at the opening)
					local mid = (i + 0.5) * (2 * math.pi / N)
					local rcf = base * CFrame.new(math.cos(mid) * fr, 0, math.sin(mid) * fr) * CFrame.Angles(0, -mid, 0)
					prop("FenceRail", BLK, Vector3.new(0.3, 0.35, railLen), WOOD, rcf * CFrame.new(0, 2.5, 0), m)  -- upper rail
					prop("FenceRail", BLK, Vector3.new(0.3, 0.35, railLen), WOOD, rcf * CFrame.new(0, 1.3, 0), m)  -- lower rail
				end
			end
		end
	end)

	-- 5) GROWTH DIAL MONUMENT: a FREESTANDING front monument on the ground in the path corridor, in front of the
	-- staircase (r28 along the doorway), NOT on the dais -- a tiered stone pedestal + a big gold-ringed dark dial
	-- (GLOBAL GROWTH <pct>%, green progress arc) + a wooden NEXT REWARD plaque below it. Its +X face points OUTWARD
	-- so a player walking up the path reads it head-on. Same live updater (refreshGrowthDial / getProgress / GOAL).
	tryProp("GrowthDial", function()
		local m = Instance.new("Model"); m.Name = "GrowthDial"; m.Parent = props
		local N = 24
		local DGREEN = Color3.fromRGB(90, 200, 80) -- bright progress-arc green
		local DDISC  = Color3.fromRGB(30, 28, 26)  -- dark dial face
		local mcf = base * CFrame.new(math.cos(openAngle) * 28, 0, math.sin(openAngle) * 28) * CFrame.Angles(0, -openAngle, 0) -- GROUNDED + CENTERED on the path axis, just in front of the steps; +X faces straight down the path
		local function solid(name, shape, size, color, cf) local p = prop(name, shape, size, color, cf, m); p.CanCollide = true; return p end

		-- tiered stone PEDESTAL (2 stacked slabs + a darker coursing seam) -- a solid plinth in dais stone tone
		solid("Pedestal", BLK, Vector3.new(4.0, 2.5, 7.0), STONE, mcf * CFrame.new(0, 1.25, 0))   -- lower slab (y0..2.5)
		prop("PedestalLip", BLK, Vector3.new(4.2, 0.4, 7.2), STONE2, mcf * CFrame.new(0, 2.5, 0), m) -- coursing seam
		solid("Pedestal", BLK, Vector3.new(3.2, 2.0, 5.5), STONE, mcf * CFrame.new(0, 3.5, 0))    -- upper slab (y2.5..4.5)

		-- wooden NEXT REWARD plaque (gold-trimmed) on the pedestal front, below the dial
		prop("PlaqueTrim", BLK, Vector3.new(0.3, 2.2, 5.4), GOLDB, mcf * CFrame.new(1.70, 3.6, 0), m)
		local plaque = prop("Plaque", BLK, Vector3.new(0.4, 1.8, 5.0), WOOD, mcf * CFrame.new(1.85, 3.6, 0), m) -- front (+X) holds the text
		local psg = Instance.new("SurfaceGui"); psg.Name = "PlaqueUI"; psg.Face = Enum.NormalId.Right; psg.CanvasSize = Vector2.new(360, 140); psg.Parent = plaque

		-- the BIG round dial up top: thick gold outer ring + large dark face + green progress arc (segment ring)
		local dY, ringR = 9.4, 4.1
		local dial = mcf * CFrame.new(0, dY, 0)
		prop("DialRing", CYL, Vector3.new(0.4, 10.6, 10.6), GOLDB, dial * CFrame.new(-0.15, 0, 0), m) -- bold solid gold outer ring (round face +/-X)
		prop("DialDisc", CYL, Vector3.new(0.5, 9.0, 9.0), DDISC, dial, m)                              -- large dark face, +X toward the player
		local segs = {}
		for i = 0, N - 1 do
			local th = (i / N) * 2 * math.pi - math.pi / 2 -- start at top, go clockwise
			segs[#segs + 1] = prop("DialSeg", BLK, Vector3.new(0.55, 0.62, 0.62), GOLDB, dial * CFrame.new(0.30, math.cos(th) * ringR, math.sin(th) * ringR), m)
		end
		local holder = prop("DialText", BLK, Vector3.new(0.05, 6.2, 6.2), DARKB, dial * CFrame.new(0.36, 0, 0), m)
		holder.Transparency = 1 -- invisible holder; the SurfaceGui renders the text on its +X (Right) face
		local sg = Instance.new("SurfaceGui"); sg.Name = "DialUI"; sg.Face = Enum.NormalId.Right; sg.CanvasSize = Vector2.new(420, 420); sg.Parent = holder
		local function label(parent, txt, y, sy, color, font)
			local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.new(1, -10, sy, 0); l.Position = UDim2.new(0, 5, y, 0)
			l.Font = font; l.TextScaled = true; l.Text = txt; l.TextColor3 = color; l.TextXAlignment = Enum.TextXAlignment.Center; l.Parent = parent
			local s = Instance.new("UIStroke", l); s.Thickness = 2.5; s.Color = Color3.fromRGB(20, 14, 8); return l
		end
		label(sg, "GLOBAL GROWTH", 0.14, 0.20, GOLD, Enum.Font.FredokaOne)
		local pctL = label(sg, "0%", 0.40, 0.42, DGREEN, Enum.Font.FredokaOne)          -- big bold percent
		label(psg, "NEXT REWARD", 0.06, 0.42, GOLDB, Enum.Font.FredokaOne)
		local cntL = label(psg, "0 / " .. GOAL, 0.52, 0.42, WHITETXT, Enum.Font.GothamBold)
		-- the module-level updater (UNCHANGED logic): reads the live progress, updates text + lights the ring proportionally
		refreshGrowthDial = function()
			local p, g = getProgress(), GOAL
			local pct = math.clamp(math.floor(p / g * 100), 0, 100)
			pcall(function()
				pctL.Text = pct .. "%"
				cntL.Text = string.format("%d / %d", p, g)
				local lit = math.floor(pct / 100 * N + 0.5)
				for i = 1, N do
					local on = (i <= lit)
					segs[i].Color = on and DGREEN or GOLDB
					segs[i].Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
				end
				if contributorLabel then contributorLabel.Text = tostring(gardenContributors or "\xE2\x80\x94") end
			end)
			print("[Garden][Dial] refreshed -> " .. pct .. "% (" .. p .. "/" .. g .. ")")
		end
		refreshGrowthDial() -- initial draw
	end)
	print("[Garden][Struct] dial (grounded + centered on the path, faces down it) done")

	-- PROOF the rotation reaches placement: the doorway's WORLD position through the rotated `base` vs through the
	-- unrotated origin `C`. These MUST differ -- if they're equal, the rotation isn't wired to placement.
	local doorOff = CFrame.new(math.cos(openAngle) * 32, 0, math.sin(openAngle) * 32)
	print("[Garden][Hardscape] doorway worldPos=" .. tostring((base * doorOff).Position)
		.. "  (unrotated would be " .. tostring((C * doorOff).Position) .. ")")
	print("[Garden][Hardscape] built -- rotated 90deg CW; dais o26/o17 (top +4), ring beds r32/r46, FULLY-CLOSED inner+outer stone walls with ONE front doorway, gold-capped pillars -- doorway/steps turn WITH the garden now")

	-- FORCE the warm tan onto EVERY stone part by name (belt-and-suspenders: even if a creation colour slipped, this
	-- guarantees it) and report the count so we can confirm it actually hit the parts.
	do
		local MAIN = { DaisTier = true, Step = true, Pillar = true, InnerWall = true, OuterWall = true, Walkway = true, GatePillar = true, CheekWall = true } -- main tan stone (NOT "Brick" -> keeps the two-tone)
		local EDGE = { DaisLip = true, StepLip = true, CheekCap = true } -- darker coursing/lips
		local n, tally = 0, {}
		for _, p in ipairs(hs:GetDescendants()) do
			if p:IsA("BasePart") then
				if MAIN[p.Name] then p.Color = STONE; n = n + 1; tally[p.Name] = (tally[p.Name] or 0) + 1
				elseif EDGE[p.Name] then p.Color = STONE2; n = n + 1; tally[p.Name] = (tally[p.Name] or 0) + 1 end
			end
		end
		local parts = {}; for nm, c in pairs(tally) do parts[#parts + 1] = nm .. "=" .. c end
		print("[Garden][Hardscape] stone recolored: " .. n .. " parts set to tan { " .. table.concat(parts, ", ") .. " }")
		print("[Garden][Hardscape] brick coursing: " .. brickCount .. " bricks (tiers + ring walls)")
	end

	-- [IDPART] one-time scan to ID two flat reddish strips lying along the inner ring wall on the RIGHT side of the
	-- entrance (planter/banner curve). Scans the whole garden container (gardenBuild). Widens the box if < 2 hits.
	do
		local function ancestorModel(p)
			local a = p.Parent
			while a and a ~= gardenBuild and not a:IsA("Model") do a = a.Parent end
			return (a and a:IsA("Model")) and a.Name or (p.Parent and p.Parent.Name or "?")
		end
		local function scan(xmin, xmax, zmax, ymin, ymax, tag)
			local matches = 0
			for _, p in ipairs(gardenBuild:GetDescendants()) do
				if p:IsA("BasePart") then
					local pos = p.Position
					if pos.X >= xmin and pos.X <= xmax and pos.Z < zmax and pos.Y >= ymin and pos.Y <= ymax then
						matches = matches + 1
						print(string.format("[IDPART]%s name=%s class=%s parentModel=%s color=%s material=%s size=%s pos=%s",
							tag, p.Name, p.ClassName, ancestorModel(p), tostring(p.Color), tostring(p.Material), tostring(p.Size), tostring(pos)))
					end
				end
			end
			return matches
		end
		local n = scan(-75, -55, -15, 241, 243, "") -- right side of the entrance, near the wall top
		print("[IDPART] done, " .. n .. " matches")
		if n < 2 then
			print("[IDPART] fewer than 2 -- WIDENING range (Z<-8, X -82..-48, Y 238..246)")
			local n2 = scan(-82, -48, -8, 238, 246, " WIDE")
			print("[IDPART] WIDE done, " .. n2 .. " matches")
		end
	end

	-- [SEAMFILLREMOVE] safety net: destroy any leftover SEAMFILL_3 / SEAMFILL_4 parts (the block + its Cap + Brick
	-- companions). The bridge loop above already SKIPS gaps 3 & 4, so normally nothing's here -- this just guarantees
	-- none linger from an older build state. Runs at the END of every build. (Replaces the COLORMAP/PINKREMOVE step.)
	do
		local removed = 0
		for _, p in ipairs(hs:GetDescendants()) do
			if p:IsA("BasePart") and string.match(p.Name, "^SEAMFILL_[34]") then -- SEAMFILL_3, _3Cap, _3Brick, _4, _4Cap, _4Brick
				print("[SEAMFILLREMOVE] removed " .. p.Name)
				p:Destroy(); removed = removed + 1
			end
		end
		print("[SEAMFILLREMOVE] done, removed " .. removed .. " total")
	end

	-- [CONNECT] DIAGNOSTIC ONLY (no build/delete): position data to design curved connectors that bridge the two
	-- removed-filler gaps (gap3 ~ X-70 Z-22, gap4 ~ X-58 Z-29) from a wall end to the central monument/pillar.
	do
		local gaps = { [3] = Vector3.new(-70, 0, -22), [4] = Vector3.new(-58, 0, -29) }
		local function hd(a, b) return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude end
		local function runOf(W)
			if W.Size.Z >= W.Size.X then return W.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1)), W.Size.Z
			else return W.CFrame.RightVector, W.Size.X end
		end
		local function nearEndFace(W, p)
			local dir, len = runOf(W)
			local e1 = W.Position + dir * (len * 0.5); local e2 = W.Position - dir * (len * 0.5)
			return (hd(e1, p) <= hd(e2, p)) and e1 or e2
		end
		-- 1) PILLAR / gate-column parts near either gap (within 18 studs)
		for _, p in ipairs(hs:GetDescendants()) do
			if p:IsA("BasePart") and (string.find(p.Name, "Pillar") or string.find(p.Name, "Column")) then
				if hd(p.Position, gaps[3]) <= 18 or hd(p.Position, gaps[4]) <= 18 then
					print(string.format("[CONNECT] pillar name=%s shape=%s pos=%s size=%s",
						p.Name, (p:IsA("Part") and tostring(p.Shape) or p.ClassName), tostring(p.Position), tostring(p.Size)))
				end
			end
		end
		-- 2) wall ends: the two nearest InnerWall/OuterWall to each gap, end face nearest the gap
		local walls = {}
		for _, p in ipairs(hs:GetDescendants()) do if p:IsA("BasePart") and (p.Name == "InnerWall" or p.Name == "OuterWall") then walls[#walls + 1] = p end end
		local nearestEnd = {}
		for _, g in ipairs({ 3, 4 }) do
			local gp = gaps[g]
			local sorted = {}
			for _, w in ipairs(walls) do sorted[#sorted + 1] = { w = w, d = hd(w.Position, gp) } end
			table.sort(sorted, function(a, b) return a.d < b.d end)
			for k = 1, math.min(2, #sorted) do
				local w = sorted[k].w
				local ef = nearEndFace(w, gp)
				if k == 1 then nearestEnd[g] = ef end
				print(string.format("[CONNECT] wallend name=%s endface=%s pos=%s size=%s orientation=%s (gap %d, #%d nearest)",
					w.Name, tostring(ef), tostring(w.Position), tostring(w.Size), tostring(w.Orientation), g, k))
			end
		end
		-- 3) for each gap: nearest wall end -> nearest pillar face + distance
		local pillars = {}
		for _, p in ipairs(hs:GetDescendants()) do if p:IsA("BasePart") and p.Name == "Pillar" then pillars[#pillars + 1] = p end end
		for _, g in ipairs({ 3, 4 }) do
			local we = nearestEnd[g]
			if we then
				local bestP, bestD
				for _, p in ipairs(pillars) do local d = hd(p.Position, we); if not bestD or d < bestD then bestP, bestD = p, d end end
				if bestP then
					local radius = math.min(bestP.Size.X, bestP.Size.Z) * 0.5
					local toWall = Vector3.new(we.X - bestP.Position.X, 0, we.Z - bestP.Position.Z)
					local face = bestP.Position + (toWall.Magnitude > 0.01 and toWall.Unit or Vector3.new(1, 0, 0)) * radius
					print(string.format("[CONNECT] gap %d: wallEnd=%s -> pillarFace=%s distance=%.2f (pillar %s)",
						g, tostring(we), tostring(face), hd(we, face), bestP.Name))
				else
					print(string.format("[CONNECT] gap %d: wallEnd=%s -> NO pillar found", g, tostring(we)))
				end
			end
		end
		print("[CONNECT] done")
	end

	-- [PILLARCONNECT] two connector wall pieces joining the two short wall ends to the central monument pillar. Each
	-- runs from its wall END FACE to the nearest point on the pillar BASE footprint (+1 stud overlap INTO both the wall
	-- and the pillar -> no gap at either join), angled via CFrame.lookAt to meet the pillar face flush. Wall style
	-- (h1.5 / thick0.9 / tan STONE + STONE2 cap). Built every build -> survives rebuilds; parented into GardenHardscape.
	do
		local centerY = 241.586                 -- bottom on floor Y=240.836 (centre = floorY + h/2)
		local fpX1, fpX2 = -54.05, -49.65       -- pillar base (4.4 wide) footprint X range
		local fpZ1, fpZ2 = -18.96, -14.56       -- pillar base footprint Z range
		local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
		local sides = {
			{ id = "A", wallEnd = Vector3.new(-58.670, centerY, -32.679) }, -- OuterWall end
			{ id = "B", wallEnd = Vector3.new(-70.733, centerY, -25.693) }, -- InnerWall end
		}
		for _, s in ipairs(sides) do
			local we = s.wallEnd
			local contact = Vector3.new(clamp(we.X, fpX1, fpX2), centerY, clamp(we.Z, fpZ1, fpZ2)) -- nearest point on the pillar footprint
			local flat = Vector3.new(contact.X - we.X, 0, contact.Z - we.Z)
			local D = flat.Magnitude
			local dir = (D > 0.01) and flat.Unit or Vector3.new(1, 0, 0)
			local length = D + 2                 -- 1 stud overlap into the wall + 1 into the pillar
			local center = Vector3.new((we.X + contact.X) * 0.5, centerY, (we.Z + contact.Z) * 0.5)
			local cf = CFrame.lookAt(center, center + dir, Vector3.new(0, 1, 0)) -- length runs along local Z, pointing at the pillar
			local body = hpart("PILLARCONNECT_" .. s.id, BLK, Vector3.new(0.9, 1.5, length), STONE, cf, true)
			hpart("PILLARCONNECT_" .. s.id .. "Cap", BLK, Vector3.new(1.2, 0.3, length + 0.1), STONE2, cf * CFrame.new(0, 0.75, 0), true)
			print(string.format("[PILLARCONNECT] side %s: wallEnd=%s pillarContact=%s length=%.2f center=%s",
				s.id, tostring(we), tostring(contact), length, tostring(body.Position)))
		end
		print("[PILLARCONNECT] done")
	end

	return hs
end

-- Names this script ever parents into the world (containers + loose part names from current AND older versions).
-- Used to sweep away orphaned geometry so a rebuild can't leave stale parts behind. (Does NOT include the sign --
-- that's owned by the sign system.)
local STALE_BUILD_NAMES = {
	CommunityGardenBuild = true, GardenHardscape = true, CommunityGardenPlants = true, SunflowerCenterpiece = true,
	Soil = true, Border = true, Segment = true, Flower = true, Bush = true, Foliage = true, Tuft = true,
	MiniSunflowerPetals = true, DaisyPetals = true, Leaf = true, LeafTip = true, LeafVein = true, Celebrate = true,
	Step = true, Pillar = true, Cap = true, CapTip = true, DaisLower = true, DaisUpper = true,
	CenterBed = true, InnerBed = true, OuterBed = true, InnerWall = true, OuterWall = true,
}

-- DESTROY the entire previous garden build (container + any orphaned loose parts from earlier versions) so the
-- rebuild starts from a clean slate, then create + return ONE fresh container Model under the marker.
local function clearPreviousBuild(island, marker)
	local function sweep(container)
		if not container then return end
		for _, ch in ipairs(container:GetChildren()) do
			if STALE_BUILD_NAMES[ch.Name] then pcall(function() ch:Destroy() end) end
		end
	end
	sweep(marker)   -- prior CommunityGardenBuild / GardenHardscape / SunflowerCenterpiece + any loose parts under the marker
	sweep(island)   -- old loose border/soil/crops left directly in Island_1_BeanFarm by earlier versions
	sweep(Workspace) -- old CommunityGardenPlants Model (it used to be parented to Workspace) + any stray build parts
	-- RECURSIVE nuke: an OLD container nested anywhere (e.g. a gray GardenHardscape from a previous layout) would
	-- overlap the new tan build and read as gray. Destroy any build container found at ANY depth (runs before the
	-- fresh build exists, so it only removes stale copies).
	local CONTAINERS = { GardenHardscape = true, CommunityGardenBuild = true, GardenProps = true, CommunityGardenPlants = true, SunflowerCenterpiece = true }
	local cleared = 0
	for _, root in ipairs({ marker, island, Workspace }) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if CONTAINERS[d.Name] then pcall(function() d:Destroy() end); cleared = cleared + 1 end
			end
		end
	end
	print("[Garden] cleared previous build, rebuilding fresh (nuked " .. cleared .. " stale container(s))")
	local build = Instance.new("Model"); build.Name = "CommunityGardenBuild"; build.Parent = marker
	return build
end

-- WaterSpot must EXIST + PERSIST across rebuilds (parented to the island, NOT gardenBuild, and never in the stale
-- sweep) and sit somewhere reachable in the ROTATED layout (just beyond the base of the front steps). Recreated if
-- the rebuild ever lost it; the client attaches its hold-E ProximityPrompt to whatever part is named "WaterSpot".
local function ensureWaterSpot(island)
	local ws = resolveMarker(island, "WaterSpot")
	if not (ws and ws:IsA("BasePart")) then
		ws = Instance.new("Part"); ws.Name = "WaterSpot"; ws.Parent = island or Workspace
		warn("[Garden] WaterSpot was missing -> recreated")
	end
	ws.Anchored = true; ws.CanCollide = false; ws.CanQuery = false; ws.Transparency = 1
	ws.Size = Vector3.new(4, 8, 4)
	if gardenTopCF then
		local b, openAngle = gardenOrigin()
		ws.CFrame = b * CFrame.new(math.cos(openAngle) * 24, 4, math.sin(openAngle) * 24) -- just beyond the lowest front step, reachable up the path
	end
	waterSpotPos = ws.Position
	print("[Garden] WaterSpot found=" .. tostring(ws ~= nil) .. " pos=" .. tostring(ws and ws.Position))
	return ws
end

local function buildGarden(island)
	local fieldM = resolveMarker(island, "CommunityGarden")
	local waterM = resolveMarker(island, "WaterSpot")
	local signM  = resolveMarker(island, "GardenSignSpot")
	if not fieldM then warn("[Garden] 'CommunityGarden' marker not found -- garden disabled"); return false end

	local fcf, fsize = markerCFrameSize(fieldM)
	-- [GARDENSHIFT] move the WHOLE garden build as ONE rigid group. Net offset = the established base move
	-- (right 4 / forward 5) PLUS 4 studs to the PLAYER'S RIGHT when standing at the front looking at the garden /
	-- growth dial. The dial/doorway front (mcf's +X) faces OUTWARD toward the approaching player; the player's
	-- screen-right is that facing rotated -90deg about Y -> rightVec = (facing.Z, 0, -facing.X). Direction is
	-- translation-independent, so we derive it from the marker's rotation + the sign direction (same maths as
	-- gardenOrigin + the GrowthDial's mcf) BEFORE shifting. Applied ONCE to fcf -> every derived piece moves with it.
	local baseOffset = Vector3.new(4, 0, 5)
	local sgnPos = signM and ((signM:IsA("BasePart") and signM.Position) or select(1, signM:GetBoundingBox()).Position)
	local C = fcf
	local b = C * CFrame.Angles(0, math.rad(-90), 0)
	local wsd = sgnPos and Vector3.new(sgnPos.X - C.Position.X, 0, sgnPos.Z - C.Position.Z) or Vector3.new(0, 0, -1)
	if wsd.Magnitude < 0.05 then wsd = Vector3.new(0, 0, -1) end
	local lsd = C:VectorToObjectSpace(wsd.Unit)
	local openAngle = math.atan2(lsd.Z, lsd.X)
	local mcf = b * CFrame.new(math.cos(openAngle) * 28, 0, math.sin(openAngle) * 28) * CFrame.Angles(0, -openAngle, 0)
	local facing = mcf.RightVector -- the dial front normal (points OUTWARD toward the player)
	local rightVec = Vector3.new(facing.Z, 0, -facing.X) -- player's screen-right when facing the garden front
	rightVec = (rightVec.Magnitude > 0.001) and rightVec.Unit or Vector3.new(1, 0, 0)
	local GARDEN_SHIFT = baseOffset + rightVec * 8.5 -- player-right along rightVec: 4 + 6 - 2 + 0.5 = 8.5 total
	fcf = fcf + GARDEN_SHIFT
	fieldCenter = fcf.Position
	if waterM and waterM:IsA("BasePart") then waterSpotPos = waterM.Position; pcall(function() waterM.Transparency = 1; waterM.CanCollide = false end) end
	-- SOIL: keep the existing CommunityGarden plot at its ORIGINAL colour (no full-plot recolor) -- the dark
	-- fertilized soil is drawn as a ROUND disc inside the border ring in renderStage, so the rectangle's corners
	-- stay normal grass/ground outside the ring.
	pcall(function() if fieldM:IsA("BasePart") then fieldM.Transparency = 0; fieldM.CanCollide = false end end) -- keep the dirt visible

	-- COMPOSITION FRAME: the center of the field's top surface (the centerpiece sits here) + a usable layout
	-- radius. The rings of flowers, the planter border + the edge bushes are all arranged out from this center
	-- (in the field's LOCAL frame, so the field's rotation is respected). One designed scene, not a grid.
	gardenMarker = fieldM -- the build container parents under this marker (Workspace.Island_1_BeanFarm.CommunityGarden)
	gardenBuild = clearPreviousBuild(island, fieldM) -- WIPE any previous build (no stale parts) -> fresh container
	plantsFolder = Instance.new("Model"); plantsFolder.Name = "CommunityGardenPlants"; plantsFolder.Parent = gardenBuild
	local topY = fsize.Y / 2 + 0.1
	gardenTopCF = fcf * CFrame.new(0, topY, 0) -- fcf already includes GARDEN_SHIFT -> whole composition is moved
	print(string.format("[GARDENSHIFT] moved 0.5 stud player-right -- rightVec=(%.2f, %.2f, %.2f) (x8.5 total) -- new center=(%.1f, %.1f, %.1f)", rightVec.X, rightVec.Y, rightVec.Z, gardenTopCF.Position.X, gardenTopCF.Position.Y, gardenTopCF.Position.Z))
	gardenRad = math.min(fsize.X, fsize.Z) * 0.46
	if signM then signPos = (signM:IsA("BasePart") and signM.Position) or select(1, signM:GetBoundingBox()).Position end -- head tilts toward the sign
	local okHS, errHS = pcall(buildHardscape) -- permanent stone foundation (dais/steps/beds/walls/pillars), built once here
	if not okHS then warn("[Garden] buildHardscape ERROR -> " .. tostring(errHS)) end -- surface silent failures (signs/stone/etc.)
	ensureWaterSpot(island) -- (re)create + reposition the persistent WaterSpot at the base of the front steps (rotated origin)

	-- SIGN: a board at GardenSignSpot facing the garden, with a SurfaceGui (title + subtitle + progress bar + text)
	if signM then
		local scf = ((signM:IsA("BasePart")) and signM.CFrame or select(1, signM:GetBoundingBox())) + GARDEN_SHIFT -- [GARDENSHIFT] move the sign with the rest of the garden (same +4 X / +5 Z)
		pcall(function() if signM:IsA("BasePart") then signM.Transparency = 1; signM.CanCollide = false end end)
		local facing = CFrame.lookAt(scf.Position, Vector3.new(fieldCenter.X, scf.Position.Y, fieldCenter.Z)) -- Front (-Z) faces the garden
		local board = newPart(Workspace, "CommunityGardenSign", BLK, Vector3.new(12, 6.5, 0.5), Color3.fromRGB(120,82,48), facing * CFrame.new(0, 0, 0))
		newPart(Workspace, "GardenSignPostL", CYL, Vector3.new(4, 0.5, 0.5), Color3.fromRGB(96,64,38), facing * CFrame.new(-4.5, -5, 0) * CFrame.Angles(0,0,math.rad(90)))
		newPart(Workspace, "GardenSignPostR", CYL, Vector3.new(4, 0.5, 0.5), Color3.fromRGB(96,64,38), facing * CFrame.new( 4.5, -5, 0) * CFrame.Angles(0,0,math.rad(90)))
		local sg = Instance.new("SurfaceGui"); sg.Name = "GardenSignUI"; sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(600, 325); sg.Parent = board
		local function lbl(txt, posY, sizeY, ts, color, bold)
			local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.new(1,-20,sizeY,0); l.Position = UDim2.new(0,10,posY,0)
			l.Font = bold and Enum.Font.FredokaOne or Enum.Font.GothamBold; l.TextScaled = true; l.Text = txt; l.TextColor3 = color or Color3.new(1,1,1)
			l.Parent = sg; local s = Instance.new("UIStroke", l); s.Thickness = 2; s.Color = Color3.fromRGB(40,26,14); return l
		end
		lbl("\xF0\x9F\x8C\xB1 Community Garden", 0.04, 0.2, nil, Color3.fromRGB(190,255,170), true)
		lbl("Grown by the Fart to Float community", 0.27, 0.1, nil, Color3.fromRGB(235,225,205))
		-- progress bar
		local barBG = Instance.new("Frame"); barBG.Size = UDim2.new(0.9,0,0.16,0); barBG.Position = UDim2.new(0.05,0,0.44,0)
		barBG.BackgroundColor3 = Color3.fromRGB(40,30,18); barBG.BorderSizePixel = 0; barBG.Parent = sg
		Instance.new("UICorner", barBG).CornerRadius = UDim.new(0,10)
		local fill = Instance.new("Frame"); fill.Size = UDim2.new(0,0,1,0); fill.BackgroundColor3 = Color3.fromRGB(110,210,90); fill.BorderSizePixel = 0; fill.Parent = barBG
		Instance.new("UICorner", fill).CornerRadius = UDim.new(0,10)
		local pctL   = lbl("0% grown", 0.64, 0.16, nil, Color3.fromRGB(200,255,180), true)
		local countL = lbl("0 / " .. GOAL, 0.84, 0.12, nil, Color3.fromRGB(235,225,205))
		signLabels = { pct = pctL, count = countL, fill = fill }
	end
	return true
end

--======================================================================
-- WATERING (server-authoritative). The client sends a "water" intent; the server validates the cooldown
-- + proximity, adds the progress, and broadcasts the splash so all clients play the effect.
--======================================================================
GardenWaterEvent.OnServerEvent:Connect(function(player, action)
	if action == "query" then
		pcall(function() GardenWaterEvent:FireClient(player, { kind = "cooldown", secs = cooldownRemaining(player) }) end)
		return
	end
	if action ~= "water" then return end
	local remain = cooldownRemaining(player)
	if remain > 0 then
		pcall(function() GardenWaterEvent:FireClient(player, { kind = "denied", secs = remain }) end)
		return
	end
	-- proximity check (anti-cheat): must be near the WaterSpot
	if waterSpotPos then
		local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - waterSpotPos).Magnitude > WATER_RANGE then return end
	end
	waterReadyAt[player.UserId] = os.time() + COOLDOWN_SECONDS
	addProgress(WATER_AMOUNT)
	print("[Garden] " .. player.Name .. " watered (+" .. WATER_AMOUNT .. ") -> " .. getProgress())
	pcall(function() GardenWaterEvent:FireClient(player, { kind = "cooldown", secs = COOLDOWN_SECONDS }) end)
	pcall(function() GardenWaterEvent:FireAllClients({ kind = "splash", x = fieldCenter.X, y = fieldCenter.Y, z = fieldCenter.Z, sound = WATER_SOUND_ID }) end)
end)

--======================================================================
-- INIT: wait for islands to be positioned, resolve markers, build the garden, render the starting stage.
--======================================================================
task.spawn(function()
	local waited = 0
	while not Workspace:GetAttribute("StandsReady") and waited < 90 do task.wait(0.5); waited = waited + 0.5 end
	local island; for _ = 1, 30 do island = findIsland("Island_1_BeanFarm"); if island then break end; task.wait(1) end
	local ok = pcall(buildGarden, island)
	if not ok then warn("[Garden] build error -- garden may be incomplete") end
	currentStage = -1
	pcall(onProgressChanged) -- initial render of the sign + starting stage
	print("[Garden] ready, progress=" .. getProgress() .. "/" .. GOAL)
end)

--======================================================================
-- \xE2\x9A\xA0\xE2\x9A\xA0 TEST COMMANDS -- REMOVE BEFORE LAUNCH \xE2\x9A\xA0\xE2\x9A\xA0  (test users only, same _G.isAllowedTestUser allow-list)
--   /watergarden <n>  -> add n progress instantly (default a chunk) so growth stages can be watched
--   /resetgarden      -> reset progress to 0 AND clear the caller's water cooldown
--   /forceharvest     -> trigger the harvest->reward->new-season cycle immediately (test the cycle without filling)
--======================================================================
local function hookGardenChat(plr)
	plr.Chatted:Connect(function(msg)
		local lower = string.lower(msg)
		if string.sub(lower, 1, 12) == "/watergarden" then
			if not (_G.isAllowedTestUser and _G.isAllowedTestUser(plr)) then return end
			local n = tonumber(string.match(msg, "%-?%d+")) or 200
			addProgress(n)
			print("[Garden] /watergarden by " .. plr.Name .. " (+" .. n .. ") -> " .. getProgress() .. " (TEST - REMOVE BEFORE LAUNCH)")
		elseif lower == "/resetgarden" then
			if not (_G.isAllowedTestUser and _G.isAllowedTestUser(plr)) then return end
			waterReadyAt[plr.UserId] = nil
			setProgress(0)
			pcall(function() GardenWaterEvent:FireClient(plr, { kind = "cooldown", secs = 0 }) end) -- re-enable the caller's prompt
			print("[Garden] /resetgarden (TEST - REMOVE BEFORE LAUNCH) by " .. plr.Name)
		elseif lower == "/forceharvest" then
			if not (_G.isAllowedTestUser and _G.isAllowedTestUser(plr)) then return end
			print("[Garden] /forceharvest (TEST - REMOVE BEFORE LAUNCH) by " .. plr.Name)
			task.spawn(harvestAndAdvance, "forced")
		elseif string.sub(lower, 1, 9) == "/grantpet" then
			-- /grantpet <season>  -> grant that season's SEASONAL PET (+ its cosmetic entitlement). TEST - REMOVE BEFORE LAUNCH.
			if not (_G.isAllowedTestUser and _G.isAllowedTestUser(plr)) then return end
			local season = string.match(msg, "%a+%s+(%a+)")
			if season then
				local key = season:sub(1, 1):upper() .. season:sub(2):lower()
				plr:SetAttribute("EarnedCosmetic_" .. key, true)
				if _G.grantSeasonalPet then _G.grantSeasonalPet(plr, key) end
				print("[Garden] /grantpet " .. key .. " (TEST - REMOVE BEFORE LAUNCH) by " .. plr.Name)
			else
				print("[Garden] /grantpet usage: /grantpet <summer|autumn|winter|spring>")
			end
		elseif lower == "/seam" then
			-- TEMP: print the caller's HumanoidRootPart world position so we can capture exact gap coordinates. REMOVE BEFORE LAUNCH.
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local p = hrp.Position
				print(string.format("[SEAMPOS] %.2f, %.2f, %.2f", p.X, p.Y, p.Z))
			else
				print("[SEAMPOS] " .. plr.Name .. " has no HumanoidRootPart (not spawned?)")
			end
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do hookGardenChat(p) end
Players.PlayerAdded:Connect(hookGardenChat)
