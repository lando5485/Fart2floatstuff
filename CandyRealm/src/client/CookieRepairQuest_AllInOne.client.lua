--======================================================================
-- CookieRepairQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-3 QUEST: "Feed the Monster" (fix the Giant Cookie the only way that works)
--   * The GiantCookie you built in Studio already has chocolate chips in it. On
--     load this script HIDES them (leaving faint dents), so the cookie shows up
--     bare -- the Chocolate Monster ate its chocolate.
--       -> name those chips choc/chip/chunk/morsel in Studio for exact control;
--          otherwise they're auto-detected (small + dark parts on the big biscuit).
--   * The blocks named "chunk" around island3 become BAIT SPOTS: glowing plates.
--     The Candy Npc hands you TOTAL bait cookies with the job.
--   * THE LOOP. The monster hunts you the whole time and you cannot fight him --
--     but he is greedy. Drop a bait cookie on a plate and he drops everything to go
--     eat it (this script publishes _G.chocoLure; the lure branch in
--     ChocolateMonster_AllInOne walks him over and calls _G.chocoLureEaten). A fed
--     monster coughs one chunk straight back up -- grab it in the quiet before he
--     re-aggros. Bait is finite, so where you put him is a real decision.
--   * Collect them all, bring them to her, and the cinematic plays: camera pans to
--     the cookie, the chocolates rain back into their dents and pop solid,
--     shockwave + shake, fireworks, "You fixed the Giant Cookie!"
--
--   (This replaced a hunt for six chunks, each opened with a five-tap panel that had
--    no timer and no fail state -- thirty identical clicks, while the one tense thing
--    on the island, the chase, was something the quest worked around. The monster is
--    the quest now.)
--
-- Self-contained (matches CandyGumballQuest). Everything is scoped to island3 so
-- it never touches island1's same-named "Candy Npc".
--======================================================================

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")
local RunService      = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME      = "island3"
-- ⚠ 6 -> 4. Each one is now a full bait-and-collect cycle (drop, he walks over, he eats, he
-- coughs it up, you grab it while he re-aggros) rather than a five-tap panel, so four of them
-- is longer in play AND shorter in tedium than six of the old ones. It is also the bait count
-- the NPC hands you, so the two can never disagree.
local TOTAL            = 4
-- (PRY_CLICKS and PRY_MONSTER_BAIL are gone with the pry panel -- see the note further down.
--  Chunks come back up out of the monster now; nothing is levered out of anything, so there
--  is no modal left to bail out of when he closes in.)
local CHUNK_NAME       = "chunk"                       -- marker name (case-insensitive).
                                                       -- These are BAIT SPOTS now: each one
                                                       -- becomes a glowing plate you may put
                                                       -- a cookie on. The name is unchanged so
                                                       -- island 3's existing Studio markers
                                                       -- keep working untouched.
-- names below are compared with norm(): lowercase, spaces/underscores/hyphens removed.
-- So "Candy Npc" and "Giant Cookie" match "candynpc" / "giantcookie".
local NPC_NAMES        = { "candynpc" }
local COOKIE_NAME      = "giantcookie"
local COLLECT_DISTANCE = 12
local BANNER_RANGE     = 320                           -- banner only shows when near island3's NPC
-- HOW FAR FROM THE COOKIE A "chunk" MAY BE and still count as one of island 3's. The sweep
-- below matches any name CONTAINING "chunk" anywhere in Workspace, and island 11's mine builds
-- rock parts called Chunk -- so without this the cave filled up with chocolate pickups every
-- time you went down it. Generous enough to cover island 3, far short of anywhere else.
local CHUNK_RANGE      = 700

-- candy / chocolate palette
local FILL   = Color3.fromRGB(255, 240, 248)
local STROKE = Color3.fromRGB(120, 72, 40)   -- chocolate brown outline
local TEXTC  = Color3.fromRGB(74, 40, 22)
local HINTC  = Color3.fromRGB(150, 120, 100)
local CHOC   = Color3.fromRGB(92, 54, 28)    -- chocolate chunk color
local CHOC_HI= Color3.fromRGB(140, 90, 52)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function firstBasePart(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

-- bounding box for a Model OR a single BasePart (GetBoundingBox is Model-only)
local function boundsOf(inst)
	if inst:IsA("Model") then return inst:GetBoundingBox() end
	return inst.CFrame, inst.Size
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn()
		if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 45)
	return fn()
end

-- lowercase + drop spaces/underscores/hyphens, so "Giant Cookie", "giant_cookie" and
-- "GiantCookie" all match the same key. (The model in Studio is named "Giant Cookie".)
local function norm(s)
	return (string.gsub(string.lower(tostring(s or "")), "[%s_%-]", ""))
end

-- GiantCookie + chunks have UNIQUE names (island3 only) -> scan all of Workspace,
-- no island-model scoping needed (island3's model may not even parent them).
local function findCookie()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and norm(d.Name) == COOKIE_NAME then return d end
	end
	return nil
end

local function npcHeadOf(inst)
	if not inst then return nil end
	return (inst:IsA("Model") and (inst:FindFirstChild("Head") or inst.PrimaryPart or firstBasePart(inst)))
		or (inst:IsA("BasePart") and inst) or firstBasePart(inst)
end

-- there may be a "Candy Npc" on island1 AND island3 (same name). Disambiguate by
-- picking the one NEAREST the GiantCookie, so this quest never grabs island1's NPC.
local NPC_MAX_DIST = 400 -- an NPC must be within this of the GiantCookie to count as island3's
local function findNPCNear(refPos)
	if not refPos then return nil end -- no cookie found yet -> don't grab a far NPC (e.g. island1's)
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local nm = norm(d.Name)
		local match = false
		for _, want in ipairs(NPC_NAMES) do if nm == want then match = true; break end end
		if match then
			local head = npcHeadOf(d)
			if head then
				local dist = (head.Position - refPos).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = head, dist end
			end
		end
	end
	return best
end

