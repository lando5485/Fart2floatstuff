--======================================================================
-- CookieRepairQuest_AllInOne.client.lua  (LocalScript)
--======================================================================
-- ISLAND-3 QUEST: "Fix the Giant Cookie."
--   * The GiantCookie you built in Studio already has chocolate chips in it. On
--     load this script HIDES them (leaving faint dents), so the cookie shows up
--     bare -- its chocolate has gone missing.
--       -> name those chips choc/chip/chunk/morsel in Studio for exact control;
--          otherwise they're auto-detected (small + dark parts on the big biscuit).
--   * 6 blocks named "chunk" are hidden around island3 -> each becomes a shiny
--     chocolate chunk you collect (E). Per-player (client-side).
--   * The Candy Npc on island3 gives the quest + receives the chunks. Collect all
--     6, bring them to her, and the cinematic plays: camera pans to the cookie,
--     the chocolates rain back into their dents and pop solid, shockwave + shake,
--     fireworks, and a "You fixed the Giant Cookie!" banner.
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
local TOTAL            = 6
local CHUNK_NAME       = "chunk"                       -- brick name (case-insensitive)
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
	if delivered then return "\xF0\x9F\x8D\xAA You fixed the Giant Cookie!" end
	if not questAccepted then return "\xF0\x9F\x8D\xAA Go talk to the Candy NPC on Island 3!" end
	if collected >= TOTAL then return "\xF0\x9F\x8D\xAA Bring the chunks to the Candy NPC!" end
	return ("\xF0\x9F\x8D\xAB Find the chocolate chunks!  %d/%d"):format(collected, TOTAL)
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
-- sockets[i] belongs to chocolates[i] -- both are appended in lockstep by hideChocolates()
local function restoreChocolates()
	for i, rec in ipairs(chocolates) do
		local p = rec.part
		if p and p.Parent then
			task.delay((i - 1) * 0.09, function()
				if not (p and p.Parent) then return end
				local land  = p.CFrame
				local flyer = mkPart({ Name = "ChocoFlyIn", Size = rec.size, Color = CHOC,
					Material = Enum.Material.SmoothPlastic, Reflectance = 0.06 })
				flyer.CFrame = land * CFrame.new(0, 26 + i * 3, 0) * CFrame.Angles(0, math.rad(i * 47), math.rad(15))
				flyer.Parent = Workspace

				local drop = TweenService:Create(flyer, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = land })
				drop.Completed:Connect(function()
					flyer:Destroy()
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
				end)
				drop:Play()
			end)
		end
	end
	-- safety sweep: clear any dent whose chip never made it back (streamed out, deleted, etc.)
	task.delay(#chocolates * 0.09 + 0.9, function()
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

local function winBanner()
	local g = Instance.new("ScreenGui"); g.Name = "CookieWin"; g.ResetOnSpawn = false; g.DisplayOrder = 20; g.IgnoreGuiInset = true; g.Parent = PlayerGui
	local f = Instance.new("Frame"); f.AnchorPoint = Vector2.new(0.5,0.5); f.Position = UDim2.new(0.5,0,0.42,0); f.Size = UDim2.new(0,0,0,90)
	f.BackgroundColor3 = FILL; f.Parent = g
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,18); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = STROKE; s.Thickness = 4; s.Parent = f
	local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1,1); l.Font = Enum.Font.FredokaOne
	l.TextColor3 = TEXTC; l.TextScaled = true; l.Text = "\xF0\x9F\x8D\xAA You fixed the Giant Cookie! \xF0\x9F\x8E\x86"; l.Parent = f
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0,24); pad.PaddingRight = UDim.new(0,24); pad.Parent = l
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 34; sz.Parent = l
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0,620,0,90) }):Play()
	task.delay(5, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.delay(0.5, function() g:Destroy() end)
	end)
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
-- CHUNK COLLECTIBLES -- hide the "chunk" brick, spawn a shiny chocolate chunk
-- ============================================================================
local function spawnChunk(src, idx)
	-- src is the user's "chunk" marker: a BasePart, or a Model containing one
	local part = src:IsA("BasePart") and src or src:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end
	local pos = part.Position
	-- hide the source marker (block or model) -> it's just a position anchor
	if src:IsA("Model") then
		for _, p in ipairs(src:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = 1; p.CanCollide = false; p.CanQuery = false; p.Anchored = true end end
	else
		src.Transparency = 1; src.CanCollide = false; src.CanQuery = false; src.Anchored = true
	end

	local model = Instance.new("Model"); model.Name = "ChocoPickup" -- NOT "chunk", so the scanner can't self-match
	local base = CFrame.new(pos + Vector3.new(0, 1.3, 0))
	local main = mkPart({ Name = "Choco", Size = Vector3.new(1.7, 1.0, 1.7), Color = CHOC, Material = Enum.Material.SmoothPlastic, Reflectance = 0.06, CanQuery = true })
	main.CFrame = base; main.Parent = model; model.PrimaryPart = main
	local top = mkPart({ Name = "ChocoTop", Size = Vector3.new(1.1, 0.7, 1.1), Color = CHOC_HI, Material = Enum.Material.SmoothPlastic })
	top.CFrame = base * CFrame.new(0.2, 0.6, -0.15) * CFrame.Angles(0, math.rad(20), 0); top.Parent = model
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = Color3.fromRGB(255, 210, 120); hl.OutlineTransparency = 0.2; hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = main; hl.Parent = model
	local glow = Instance.new("PointLight"); glow.Color = Color3.fromRGB(255, 200, 110); glow.Brightness = 1.4; glow.Range = 8; glow.Parent = main
	model.Parent = Workspace
	liveChunks[model] = main.Position   -- so the NPC can hint toward the nearest one

	task.spawn(function()
		local b = model:GetPivot(); local t = idx * 0.7
		while model.Parent do t += 0.06; model:PivotTo(b * CFrame.new(0, math.sin(t) * 0.35, 0) * CFrame.Angles(0, t * 0.5, 0)); task.wait(0.03) end
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"; prompt.ObjectText = "Chocolate Chunk"; prompt.HoldDuration = 0
	prompt.MaxActivationDistance = COLLECT_DISTANCE; prompt.RequiresLineOfSight = false; prompt.Parent = main

	local done = false
	prompt.Triggered:Connect(function()
		if done then return end
		if not questAccepted then flashBanner("\xF0\x9F\x8D\xAA Talk to the Candy NPC first!", 2.5); return end
		done = true
		collected += 1
		liveChunks[model] = nil
		refreshBanner()
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = p.Size * 1.5, Transparency = 1 }):Play() end
		end
		Debris:AddItem(model, 0.4)

		-- the NPC calls out with a flavor line (heard anywhere on the island via the banner)
		local line
		if collected >= TOTAL then line = "That's all 6! Bring them to me -- let's fix that cookie!"
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
	end)