-- ============================================================================
-- SPEECH BUBBLE (candy palette; paged) -- same look as the gumball quest
-- ============================================================================
local function hideBubble(adornee) local prev = adornee:FindFirstChild("SpeechBubble"); if prev then prev:Destroy() end end
local function showBubble(adornee, text, persist, footer)
	hideBubble(adornee)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = adornee; bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1,1); frame.BackgroundColor3 = FILL
	frame.BackgroundTransparency = 0.05; frame.BorderSizePixel = 0; frame.Parent = bb
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0,18); cr.Parent = frame
	local st = Instance.new("UIStroke"); st.Color = STROKE; st.Thickness = 2; st.Transparency = 0.3; st.Parent = frame
	local pd = Instance.new("UIPadding"); pd.PaddingTop=UDim.new(0,12); pd.PaddingBottom=UDim.new(0,12); pd.PaddingLeft=UDim.new(0,14); pd.PaddingRight=UDim.new(0,14); pd.Parent = frame
	local lbl = Instance.new("TextLabel"); lbl.Size = footer and UDim2.fromScale(1,0.78) or UDim2.fromScale(1,1)
	lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne; lbl.Text = text; lbl.TextColor3 = TEXTC
	lbl.TextScaled = true; lbl.TextWrapped = true; lbl.Parent = frame
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = lbl
	if footer then
		local h = Instance.new("TextLabel"); h.Size = UDim2.fromScale(1,0.2); h.Position = UDim2.fromScale(0,0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer; h.TextColor3 = HINTC; h.TextScaled = true; h.Parent = frame
		local hs = Instance.new("UITextSizeConstraint"); hs.MaxTextSize = 14; hs.Parent = h
	end
	bb.Parent = adornee
	if not persist then task.delay(9, function() if bb and bb.Parent == adornee and bb.Name == "SpeechBubble" then bb:Destroy() end end) end
end

-- ============================================================================
-- OBJECTIVE BANNER (top-center, proximity-gated to island3)
-- ============================================================================
local collected     = 0
local baitLeft      = 0     -- bait cookies in hand; the NPC hands over TOTAL when you accept
local questAccepted  = false
local delivered      = false
_G.cookieQuestComplete = false -- island-3 Cookie Stand (Shop_AllInOne) stays LOCKED until this is true
_G.cookieQuestStarted = _G.cookieQuestStarted or false -- Chocolate Monster stays hidden until you talk to the NPC

local objGui = Instance.new("ScreenGui")
objGui.Name = "CookieQuestObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12); objFrame.Size = UDim2.new(0, 520, 0, 52)
objFrame.BackgroundColor3 = FILL; objFrame.Visible = false; objFrame.Parent = objGui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = objFrame
   local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1); objLabel.Font = Enum.Font.FredokaOne
objLabel.TextColor3 = TEXTC; objLabel.TextScaled = true; objLabel.Parent = objFrame
do local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
   local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 14); pad.PaddingRight = UDim.new(0, 14); pad.Parent = objLabel end

local function baseObjectiveText()
	if delivered then return "\xF0\x9F\x8D\xAA The Giant Cookie is fixed -- the Cookie Stand is open!" end
	if not questAccepted then
		return "\xF0\x9F\x8D\xAA Talk to the Candy NPC to start -- follow the green arrows!"
	end
	if collected >= TOTAL then
		return ("\xF0\x9F\x8D\xAA You have all %d! Carry the chunks back to the Candy NPC."):format(TOTAL)
	end
	-- the line names whichever half of the loop you are in: bait is down and he is walking to
	-- it, or the plate is empty and it is on you to put a cookie on one
	if _G.chocoLure then
		return ("\xF0\x9F\x8D\xAB He's coming for the bait -- grab the chunk when he brings it up!  %d/%d")
			:format(collected, TOTAL)
	end
	return ("\xF0\x9F\x8D\xAA Drop Bait on a glowing plate to lure him off you  (%d bait left)  %d/%d")
		:format(baitLeft, collected, TOTAL)
end
local flashToken = 0
local npcHead     -- assigned below
-- banner shows ONLY when the player is near island3 (so it never overlaps island1's quest banner)
local wantVisible = false
local function refreshBanner() objLabel.Text = baseObjectiveText() end
local function flashBanner(text, seconds)
	flashToken += 1; local myTok = flashToken
	objLabel.Text = text
	task.delay(seconds or 2.5, function() if myTok == flashToken then refreshBanner() end end)
end

-- the food stand (Shop_AllInOne) calls this when you touch the LOCKED island-3 Cookie Stand
_G.cookieQuestNudge = function()
	flashBanner("\xF0\x9F\x8D\xAA Fix the Giant Cookie to unlock the Cookie Stand!", 2.5)
end
task.spawn(function()
	while true do
		local vis = false
		if wantVisible and npcHead and npcHead.Parent then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - npcHead.Position).Magnitude <= BANNER_RANGE
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- THE COOKIE -- its chocolates go MISSING on load, and come back on completion
-- ============================================================================
-- The GiantCookie is built in Studio and already has chocolate chips in it. We
-- hide those chips at load (leaving faint empty dents), and the chunks you find
-- around the island are those very chips -- they fly back in at the end.
local cookie                -- the GiantCookie instance (Model or BasePart)
local chocolates = {}       -- [i] = { part=, transparency=, size=, collide= }  the chips we hid
local biscuitPart           -- the big dough slab; the fly-in measures chips against it
local sockets    = {}       -- faint dents left behind where each chip was

local function mkPart(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

-- little gold sparkle where a chip lands
local function sparkleAt(pos)
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local s = mkPart({ Name = "ChocoSparkle", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35),
			Color = Color3.fromRGB(255, 226, 160), Material = Enum.Material.Neon })
		s.CFrame = CFrame.new(pos); s.Parent = Workspace
		TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 3, 1.6 + (i % 3) * 0.5, math.sin(a) * 3)),
			Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		Debris:AddItem(s, 0.7)
	end
end

-- ---------------------------------------------------------------------------
-- Which parts of the GiantCookie are its chocolate chips?
--   1) by NAME  -- anything called choc/chip/chunk/morsel (name them in Studio for exact control)
--   2) by LOOK  -- fallback: the biggest part is the biscuit; the small dark parts on it are chips
-- ---------------------------------------------------------------------------
local CHOC_NAME_HINTS = { "choc", "chip", "chunk", "morsel" }
local function looksLikeChocolate(name)
	local n = string.lower(name)
	for _, h in ipairs(CHOC_NAME_HINTS) do if string.find(n, h, 1, true) then return true end end
	return false
end
local function lum(c) return c.R * 0.299 + c.G * 0.587 + c.B * 0.114 end

-- returns: chips, how, biscuit  -- `biscuit` is the big dough part we sample colour/material
-- from when plugging the holes the chips leave behind.
local function findChocolates(inst)
	local parts = {}
	if inst:IsA("BasePart") then parts[1] = inst
	else for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then parts[#parts + 1] = d end end end

	-- the biggest part is the biscuit itself (the "cookie with holes" slab)
	local base, baseVol
	for _, p in ipairs(parts) do
		local v = p.Size.X * p.Size.Y * p.Size.Z
		if not baseVol or v > baseVol then base, baseVol = p, v end
	end

	local named = {}
	for _, p in ipairs(parts) do if p ~= base and looksLikeChocolate(p.Name) then named[#named + 1] = p end end
	if #named > 0 then return named, "name", base end

	if #parts < 2 then return {}, "single-mesh", base end
	local baseLum, out = lum(base.Color), {}
	for _, p in ipairs(parts) do
		local v = p.Size.X * p.Size.Y * p.Size.Z
		if p ~= base and v < baseVol * 0.2 and lum(p.Color) < baseLum - 0.05 then out[#out + 1] = p end
	end
	return out, "look", base
end

-- hide the cookie's chocolates -> it reads as "somebody stole my chocolate".
-- IDEMPOTENT: StreamingEnabled means the cookie's parts trickle in, so this is re-run on a
-- loop until the quest is delivered -- any chip that shows up late gets hidden too.
local hidden = {}   -- [part] = true, so a re-run never double-registers a chip
local function hideChocolates(quiet)
	if not cookie or not cookie.Parent then return end
	local found, how, biscuit = findChocolates(cookie)
	biscuitPart = biscuit or biscuitPart

	-- HAS IT ACTUALLY STREAMED IN YET? An empty Model replicates immediately; its Parts only arrive when a
	-- player is near them. So a cookie with ZERO BaseParts is not a badly-named cookie, it is a cookie nobody
	-- has flown to -- and the "rename your chips" advice below is then flatly wrong, sending you to Studio to
	-- fix parts that are fine. (This is exactly what the boot log showed: 0 parts, biscuit = none, reported
	-- while the player was on island 9.) hideChocolates is already re-run on a loop, so it self-heals on
	-- arrival; all this branch has to do is say so instead of accusing the model.
	local partCount = 0
	if cookie:IsA("BasePart") then partCount = 1
	else for _, d in ipairs(cookie:GetDescendants()) do if d:IsA("BasePart") then partCount += 1 end end end

	if not quiet and partCount == 0 then
		print(("[CookieQuest] cookie '%s' has no parts yet -- not streamed in. Fly to island 3; this re-checks itself.")
			:format(cookie.Name))
		return
	end

	if not quiet then
		print(("[CookieQuest] cookie '%s' (%s): %d chocolate part(s) found by %s; biscuit = %s"):format(
			cookie.Name, cookie.ClassName, #found, how, biscuit and biscuit.Name or "none"))
		-- auto-detection is a guess. If it found a suspicious number, dump what's actually in
		-- the model so the parts can be named explicitly (choc/chip/chunk/morsel) instead.
		if #found < 2 then
			warn("[CookieQuest] that looks wrong -- listing every BasePart in the cookie so you can name the chips:")
			local all = {}
			if cookie:IsA("BasePart") then all[1] = cookie
			else for _, d in ipairs(cookie:GetDescendants()) do if d:IsA("BasePart") then all[#all + 1] = d end end end
			for _, p in ipairs(all) do
				print(("    '%s'  %s  size=%.1f,%.1f,%.1f  colour=%d,%d,%d"):format(
					p.Name, p.ClassName, p.Size.X, p.Size.Y, p.Size.Z,
					math.floor(p.Color.R * 255), math.floor(p.Color.G * 255), math.floor(p.Color.B * 255)))
			end
			warn("[CookieQuest] rename the chocolate ones to Choc1..Choc6 in Studio and they'll be picked up exactly.")
		end
	end
	for _, p in ipairs(found) do
		if not hidden[p] then
			hidden[p] = true

			-- An INVISIBLE marker sitting exactly where the chip was. It's a clone of the chip
			-- purely for its geometry -- the Highlight below traces that shape, so the empty
			-- socket shimmers in the outline of the chocolate that belongs there.
			-- (Highlight renders on a fully transparent part, so the part itself stays unseen.)
			local wasArchivable = p.Archivable
			p.Archivable = true              -- Clone() returns nil on a non-archivable part
			local plug = p:Clone()
			p.Archivable = wasArchivable
			for _, ch in ipairs(plug:GetDescendants()) do ch:Destroy() end  -- drop decals/SurfaceAppearance/prompts
			plug.Name         = "ChocoSocket"
			plug.Anchored     = true
			plug.CanCollide   = false
			plug.CanQuery     = false
			plug.CastShadow   = false
			plug.Transparency = 1
			plug.Size         = p.Size
			plug.CFrame       = p.CFrame
			plug.Parent       = Workspace

			chocolates[#chocolates + 1] = { part = p, transparency = p.Transparency, size = p.Size, collide = p.CanCollide }
			p.Transparency = 1
			p.CanCollide = false
			p.CanQuery = false

			-- the shimmer itself -- a gold glow in the shape of the missing chocolate
			local hl = Instance.new("Highlight")
			hl.FillColor = Color3.fromRGB(255, 226, 160); hl.FillTransparency = 0.8
			hl.OutlineColor = Color3.fromRGB(255, 214, 130); hl.OutlineTransparency = 0.05
			hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = plug; hl.Parent = plug
			TweenService:Create(hl, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ FillTransparency = 0.97, OutlineTransparency = 0.65 }):Play()

			sockets[#sockets + 1] = plug
		end
	end
end

-- put them back: each chip drops in from above, lands in its dent, and pops solid
--======================================================================
-- A SLAB ARRIVES AS PIECES, NOT AS ONE LUMP
--======================================================================
-- The fly-in built ONE flyer at rec.size and dropped it on the dent. That is right for a cookie
-- whose chips are chip-sized, and wrong for this one: island3's Giant Cookie has a single MeshPart
-- called 'missing cholcolate' measuring 38.6 x 39.2 against a 78.7 x 68.1 biscuit -- 28% of the
-- whole cookie in one piece. So the payoff shot was a slab half the size of the cookie falling out
-- of the sky and smacking it flat. One object, one thud, no sense of chocolate being put back.
--
-- Now the SIZE of the chip decides how it arrives. Anything covering 5% or more of the biscuit's
-- top comes in as REVEAL_PIECES smaller chunks, spread across the footprint it is filling and
-- landing a beat apart, so the reveal reads as chocolate raining back in. A genuinely small chip
-- (a 6x6 morsel is 0.7% of that biscuit) still arrives as itself -- this does not turn a cookie
-- with six proper chips into eighteen crumbs.
--
-- The real part is untouched: the pieces are throwaway flyers, and the authored MeshPart still
-- un-hides underneath with its pop. Nothing about the cookie you built in Studio changes.
local REVEAL_PIECES = 3
local SLAB_FRACTION = 0.05

local function flyPieces(rec)
	if not (biscuitPart and rec.size) then return 1 end
	local biscuitArea = biscuitPart.Size.X * biscuitPart.Size.Z
	if biscuitArea <= 0 then return 1 end
	local chipArea = rec.size.X * rec.size.Z
	return (chipArea / biscuitArea >= SLAB_FRACTION) and REVEAL_PIECES or 1
end

-- sockets[i] belongs to chocolates[i] -- both are appended in lockstep by hideChocolates()
local function restoreChocolates()
	for i, rec in ipairs(chocolates) do
		local p = rec.part
		if p and p.Parent then
			task.delay((i - 1) * 0.09, function()
				if not (p and p.Parent) then return end
				local land = p.CFrame
				local n    = flyPieces(rec)

				-- THE REVEAL RUNS ONCE, AFTER THE LAST PIECE LANDS -- not per piece. Un-hiding the
				-- real part on the first landing would leave the other two dropping onto a chip that
				-- was already whole.
				local landed = 0
				local function onLanded()
					landed += 1
					if landed < n then return end
					local sock = sockets[i]                     -- the dent this chip is filling
					if sock then pcall(function() sock:Destroy() end); sockets[i] = nil end
					if not (p and p.Parent) then return end
					p.Transparency = rec.transparency
					p.CanCollide   = rec.collide
					p.CanQuery     = true
					if p.Anchored then   -- squash-and-stretch pop (only safe on anchored parts -- no welds to break)
						p.Size = rec.size * 0.35
						TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = rec.size }):Play()
					end
					sparkleAt(land.Position)
				end

				-- each piece is a chunk of the slab, a little taller than flat so it reads as a
				-- broken-off lump rather than a tile
				local pieceSize = (n == 1) and rec.size
					or Vector3.new(rec.size.X / n * 0.86, math.max(rec.size.Y, 1.1) * 1.15, rec.size.Z * 0.52)

				for k = 1, n do
					-- symmetric about the dent's centre: for n = 3 that is -1/3, 0, +1/3 of the width,
					-- with a small alternating nudge in Z so they do not sit in a dead straight line
					local spread = (n == 1) and Vector3.new(0, 0, 0)
						or Vector3.new(((k - (n + 1) * 0.5) / n) * rec.size.X, 0,
							(((k % 2) == 0) and 1 or -1) * rec.size.Z * 0.16)
					local target = land * CFrame.new(spread)
					task.delay((k - 1) * 0.13, function()
						local flyer = mkPart({ Name = "ChocoFlyIn", Size = pieceSize, Color = CHOC,
							Material = Enum.Material.SmoothPlastic, Reflectance = 0.06 })
						flyer.CFrame = target * CFrame.new(0, 26 + i * 3 + k * 2, 0)
							* CFrame.Angles(0, math.rad(i * 47 + k * 31), math.rad(15))
						flyer.Parent = Workspace
						local drop = TweenService:Create(flyer,
							TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = target })
						drop.Completed:Connect(function()
							flyer:Destroy()
							if n > 1 then sparkleAt(target.Position) end   -- each piece puffs where it lands
							onLanded()
						end)
						drop:Play()
					end)
				end
			end)
		end
	end
	-- safety sweep: clear any dent whose chip never made it back (streamed out, deleted, etc.)
	-- Allows for the staggered pieces: (REVEAL_PIECES - 1) * 0.13 + the 0.42 drop, plus headroom.
	task.delay(#chocolates * 0.09 + 1.8, function()
		for _, s in pairs(sockets) do pcall(function() s:Destroy() end) end
		sockets = {}
	end)
end

-- ============================================================================
-- FIREWORK + WIN BANNER
-- ============================================================================
local FW_COLORS = { Color3.fromRGB(255,92,138), Color3.fromRGB(120,200,255), Color3.fromRGB(150,235,130), Color3.fromRGB(255,205,90), Color3.fromRGB(190,130,255) }

local function burst(atPos, color)
	for _ = 1, 26 do
		local dir = Vector3.new(math.cos(_) * (0.5 + (_ % 5) * 0.1), 1, math.sin(_ * 1.7)) -- pseudo-spread (no Math.random in world spawns needed)
		local spark = mkPart({ Name = "Spark", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5,0.5,0.5), Color = color, Material = Enum.Material.Neon })
		spark.CFrame = CFrame.new(atPos); spark.Parent = Workspace
		local dest = atPos + (Vector3.new((_ % 7) - 3, (_ % 5), ((_ * 3) % 7) - 3)).Unit * 14
		TweenService:Create(spark, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(dest), Transparency = 1, Size = Vector3.new(0.1,0.1,0.1) }):Play()
		Debris:AddItem(spark, 1)
	end
end

local function launchFireworks(fromPos)
	for i = 1, 3 do
		task.delay(i * 0.35, function()
			local rocket = mkPart({ Name = "Rocket", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6,0.6,0.6), Color = Color3.fromRGB(255,240,200), Material = Enum.Material.Neon })
			local start = fromPos + Vector3.new((i - 2) * 6, 3, 0)
			local apex  = start + Vector3.new(0, 45 + i * 6, 0)
			rocket.CFrame = CFrame.new(start); rocket.Parent = Workspace
			local up = TweenService:Create(rocket, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(apex) })
			up.Completed:Connect(function()
				burst(apex, FW_COLORS[((i - 1) % #FW_COLORS) + 1])
				rocket:Destroy()
			end)
			up:Play()
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
local function winBanner()
	local msg = "\xF0\x9F\x8D\xAA You fixed the Giant Cookie! \xF0\x9F\x8E\x86"
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({
			top      = "\xE2\x9C\xA8 QUEST COMPLETE",
			text     = msg,
			color    = STROKE,
			priority = _G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.EVENT or nil,
			duration = 5,
		}) end)
	else
		print("[CookieQuest] " .. tostring(msg))
	end
end

-- expanding neon ring on the ground when the halves slam together
local function shockwave(center, size, delay, color)
	task.delay(delay, function()
		local ring = mkPart({ Name = "CookieShock", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 6, 6),
			Color = color, Material = Enum.Material.Neon, Transparency = 0.1 })
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)) -- Cylinder height is +X -> stand it up = flat disc
		ring.Parent = Workspace
		local d = math.max(size.X, size.Z) * 3.2 + 55
		TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.7, d, d), Transparency = 1 }):Play()
		Debris:AddItem(ring, 1.1)
	end)