end

-- ============================================================================
-- NPC DIALOGUE (accept the quest; deliver when all 6 are collected)
-- ============================================================================
local function questPages()
	if delivered then
		return {
			"Thank you! The Giant Cookie is whole again! \xF0\x9F\x8D\xAA",
			"Go on, the Cookie Stand's open now. You earned it.",
		}
	end
	if collected >= TOTAL then
		return { "All 6! You beautiful genius!", "Hand them over -- let me fix the Giant Cookie..." }
	end
	if questAccepted then
		local pages = { "Still missing some chunks!", ("Found: %d of %d."):format(collected, TOTAL) }
		local hint = nextHint()
		if hint then pages[#pages + 1] = hint end
		return pages
	end
	return {
		"Disaster! Look at my Giant Cookie -- all the chocolate is GONE!",
		"Every last chunk popped out and rolled off across the island.",
		"Find all 6 and bring them back to me.",
		"Do that, and I'll put my cookie -- and my Cookie Stand -- back together!",
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
		if index == 0 then pages = questPages() end
		index += 1
		if not pages or index > #pages then closeDialogue(); return end
		if index == 2 then
			if not questAccepted then questAccepted = true; _G.cookieQuestStarted = true; refreshBanner() end
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
		local footer = last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages)
		showBubble(head, pages[index], true, footer)
		prompt.ActionText = last and "Close" or "Continue"
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
	else warn("[CookieQuest] no 'Candy Npc' found near the cookie") end

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
		while true do
			local found = 0
			for _, d in ipairs(Workspace:GetDescendants()) do
				-- match any BasePart/Model whose name CONTAINS "chunk" (chunk, Chunk1, "Chunk 3", ...)
				-- but NEVER the cookie's own chips -- those may be named Chunk1..Chunk6 too, and they
				-- belong to the cookie (hidden until the reveal), not to the island hunt.
				local inCookie = cookie and (d == cookie or d:IsDescendantOf(cookie))
				if not inCookie and (d:IsA("BasePart") or d:IsA("Model")) and string.find(string.lower(d.Name), CHUNK_NAME, 1, true)
					and nearCookie(d) then
					found += 1
					if not seen[d] then
						seen[d] = true; idx += 1; spawnChunk(d, idx)
						print(("[CookieQuest] chunk '%s' spawned (%d)"):format(d.Name, idx))
					end
				end
			end
			if not firstDone then firstDone = true; print(("[CookieQuest] scan: %d instance(s) with '%s' in the name"):format(found, CHUNK_NAME)) end
			task.wait(3)
		end
	end)

	refreshBanner()
	print(("[CookieQuest] ready -- cookie %s, %d chocolate hidden, NPC %s (chunks spawn as island3 streams in)"):format(
		cookie and "found" or "MISSING", #chocolates, npcHead and "wired" or "MISSING"))
end)

-- ============================================================================
-- /complete -- test command: instantly finish the cookie quest (fix + firework)
-- ============================================================================
local function onCommand(msg)
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