end

-- the whole payoff: pan to the cookie -> chips rain back in -> shake + shockwave -> fireworks -> camera back
local function cinematicFinish(onReveal)
	local cam = Workspace.CurrentCamera
	if not (cam and cookie and cookie.Parent) then
		onReveal()
		local at = (player.Character and player.Character:GetPivot().Position + Vector3.new(0, 12, 0))
		if at then launchFireworks(at) end
		winBanner()
		return
	end

	local cf, size = boundsOf(cookie)
	local center   = cf.Position

	-- frame the cookie from the player's side so the pan never swings behind them
	local charPos = (player.Character and player.Character:GetPivot().Position) or (center + Vector3.new(0, 20, 60))
	local away = (charPos - center) * Vector3.new(1, 0, 1)
	away = (away.Magnitude > 1) and away.Unit or Vector3.new(0, 0, 1)
	local dist   = math.max(size.X, size.Z) * 1.5 + 36
	local camCF  = CFrame.lookAt(center + away * dist + Vector3.new(0, size.Y * 0.6 + 16, 0), center)

	local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	cam.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(cam, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = camCF }):Play()

	-- t=1.0s : the chocolate comes home
	task.delay(1.0, function()
		onReveal()                                   -- chips drop in one by one and pop solid
		-- the rings + shake hit when the FIRST chip actually lands (0.42s into its drop)
		shockwave(center, size, 0.42, Color3.fromRGB(255, 228, 170))
		shockwave(center, size, 0.54, Color3.fromRGB(255, 170, 90))

		-- 0.7s of decaying screenshake, driven off the framed CFrame (pan tween is done by now)
		task.wait(0.42)
		local SHAKE = 0.7
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local left = SHAKE - (os.clock() - t0)
			if left <= 0 or cam.CameraType ~= Enum.CameraType.Scriptable then
				conn:Disconnect()
				if cam.CameraType == Enum.CameraType.Scriptable then cam.CFrame = camCF end
				return
			end
			local m = (left / SHAKE) ^ 2 * 3.0
			cam.CFrame = camCF
				* CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
				* CFrame.Angles(0, 0, (math.random() - 0.5) * m * 0.012)
		end)
	end)

	-- the last chip lands ~1.9s in -> celebrate after it
	task.delay(2.0, function() launchFireworks(center + Vector3.new(0, size.Y * 0.5 + 6, 0)) end)
	task.delay(2.2, winBanner)

	-- t=5.0s : give the camera back
	task.delay(5.0, function()
		cam.CameraType = Enum.CameraType.Custom
		if humanoid then cam.CameraSubject = humanoid end
	end)
end

local function completeQuest()
	if delivered then return end
	delivered = true
	_G.cookieQuestComplete = true -- unlocks the island-3 Cookie Stand
	refreshBanner()
	-- let her line read during the 1s camera pan, then clear it right before the slam
	if npcHead then task.delay(0.95, function() hideBubble(npcHead) end) end
	cinematicFinish(restoreChocolates)
	if _G.NotifyCenter then pcall(function() _G.NotifyCenter.push({ text = "\xF0\x9F\x8D\xAA You fixed the Giant Cookie!", color = STROKE }) end) end
	print("[CookieQuest] complete -- Giant Cookie fixed")
end

-- ============================================================================
-- NPC PERSONALITY -- flavor lines per pickup + a hint toward the next chunk
-- ============================================================================
-- every live (uncollected) chunk registers here so the NPC can point at one
local liveChunks = {}   -- [model] = Vector3 position

-- rotating pickup lines: never the same one twice in a row, cycles the whole list
local CHUNK_LINES = {
	"Ooh, that one's still warm!",
	"Straight from the batter, that one!",
	"Careful now -- no nibbling!",
	"Perfect. That one goes right in the middle.",
	"You're better at this than the gingerbread men!",
	"Ha! I dropped that one weeks ago.",
	"That's the good chocolate. The expensive stuff.",
	"Oh I've been looking for that one!",
}
local lineOrder, linePos = {}, 0
local function nextLine()
	if linePos >= #lineOrder then    -- reshuffle-ish: rotate the deck by a step so runs differ
		lineOrder = {}
		for i = 1, #CHUNK_LINES do lineOrder[i] = CHUNK_LINES[((i + collected * 3) % #CHUNK_LINES) + 1] end
		linePos = 0
	end
	linePos += 1
	return lineOrder[linePos]
end

-- describe roughly where the nearest uncollected chunk is (compass + height)
local function nextHint()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local from = (hrp and hrp.Position) or (cookie and (boundsOf(cookie)).Position)
	if not from then return nil end
	local best, bestD
	for model, pos in pairs(liveChunks) do
		if model.Parent then
			local d = (pos - from).Magnitude
			if not bestD or d < bestD then best, bestD = pos, d end
		else
			liveChunks[model] = nil
		end
	end
	if not best then return nil end

	local delta = best - from
	local flat  = Vector3.new(delta.X, 0, delta.Z)
	local ns    = (delta.Z < 0) and "north" or "south"
	local ew    = (delta.X > 0) and "east"  or "west"
	local dir   = (math.abs(delta.X) > math.abs(delta.Z) * 1.6) and ew
		or (math.abs(delta.Z) > math.abs(delta.X) * 1.6) and ns
		or (ns .. "-" .. ew)

	if flat.Magnitude < 45 then
		if delta.Y > 18 then return "One's right above you -- look UP!" end
		if delta.Y < -18 then return "One's right below you somewhere!" end
		return "You're standing near one right now... sniff around!"
	end
	if delta.Y > 25 then return ("Try the %s side -- and up high!"):format(dir) end
	if delta.Y < -25 then return ("Try the %s side, down low."):format(dir) end
	return ("Try looking %s of here."):format(dir)
end

-- ============================================================================
-- THE CHIP PRY PANEL IS GONE (island 3 is "Feed the Monster" now)
-- ============================================================================
-- It was a modal with PRY_CLICKS taps, no timer, no fail state and no rising ceiling:
-- identical clicks per chunk, thirty across the quest at its original tuning, and its own
-- header conceded the thing was "only ever in the way" of the chase. Chunks are not pried
-- out of scenery any more -- the monster ate them, and he coughs one up for every bait
-- cookie you put down, so the pressure comes from HIM standing over you, not a tap counter.
--
-- monsterDistance() and pryOpen went with it (the panel's bail-out watcher was the only
-- caller). PRY_CLICKS / PRY_MONSTER_BAIL are removed from CONFIG for the same reason.

-- ============================================================================
-- CHUNK COLLECTIBLES -- hide the "chunk" brick, spawn a shiny chocolate chunk
-- ============================================================================
-- ===== ONE CHUNK PER SPOT, FOREVER =====
-- ⚠ DO NOT GO BACK TO KEYING THIS BY INSTANCE. It was `seen[d] = true` on the Instance itself,
-- which looks right and is not: island3 streams, and a part that streams out and back in is a
-- BRAND NEW INSTANCE with the same name at the same place. The old key pointed at a destroyed
-- object, the scan below saw an unseen part, and it spawned another chunk on top of the one you
-- had already taken -- roughly every forty seconds, forever. The 16 Aug playtest log shows it:
-- six chunks at boot, then (7)(8) at 19:12:17, (9)(10) at 19:12:54, (11)(12) at 19:13:36.
--
-- THE SPOT IS THE IDENTITY, not the part that happens to be sitting on it. These are anchored
-- hand-placed markers, so a rounded position is stable across any amount of streaming. One stud
-- of rounding is far finer than the gap between two markers and far coarser than any float drift.
local chunkTaken = {}    -- [spotKey] = true once collected -- never spawns again this session
local function spotKey(d)
	local ok, pos = pcall(function()
		return d:IsA("Model") and d:GetPivot().Position or d.Position
	end)
	if not (ok and pos) then return nil end
	return ("%d,%d,%d"):format(math.round(pos.X), math.round(pos.Y), math.round(pos.Z))
end

-- ============================================================================
-- FEED THE MONSTER -- what the chunk hunt is now
-- ============================================================================
-- It used to be: find a chunk, open a five-tap panel with no timer and no fail state, repeat
-- six times, while a monster you could always outrun made noise in the background. Thirty
-- identical clicks, and the one genuinely tense thing on the island -- the chase -- was
-- something the quest worked AROUND rather than with.
--
-- Now the monster IS the quest, and the reason is in the fiction: he ate the chocolate. You
-- cannot fight him and you cannot outsmart him, but he is greedy, so you can BUY him. Each
-- marker is a bait spot; dropping a bait cookie publishes _G.chocoLure, which pulls him off
-- your back (see the lure branch in ChocolateMonster_AllInOne) and walks him over to eat --
-- and a fed monster coughs one chunk straight back up.
--
-- The loop that makes: sprint to the next spot with him on you -> drop bait -> he breaks off
-- -> you get a few seconds of quiet to collect the chunk -> he comes back. The bait is a tool
-- for managing the chase, so every drop is a real decision about where you want him standing.
-- (`baitLeft` lives up in STATE with `collected`: the objective banner reads it and sits ~700
--  lines above here, and a Lua local is invisible above its own declaration -- declared here
--  it would resolve to a nil GLOBAL in the banner and throw on the first refresh.)

local function spawnChunk(src, idx, key)
	-- src is the user's "chunk" marker: a BasePart, or a Model containing one.
	-- It is a BAIT SPOT now: the chunk that appears here is coughed up, not pried loose.
	local part = src:IsA("BasePart") and src or src:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end
	local pos = part.Position
	-- hide the source marker (block or model) -> it's just a position anchor
	if src:IsA("Model") then
		for _, p in ipairs(src:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.Anchored = true end end
	else
		src.Transparency = 1; src.CanCollide = false; src.CanQuery = false; src.Anchored = true
	end

	-- THE BAIT SPOT: a flat, faintly glowing plate on the ground. It is not a collectible --
	-- it is a place you may choose to put a cookie down, so it reads as a marked spot rather
	-- than as loot (which is what the old bobbing chunk read as, on a marker you had not
	-- earned yet).
	local model = Instance.new("Model"); model.Name = "BaitSpot" -- NOT "chunk", so the scanner can't self-match
	local base = CFrame.new(pos + Vector3.new(0, 0.2, 0))
	local main = mkPart({ Name = "Plate", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 5.5, 5.5), Color = Color3.fromRGB(255, 226, 170),
		Material = Enum.Material.Neon, Transparency = 0.55, CanQuery = true })
	main.CFrame = base * CFrame.Angles(0, 0, math.rad(90)); main.Parent = model; model.PrimaryPart = main
	local glow = Instance.new("PointLight"); glow.Color = Color3.fromRGB(255, 200, 110); glow.Brightness = 1.1; glow.Range = 10; glow.Parent = main
	model.Parent = Workspace
	liveChunks[model] = main.Position   -- so the NPC can hint toward the nearest one

	-- the plate breathes so it reads as live; it does NOT bob (it is on the floor)
	task.spawn(function()
		local t = idx * 0.7
		while model.Parent do
			t += 0.06
			main.Transparency = 0.5 + math.sin(t) * 0.12
			task.wait(0.05)
		end
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drop Bait"; prompt.ObjectText = "Bait Spot"; prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = COLLECT_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = main

	local done = false
	-- the reward half, unchanged -- it just runs after the pry now instead of on the tap
	local function award()
		if done then return end
		done = true
		-- this SPOT is spent. Marked before anything else so a chunk that streams back in
		-- during the pickup animation still cannot re-arm it.
		if key then chunkTaken[key] = true end
		collected += 1
		liveChunks[model] = nil
		refreshBanner()
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = p.Size * 1.5, Transparency = 1 }):Play() end
		end
		Debris:AddItem(model, 0.4)

		-- the NPC calls out with a flavor line (heard anywhere on the island via the banner)
		local line
		if collected >= TOTAL then line = ("That's all %d! Bring them to me -- let's fix that cookie!"):format(TOTAL)
		else line = nextLine() end
		if npcHead then
			showBubble(npcHead, (collected >= TOTAL) and line or ("%s  (%d/%d)"):format(line, collected, TOTAL), false)
		end
		flashBanner(("\xF0\x9F\x8D\xAB %s  %d/%d"):format(line, collected, TOTAL), 3)

		-- ...then, a beat later, nudges you toward the next one
		if collected < TOTAL then
			task.delay(3.2, function()
				if delivered or collected >= TOTAL then return end
				local hint = nextHint()
				if hint then flashBanner("\xF0\x9F\x8D\xAB " .. hint, 3) end
			end)
		end
	end

	prompt.Triggered:Connect(function()
		if done then return end
		-- the realm banner, not this quest's own strip: "you have not taken this job" is the same
		-- sentence on every island, so it goes where a player already watches for news. The local
		-- strip stays as the fallback if DoneCommand (which owns _G.questLocked) has not loaded.
		if not questAccepted then
			if _G.questLocked then
				pcall(_G.questLocked, "the Cookie Repair",
					"\xF0\x9F\x8D\xAA Talk to the Candy NPC first -- she hands out the job!")
			else
				flashBanner("\xF0\x9F\x8D\xAA Talk to the Candy NPC first!", 2.5)
			end
			return
		end
		-- ONE BAIT DOWN AT A TIME. Two lures would fight over _G.chocoLure and the monster would
		-- pinball between them; and the basket is finite, so a second drop is also a wasted cookie.
		if _G.chocoLure then
			flashBanner("\xF0\x9F\x8D\xAA There's already a cookie down -- let him get to it!", 2.5)
			return
		end
		if baitLeft <= 0 then
			flashBanner("\xF0\x9F\x8D\xAA Out of bait! Go and see the Candy NPC.", 2.5)
			return
		end
		prompt.Enabled = false
		baitLeft -= 1
		refreshBanner()

		-- the cookie on the plate: what he is coming for
		local bait = mkPart({ Name = "BaitCookie", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 3.0, 3.0), Color = Color3.fromRGB(214, 168, 108),
			Material = Enum.Material.SmoothPlastic, CanQuery = false })
		bait.CFrame = base * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
		bait.Parent = Workspace
		for i = 1, 5 do
			local chip = mkPart({ Name = "Chip", Size = Vector3.new(0.42, 0.3, 0.42), Color = CHOC })
			local a = (i / 5) * math.pi * 2
			chip.CFrame = bait.CFrame * CFrame.new(0.3, math.cos(a) * 0.9, math.sin(a) * 0.9)
			chip.Parent = bait
		end
		sparkleAt(bait.Position)

		-- HE COMES. The monster script watches this global; it drops whatever it was chasing.
		_G.chocoLure = bait.Position
		flashBanner("\xF0\x9F\x8D\xAA Bait's down -- he's coming for it! Stand back.", 3)
		if npcHead then showBubble(npcHead, "That's it -- let him smell it!", false) end

		-- ...and when he reaches it, he eats and brings a chunk back up.
		_G.chocoLureEaten = function()
			_G.chocoLureEaten = nil
			if bait.Parent then
				for _, p in ipairs(bait:GetChildren()) do
					if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
				end
				TweenService:Create(bait, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.5, 0.4, 0.4) }):Play()
				Debris:AddItem(bait, 0.4)
			end
			sparkleAt(pos + Vector3.new(0, 2, 0))
			flashBanner("\xF0\x9F\x8D\xAB GULP -- and up comes a chunk! Grab it, quick!", 3)

			-- the coughed-up chunk: the old pickup prop, but taken with one instant press.
			-- No panel. The monster is standing right there and will be hunting again in a
			-- second, so the pressure comes from HIM, not from a tap counter.
			local cm = Instance.new("Model"); cm.Name = "ChocoPickup"; cm.Parent = Workspace
			local cbase = CFrame.new(pos + Vector3.new(0, 1.3, 0))
			local cmain = mkPart({ Name = "Choco", Size = Vector3.new(1.7, 1.0, 1.7), Color = CHOC,
				Material = Enum.Material.SmoothPlastic, Reflectance = 0.06, CanQuery = true })
			cmain.CFrame = cbase; cmain.Parent = cm; cm.PrimaryPart = cmain
			local ctop = mkPart({ Name = "ChocoTop", Size = Vector3.new(1.1, 0.7, 1.1), Color = CHOC_HI,
				Material = Enum.Material.SmoothPlastic })
			ctop.CFrame = cbase * CFrame.new(0.2, 0.6, -0.15) * CFrame.Angles(0, math.rad(20), 0); ctop.Parent = cm
			local chl = Instance.new("Highlight"); chl.FillTransparency = 1
			chl.OutlineColor = Color3.fromRGB(255, 210, 120); chl.OutlineTransparency = 0.2
			chl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; chl.Adornee = cmain; chl.Parent = cm
			local cglow = Instance.new("PointLight"); cglow.Color = Color3.fromRGB(255, 200, 110)
			cglow.Brightness = 1.6; cglow.Range = 10; cglow.Parent = cmain
			liveChunks[cm] = cmain.Position
			task.spawn(function()
				local b, t = cm:GetPivot(), idx * 0.7
				while cm.Parent do
					t += 0.06
					cm:PivotTo(b * CFrame.new(0, math.sin(t) * 0.35, 0) * CFrame.Angles(0, t * 0.5, 0))
					task.wait(0.03)
				end
			end)

			local gp = Instance.new("ProximityPrompt")
			gp.ActionText = "Grab"; gp.ObjectText = "Chocolate Chunk"; gp.HoldDuration = 0
			gp.MaxActivationDistance = COLLECT_DISTANCE; gp.RequiresLineOfSight = false; gp.Parent = cmain
			gp.Triggered:Connect(function()
				if done then return end
				gp.Enabled = false
				liveChunks[cm] = nil
				liveChunks[model] = nil
				for _, p in ipairs(cm:GetDescendants()) do
					if p:IsA("BasePart") then
						TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
							{ Size = p.Size * 1.5, Transparency = 1 }):Play()
					end
				end
				Debris:AddItem(cm, 0.4)
				-- the spot is spent: plate off, so the island shows what is left to do
				if model.Parent then
					TweenService:Create(main, TweenInfo.new(0.4), { Transparency = 1 }):Play()
					Debris:AddItem(model, 0.5)
				end
				award()
			end)
		end
	end)
end

-- ============================================================================
-- NPC DIALOGUE (accept the quest; deliver when every chunk is back)
-- ============================================================================
local function questPages()
	if delivered then
		return {
			"Thank you! The Giant Cookie is whole again! \xF0\x9F\x8D\xAA",
			"The Cookie Stand's open. You earned it.",
		}
	end
	if collected >= TOTAL then
		return { ("All %d! You beautiful genius!"):format(TOTAL), "Hand them over. I'll fix the Cookie..." }
	end
	if questAccepted then
		local pages = { ("You've got %d of %d chunks back."):format(collected, TOTAL),
			("Drop bait on a glowing plate. (%d left)")
				:format(baitLeft) }
		local hint = nextHint()
		if hint then pages[#pages + 1] = hint end
		return pages
	end
	return {
		"Disaster! That MONSTER ate my Giant Cookie's chocolate!",
		"Never wrestle it off him. He's greedy...",
		("Take %d bait cookies for the glowing plates."):format(TOTAL),
		"He drops a chunk -- grab it!",
	}
end

local function wireNPC(head)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = COLLECT_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = head

	local pages, index = nil, 0
	local watching = false
	local function closeDialogue() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end
	local function startWatcher()
		if watching then return end
		watching = true
		task.spawn(function()
			while index ~= 0 do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp or (hrp.Position - head.Position).Magnitude > COLLECT_DISTANCE then closeDialogue(); break end
				task.wait(0.25)
			end
			watching = false
		end)
	end

	prompt.Triggered:Connect(function()
		if index == 0 then pages = (_G.capBubble and _G.capBubble(questPages())) or questPages() end
		index += 1
		if not pages or index > #pages then closeDialogue(); return end
		if index == 2 then
			if not questAccepted then
				questAccepted = true
				_G.cookieQuestStarted = true
				baitLeft = TOTAL          -- the basket of bait cookies comes with the job
				refreshBanner()
			end
			-- deliver: reading past page 1 of the "you found them all" state fixes the cookie.
			-- show her last line, hand the dialogue off, and let the cinematic take over.
			if collected >= TOTAL and not delivered then
				showBubble(head, pages[index], true)
				prompt.ActionText = "Talk"; index = 0; pages = nil
				completeQuest()
				return
			end
		end
		local last = index >= #pages
		-- no "[E] ..." badge in the bubble: the ProximityPrompt IS the E prompt, and the page
		-- count rides its ActionText instead of a second floating HUD over the NPC's head
		showBubble(head, pages[index], true, nil)
		prompt.ActionText = last and "Close" or ("Continue  (%d/%d)"):format(index, #pages)
		startWatcher()
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then closeDialogue() end end)
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	-- cookie first (its position disambiguates which "Candy Npc" is the island-3 one)
	cookie = pollFor(findCookie, 45)
	if cookie then
		-- StreamingEnabled: island3 is far from spawn, so the cookie's PARTS stream in AFTER the
		-- model itself appears. Wait for them before splitting (else it reads as 0 parts = no split).
		pollFor(function() return firstBasePart(cookie) end, 45)
		task.wait(1)
		hideChocolates()
		-- keep hiding: island3 streams in piecemeal, so chips can arrive after this first pass
		task.spawn(function()
			while not delivered do
				task.wait(3)
				if delivered then break end
				hideChocolates(true)
			end
		end)
		-- twinkle the empty spots one at a time so you can see where chocolate is missing
		task.spawn(function()
			local i = 0
			while not delivered do
				task.wait(1.6)
				if delivered then break end
				if #sockets > 0 then
					i = (i % #sockets) + 1
					local s = sockets[i]
					if s and s.Parent then sparkleAt(s.Position) end
				end
			end
		end)
	else warn("[CookieQuest] no 'GiantCookie' found in Workspace") end
	local cookiePos = cookie and ((boundsOf(cookie)).Position)

	npcHead = pollFor(function() return findNPCNear(cookiePos) end, 45)
	if npcHead then wireNPC(npcHead); wantVisible = true
	else
		-- SHE IS NOT OPTIONAL HERE EITHER. completeQuest() is reachable from exactly one place --
		-- page 2 of her "you found them all" dialogue -- so without her you can collect all six
		-- chunks and then have nowhere to take them, and island3's Cookie Stand (locked behind
		-- _G.cookieQuestComplete in Shop_AllInOne) never opens. Same 180s late watch island1 and
		-- the crystal mine use; the build below sets questBuilt_cookie either way, so the retainer
		-- will not re-run this one for us.
		warn("[CookieQuest] no 'Candy Npc' found near the cookie in 45s -- still watching for her")
		task.spawn(function()
			npcHead = pollFor(function() return findNPCNear(cookiePos) end, 180)
			if npcHead then
				wireNPC(npcHead); wantVisible = true; refreshBanner()
				print("[CookieQuest] Candy Npc streamed in late -- wired")
			else
				warn("[CookieQuest] no 'Candy Npc' near the cookie after 180s -- the six chunks can be "
					.. "collected but not handed in, so island3's Cookie Stand stays locked. Check island3 "
					.. "has a model named exactly 'Candy Npc' with a Head, near the GiantCookie.")
			end
		end)
	end

	-- chunks STREAM IN as the player nears island3 (StreamingEnabled) -- island3 is far
	-- from the island-1 spawn, so a one-time scan finds nothing. Keep scanning and spawn a
	-- chocolate chunk for each new "chunk" brick as it appears.
	-- Anything called "chunk" that is not near the cookie belongs to another island, so leave
	-- it alone. With no cookie found yet we take nothing: better a late chunk than island 11's
	-- mine turned into a chocolate box.
	local function nearCookie(d)
		local at = cookie and (cookie:IsA("Model") and cookie:GetPivot().Position or cookie.Position)
		if not at then return false end
		local ok, pos = pcall(function()
			return d:IsA("Model") and d:GetPivot().Position or d.Position
		end)
		return ok and pos and (pos - at).Magnitude <= CHUNK_RANGE
	end

	task.spawn(function()
		local seen, idx, firstDone = {}, 0, false
		local lastIdx, settleAt = 0, nil   -- see the SETTLE-DOWN note at the bottom of this loop
		while true do
			local found = 0
			for _, d in ipairs(Workspace:GetDescendants()) do
				-- match any BasePart/Model whose name CONTAINS "chunk" (chunk, Chunk1, "Chunk 3", ...)
				-- but NEVER the cookie's own chips -- those may be named Chunk1..Chunk6 too, and they
				-- belong to the cookie (hidden until the reveal), not to the island hunt.
				local inCookie = cookie and (d == cookie or d:IsDescendantOf(cookie))
				if not inCookie and (d:IsA("BasePart") or d:IsA("Model")) and string.find(string.lower(d.Name), CHUNK_NAME, 1, true)
					and nearCookie(d) then
					local key = spotKey(d)
					-- a spot already collected is not counted either: `found` feeds the
					-- settle-down target below, and counting a taken spot would keep the
					-- target at 6 when only 5 are left to find.
					if key and not chunkTaken[key] then
						found += 1
						if not seen[key] then
							seen[key] = true; idx += 1; spawnChunk(d, idx, key)
							print(("[CookieQuest] chunk '%s' spawned (%d) at spot %s"):format(d.Name, idx, key))
						end
					end
				end
			end
			if not firstDone then firstDone = true; print(("[CookieQuest] scan: %d instance(s) with '%s' in the name"):format(found, CHUNK_NAME)) end

			-- SETTLE-DOWN. The rescan above copes with island3 streaming in late, but if the
			-- world simply has fewer 'chunk' parts than TOTAL, the quest can never be handed
			-- in -- you'd hunt forever for a 6th chunk that does not exist. So once the count
			-- has stopped moving for a while, the target drops to what actually exists.
			if idx > 0 and idx ~= lastIdx then lastIdx = idx; settleAt = os.clock() + 45 end
			if idx > 0 and idx < TOTAL and settleAt and os.clock() >= settleAt then
				warn(("[CookieQuest] only %d chunk(s) exist on island3 -- target lowered from %d to %d")
					:format(idx, TOTAL, idx))
				TOTAL = idx
				settleAt = nil
				refreshBanner()
			end
			task.wait(3)
		end
	end)

	refreshBanner()
	print(("[CookieQuest] ready -- cookie %s, %d chocolate hidden, NPC %s (chunks spawn as island3 streams in)"):format(
		cookie and "found" or "MISSING", #chocolates, npcHead and "wired" or "MISSING"))
	-- RETAINER SIGNAL: the quest reached the end of its build with its world objects up. QuestRetainer
	-- watches this flag; anything still false once its island has streamed in gets force-streamed and
	-- re-run. It is set HERE, at the ready print, not at the top of the file -- a quest that bailed
	-- early on a missing marker must NOT look built. See QuestRetainer.client.luau.
	_G.questBuilt_cookie = true
end)

-- ============================================================================
-- /complete -- test command: instantly finish the cookie quest (fix + firework)
-- ============================================================================
local function onCommand(msg)
	-- DEV ONLY. QuestDevGate publishes this; read at command time so load order cannot matter,
	-- and nil (gate not up yet) refuses. Without it any player could type their way to the whole realm.
	if not _G.questDevOK then return end
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	-- only completes when you're standing on island3 (near ITS NPC). If that NPC isn't found
	-- yet, do nothing -- never complete on a "maybe", or /complete on another island fires this.
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (npcHead and npcHead.Parent and hrp) then return end
	if (hrp.Position - npcHead.Position).Magnitude > BANNER_RANGE then return end
	questAccepted = true; collected = TOTAL; refreshBanner(); completeQuest()
	print("[CookieQuest][TEST] /complete -- Giant Cookie fixed")
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
