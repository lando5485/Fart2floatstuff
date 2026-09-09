--======================================================================
-- CandyTrollBridge_AllInOne.client.lua  (LocalScript, per-player)
--======================================================================
-- ISLAND 1 -- "BRIDGE TOLL": the Candy Troll, his bridge, and TROLLLAND.
--
-- A troll sits on island 1's bridge and will not let you across until you have paid the
-- toll. The toll is a job, picked at random from four, and the far side -- TROLLLAND -- is
-- his park: step into it before you have paid and he throws you straight back out.
--
--   TOLLS (one is rolled per player, per attempt):
--     LOLLIPOP  he lost his favourite lolly. It is hidden; a jingle gets louder as you
--               close on it, so you FIND it by ear rather than by following an arrow.
--     BRIDGE    three planks of his bridge are broken. Each one is hammered back in on a
--               tap-on-the-swing beat -- the same rhythm island 14's chainsaw uses.
--     CANDY     he is hungry and names ONE candy by colour. Several are lying about; bring
--               the wrong one and he tells you so. It is an identify-and-choose, not a fetch.
--     DRINK     he is thirsty. The cup is enormous: you carry it SLOWLY and it slops as you
--               go. Spill it and you go back and refill.
--
-- ⚠ WHY FOUR DIFFERENT VERBS UNDER FOUR FETCH-SHAPED FICTIONS.
-- Written literally, all four tolls are "find the thing, carry it back" -- which is the exact
-- loop that made the gumball quest repetitive: four trips that differ only in what the thing
-- is called. The fictions are kept word for word; what changes is what your HANDS do. Search
-- by ear, hammer to a beat, identify and choose, carry something awkward. Same troll, same
-- four jobs, four different games.
--
-- ⚠ THE RESTRICTION IS PER-PLAYER FOR FREE, and that is why this is a LocalScript.
-- Trollland's barrier, the warning and the throw-out all live on the client, so they are only
-- ever applied to the player who has not paid. One player finishing their toll cannot open
-- the park for anybody else, and nobody needs a server remote to keep that true.
--
-- WHAT THE WORLD PROVIDES (all optional -- every one of these is BUILT if missing, the same
-- convention the rest of the realm uses: a block gives POSITION, the prop is built on it):
--   troll       -- where the Candy Troll stands. A model is adopted as-is; a part is a marker.
--   trollland   -- a block covering the restricted park. Its FOOTPRINT is the zone.
--   bridge      -- island 1's existing bridges (ShowBridges.server.luau reveals them)
--   lolly / candy / drink -- optional hand-placed spots for the toll props
--======================================================================

-- ============================================================================
-- ⚠ DISABLED -- ISLAND 1 IS BACK ON THE GUMBALL HUNT
-- ============================================================================
-- The Bridge Toll replaced CandyGumballQuest_AllInOne on island 1; that has been reverted,
-- and the Gumball Hunt is live again (its own RETIRED flag is gone). EXACTLY ONE of the two
-- may run: both build props on island 1 and both claim the same ladder rung by setting
-- `_G.candyQuestComplete`, which is what unlocks tier 2 / flight.
--
-- To bring the troll back: set TROLL_DISABLED = false HERE and re-add the retire guard at the
-- top of CandyGumballQuest_AllInOne. Never leave both live.
--
-- The guard also claims the build tie-break and sweeps the troll's folder, so a DUPLICATE copy
-- of this script baked into the place file (the boot log's NOT-IN-MANIFEST line) stands down
-- and any troll it already built is removed -- otherwise the old troll would still be standing
-- on the bridge next to the gumball machine.
local TROLL_DISABLED = true
if TROLL_DISABLED then
	_G.__candyTrollBuild = math.huge
	_G.trollTollPaid = true   -- nothing gates on it any more; true == no invisible barrier
	local function sweep()
		for _, f in ipairs(workspace:GetChildren()) do
			if f.Name == "CandyTrollLocal" then f:Destroy() end
		end
	end
	sweep()
	task.delay(5, sweep)      -- in case a baked-in duplicate builds after this copy runs
	task.delay(15, sweep)
	print("[Troll] DISABLED -- island 1 runs the Gumball Hunt (CandyGumballQuest_AllInOne).")
	return
end

local Players         = game:GetService("Players")
local Workspace       = game:GetService("Workspace")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")
local RunService      = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- ONE COPY ONLY
-- ============================================================================
-- Rojo ADDS, it never overwrites, so a copy of this script baked into the place file runs
-- ALONGSIDE the synced one -- and this realm boot audit already names this script:
--   [SECURITY] NOT-IN-MANIFEST | StarterPlayer.StarterPlayerScripts.CandyTrollBridge_AllInOne
-- Two copies build two trolls at the same bridge, interleaved, which looks exactly like ONE
-- troll that has come apart: limbs from the older design floating beside the newer one, and
-- pieces the older design never had (nose, tusks, legs) apparently "missing".
--
-- BUILD is the tie-break. The higher build wins, sweeps the older folder, and the loser stands
-- down. Raise it whenever the troll geometry changes.
local BUILD = 43
if (_G.__candyTrollBuild or 0) >= BUILD then
	warn(("[Troll] STANDING DOWN -- build %d is already running in this client and this copy "
		.. "is build %d. A DUPLICATE of this script is baked into the place file: delete "
		.. "StarterPlayerScripts.CandyTrollBridge_AllInOne in Studio and republish.")
		:format(_G.__candyTrollBuild, BUILD))
	return
end
if _G.__candyTrollBuild then
	warn(("[Troll] an OLDER copy (build %d) already built a troll -- sweeping its parts and "
		.. "taking over. That copy is baked into the place file: delete it in Studio.")
		:format(_G.__candyTrollBuild))
end
_G.__candyTrollBuild = BUILD
for _, f in ipairs(Workspace:GetChildren()) do
	if f.Name == "CandyTrollLocal" then f:Destroy() end
end

print("[Troll] >>> VERSION toll-v4 (welded Motor6D rig, rounded-box build, "
	.. "build 43: HINGED JAW that moves when he speaks -- and the idle loop no longer dies "
	.. "on a nil `stand`, which is what froze him solid) loaded <<<")

-- DECLARED FALSE AT BOOT, not left nil -- same rule as every other quest flag in this realm.
_G.trollTollPaid = false

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_NAME   = "island1"
local TROLL_NAME    = "troll"
local LAND_NAME     = "trollland"
local BRIDGE_NAME   = "bridge"
local SIGN_NAME     = "signplacement"
local SPOT_NAME     = "gumball"   -- the retired Gumball Hunt's hand-placed spots

-- Filled at boot from every part named 'gumball' on island1. The retired quest scattered its
-- orbs on these, they are already spaced sensibly around the island, and they beat a computed
-- ring: a ring lands props in walls, off ledges and out over the water, which is exactly what
-- has needed raycast-guarding at every turn.
local spots = {}

--[[ n distinct marker positions, or {} if none were placed. ]]
local function takeSpots(n)
	local pool, out = {}, {}
	for _, v in ipairs(spots) do pool[#pool + 1] = v end
	for i = #pool, 2, -1 do
		local j = math.random(i); pool[i], pool[j] = pool[j], pool[i]
	end
	for i = 1, math.min(n, #pool) do out[i] = pool[i] end
	return out
end
local TALK_RANGE    = 14
local ISLAND_RANGE  = 600

-- HOW TROLLLAND PUNISHES A GATECRASHER.
--   "knockback" -- thrown back out the way you came, unhurt. The default, deliberately.
--   "reset"     -- your character resets.
-- ⚠ KNOCKBACK IS THE DEFAULT ON PURPOSE. Island 1 is the TUTORIAL island: it is the first
-- ground a new player stands on, and killing somebody for walking the wrong way in their
-- first minute teaches them that the game is unfair rather than that the park is closed. A
-- throw-out says the same thing, is funnier, and costs the player nothing. Flip to "reset"
-- if you want it harsher -- everything else about the restriction is identical.
local PUNISH        = "knockback"
local THROW_BACK    = 70          -- studs/sec he throws you at
local THROW_UP      = 42
local WARN_COOLDOWN = 2.5         -- seconds between warnings, so one wall-hug is not a spam

-- ⚠ THE TROLL STANDS IN HIS OWN RESTRICTED ZONE, AND YOU MUST BE ABLE TO REACH HIM.
-- A 'trollland' block drawn over the whole park will usually cover the BRIDGE too -- and the
-- trolls are built at the bridge mouths, which put each of them inside the very area they
-- were throwing people out of. You got launched before you could ever open his dialogue, so
-- the toll could not be started, so the zone could never open: a deadlock.
--
-- Every troll now carries a safe bubble this wide that the barrier ignores completely. Walking
-- up, talking and handing in always work; the punishment only starts once you are past him and
-- properly into the park.
local TROLL_SAFE    = 30          -- studs around each troll where you are never thrown out

-- toll tuning
local PLANKS_NEEDED = 3           -- FIX MY BRIDGE: broken planks to hammer back in
local PLANK_TAPS    = 4           -- taps to seat one plank (tap ON the swing beat)
local LOLLY_HOT     = 90          -- studs at which the lolly's jingle becomes audible
local DRINK_SPEED   = 0.55        -- walkspeed multiplier while carrying the giant cup
local DRINK_SPILL   = 8           -- seconds of running before the cup slops empty

-- palette (candy realm house colours)
local PAL = {
	SKIN   = Color3.fromRGB(150, 214, 168),
	SKIN_D = Color3.fromRGB(112, 178, 132),
	CREAM  = Color3.fromRGB(255, 246, 232),
	PINK   = Color3.fromRGB(232, 96, 110),
	PINK_L = Color3.fromRGB(255, 196, 214),
	CHOC   = Color3.fromRGB(92, 54, 28),
	WOOD   = Color3.fromRGB(178, 126, 78),
	WOOD_D = Color3.fromRGB(120, 78, 44),
	GOLD   = Color3.fromRGB(226, 176, 88),
	RED    = Color3.fromRGB(226, 60, 84),
	MINT   = Color3.fromRGB(150, 222, 200),
	PURPLE = Color3.fromRGB(186, 132, 214),
}

-- ============================================================================
-- HELPERS
-- ============================================================================
local function norm(s) return (tostring(s or ""):lower():gsub("[%s_%-]", "")) end

local function mk(props)
	-- Class lets a caller ask for a WedgePart instead of a Part. A wedge is the only way to get
	-- a genuine flat triangle: faking one with a squashed ball is what made the troll's ears
	-- read as two more bumps on the side of his head.
	local cls = props.Class; props.Class = nil
	local p = Instance.new(cls or "Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat local r = fn(); if r then return r end; task.wait(0.5) until os.clock() - t0 > (timeout or 45)
	return fn()
end

local function firstBasePart(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function hrpOf()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function humOf()
	local c = player.Character
	return c and c:FindFirstChildWhichIsA("Humanoid")
end

local function banner(text, colour)
	if _G.NotifyCenter and _G.NotifyCenter.push then
		pcall(function() _G.NotifyCenter.push({ text = text, color = colour or PAL.PINK }) end)
	else
		print("[Troll] " .. tostring(text))
	end
end

-- ============================================================================
-- STATE
-- ============================================================================
-- ⚠ ONE TROLL PER BRIDGE. Island 1 has TWO parts named "bridge" (ShowBridges.server.luau
-- reveals them both), so it gets two trolls -- a toll booth on an unguarded second crossing
-- is not a toll booth. They are BROTHERS and they share one park: pay either one and
-- Trollland opens, because word travels. The other then steps aside too and says so.
--
-- ONE TOLL AT A TIME, GLOBALLY. `active` is the troll whose job you are currently doing, so
-- walking to the other brother mid-job gets you told off rather than handed a second task --
-- two live tolls would mean two props in one pair of hands and an objective line that cannot
-- say what you are meant to be doing.
local island, landPart, landCF, landHalf
local trolls = {}      -- { { model=, head=, name=, rig=, chest=, ... }, ... }

-- Every troll's "Talk" prompt, so they can be switched off as a group.
-- ⚠ WHY: his prompt lives on his HEAD, and he stands in the middle of the bridge -- which is
-- exactly where the broken planks are. Roblox shows whichever prompt is nearest, so while you
-- are hammering, his Talk prompt and the plank's Hammer prompt swap under the cursor as you
-- shuffle: you go to hit a plank and open his dialogue instead. Muting his prompt for the
-- duration means the only E on that bridge is the one you want.
local trollPrompts = {}
local function setTrollPrompts(on)
	for _, pr in ipairs(trollPrompts) do
		if pr.Parent then pr.Enabled = on end
	end
end
local active = nil     -- the troll record whose toll is running, or nil
local function firstHead() return trolls[1] and trolls[1].head end
local toll        = nil        -- "lolly" | "bridge" | "candy" | "drink"
local tollActive  = false      -- a toll has been handed out and is not finished
local paid        = false      -- THIS player has paid; Trollland is open to them
local carrying    = nil        -- the prop currently in hand ("lolly" | "candy" | "drink")
-- ⚠ DECLARED HERE, WITH THE REST OF THE STATE, NOT NEXT TO giveHeld() FURTHER DOWN.
-- A Lua local is invisible ABOVE its own declaration, so any code earlier in the file that
-- said `heldModel` was silently reading a nil GLOBAL instead -- no error, just a value that is
-- always nil. giveHeld() and the toll props below are the readers.
local heldModel   = nil
local props       = {}         -- everything this quest built, for cleanup
local planksLeft  = 0
local wantCandy   = nil        -- the candy colour he asked for, on the CANDY toll
local lastWarn    = 0
local folder = Instance.new("Folder"); folder.Name = "CandyTrollLocal"; folder.Parent = Workspace

local function track(p) props[#props + 1] = p; return p end

-- ============================================================================
-- THE OBJECTIVE LINE -- rides the realm banner like every other quest here
-- ============================================================================
local objGui = Instance.new("ScreenGui")
objGui.Name = "TrollTollObjective"       -- the "...Objective" suffix ObjectiveBannerBridge mirrors
objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7; objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 540, 0, 52); objFrame.BackgroundColor3 = PAL.CREAM
objFrame.Visible = false; objFrame.Parent = objGui
Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0, 16)
do local s = Instance.new("UIStroke"); s.Color = PAL.PINK; s.Thickness = 3; s.Parent = objFrame end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1)
objLabel.Font = Enum.Font.FredokaOne; objLabel.TextColor3 = Color3.fromRGB(80, 30, 60)
objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 22; sz.Parent = objLabel
	local pd = Instance.new("UIPadding")
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = objLabel
end

local TOLL_LINE = {
	lolly  = "\xF0\x9F\x8D\xAD Find the Troll's lollipop -- listen for the jingle, it gets louder!",
	bridge = "\xF0\x9FA\xAA\xB5 Hammer the broken planks back into the bridge",
	candy  = "\xF0\x9F\x8D\xAC Bring the Troll the candy he asked for",
	drink  = "\xF0\x9F\xA5\xA4 Carry the Troll's giant drink back -- slowly, it slops!",
}
TOLL_LINE.bridge = "\xF0\x9F\xAA\xB5 Hammer the broken planks back into the bridge"

local objText = ""
local function setObjective(t) objText = t; objLabel.Text = t end

--[[ The subtitle under each troll's name tracks the state of HIS toll.
     A tag that reads "Bridge Troll" forever is a label; one that reads "WANTS: THE PINK CANDY"
     over the brother who set the job, and "TOLL PAID" once you are through, answers "where do
     I stand with this one" from across the bridge without opening anything. It also
     disambiguates the two brothers at a glance, which matters most on the second bridge. ]]
local TAG_SUB = { lolly = "LOST HIS LOLLIPOP", bridge = "WANTS HIS BRIDGE FIXED",
	candy = "WANTS A CANDY", drink = "WANTS A DRINK" }

local function refreshTags()
	for _, t in ipairs(trolls) do
		if t.tagSub then
			if paid then
				t.tagSub.Text = "TOLL PAID"
				t.tagSub.TextColor3 = PAL.GOLD
			elseif tollActive and active == t then
				t.tagSub.Text = TAG_SUB[toll] or "WANTS SOMETHING"
				t.tagSub.TextColor3 = PAL.CREAM
			elseif tollActive then
				-- the OTHER brother, while his sibling's job is live
				t.tagSub.Text = "WAIT YOUR TURN"
				t.tagSub.TextColor3 = PAL.PINK_L
			else
				t.tagSub.Text = "PAY THE TOLL"
				t.tagSub.TextColor3 = PAL.CREAM
			end
		end
	end
end

local function refreshObjective()
	refreshTags()
	if paid then
		setObjective("\xF0\x9F\x8D\xAD Toll paid -- Trollland is open. Cross whenever you like!")
	elseif not tollActive then
		setObjective("\xF0\x9F\x8C\x89 Talk to the Candy Troll at the bridge to pay the toll")
	elseif toll == "bridge" then
		setObjective(("\xF0\x9F\xAA\xB5 Hammer the broken planks back in:  %d left")
			:format(planksLeft))
	elseif toll == "candy" then
		setObjective(("\xF0\x9F\x8D\xAC The Troll wants the %s candy -- find that one and bring it")
			:format(wantCandy and wantCandy.name or "right"))
	else
		setObjective(TOLL_LINE[toll] or objText)
	end
end

local flashTok = 0
local function flash(text, secs)
	flashTok += 1; local mine = flashTok
	objLabel.Text = text
	task.delay(secs or 2.5, function() if mine == flashTok then objLabel.Text = objText end end)
end

-- the line only shows while you are on island 1
task.spawn(function()
	while true do
		local vis = false
		local hrp, ref = hrpOf(), firstHead() or landPart
		if hrp and ref and ref.Parent then
			vis = (hrp.Position - ref.Position).Magnitude <= ISLAND_RANGE
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- SPEECH BUBBLE -- island 1's Candy Npc pattern, so the troll talks like a local
-- ============================================================================
local function hideBubble(a) local p = a:FindFirstChild("SpeechBubble"); if p then p:Destroy() end end

local function showBubble(a, text, persist)
	hideBubble(a)
	local bb = Instance.new("BillboardGui"); bb.Name = "SpeechBubble"; bb.Adornee = a
	bb.Size = UDim2.new(0, 330, 0, 150); bb.StudsOffset = Vector3.new(0, 6.5, 0)
	bb.AlwaysOnTop = true; bb.MaxDistance = 140
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = PAL.CREAM
	f.BackgroundTransparency = 0.05; f.BorderSizePixel = 0; f.Parent = bb
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = PAL.PINK; st.Thickness = 2; st.Parent = f
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = f
	local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1, 1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne; l.Text = text; l.TextColor3 = Color3.fromRGB(74, 30, 58)
	l.TextScaled = true; l.TextWrapped = true; l.Parent = f
	Instance.new("UITextSizeConstraint", l).MaxTextSize = 22
	bb.Parent = a
	-- HE TALKS WITH HIS MOUTH. Stamp whichever troll owns this head and animateTroll chatters
	-- his jaw for as long as the line takes to read -- so the bubble is him SAYING it rather
	-- than a card appearing over a statue. Length comes off the text, so a one-word bark is a
	-- snap of the jaw and a full haggle is a mouthful.
	for _, tr in ipairs(trolls) do
		if tr.head == a and tr.rig then
			tr.rig.talkUntil = os.clock() + math.clamp(#tostring(text) * 0.045, 0.7, 6)
		end
	end
	if not persist then
		task.delay(8, function() if bb and bb.Parent == a then bb:Destroy() end end)
	end
	return bb
end

-- ============================================================================
-- THE CANDY TROLL -- adopted from Studio, or built here
-- ============================================================================
-- Extra yaw TRIM only. The bridge trolls are auto-turned to stand ACROSS the deck (see the
-- placement block further down), because "blocking the path" is a fact about the bridge, not a
-- fixed number. Set this to 180 if a troll ends up facing off the far end.
-- The TROLLLAND arch over each bridge mouth. Off: the signs carry the wording, and at the
-- troll's current size the arch read as the biggest thing on the island.
local SHOW_ARCH = false

-- ⚠ THE ONLY THING THAT SETS WHICH WAY A TROLL FACES. Nothing else rotates him.
-- He inherits his bridge's own rotation and then turns by this much, so the same world gives
-- the same facing on every single boot. Two earlier passes tried to be clever here -- one read
-- the bridge's long axis, one aimed him at the island centre -- and between them the troll
-- turned a different way nearly every run, which is not a fix, it is a moving target. If he
-- faces the wrong way, change this ONE number: 0 / 90 / 180 / 270.
-- 270 = the previous 180 plus a 90 quarter-turn COUNTER-CLOCKWISE seen from above.
-- (Roblox yaw is counter-clockwise about +Y, so counter-clockwise ADDS.)
local TROLL_YAW = 270

-- Shoulders to about bridge-rail height. Every length in buildTroll is quoted at scale 1 and
-- multiplied here, so the proportions the art notes settled stay put and only the size moves.
-- ⚠ 0.62, NOT 1.45. The build-14 audit measured the finished troll at 19.5 studs tall --
-- nearly FOUR times a player, not the 1.5x this was supposed to be. Every art note since then
-- ("no legs", "arms missing", "slab with a face") was written looking up at a giant from below,
-- where the skirt hides the legs and the head is above your camera. The build coordinates grew
-- as detail was added and the scale was never re-derived. 13.5 build studs x 0.62 = ~8.4.
local TROLL_SCALE = 0.62

-- ============================================================================
-- THE TROLL -- built the way the island-3 chocolate monster is built
-- ============================================================================
-- SCALE: a stocky guard, head top ~7.6 studs = about 1.5x a player. The first pass was ~24
-- studs to the hat and towered over the bridge like a boss monster; everything below is sized
-- off the player, not off the bridge.
--
-- CONSTRUCTION follows ChocolateMonster_AllInOne: every piece is an OVERLAPPING part carrying
-- an offset from one of four pivots, and one loop writes them all each frame. Parts overlap on
-- purpose -- that is what makes shoulders, hips and neck read as connected mass rather than a
-- stack of separate boxes. Nothing is welded and nothing is parented into a sub-model.
--
-- FOUR PIVOTS, quoted in the FEET frame (y = 0 is the sole of the foot, -Z is forward):
local ROOT_Y = 4.10   -- torso centre: everything in the "body" group hangs off this
local NECK_Y = 6.10   -- the head group turns about here, so he can watch you
local SHO_Y  = 5.20   -- shoulders: the arm groups swing about these
local SHO_X  = 2.05

-- MINT / SAGE, saturated. The first pass used the shared PAL.SKIN, a pale cyan that washed out
-- completely against the sky at altitude -- he read as grey-blue, not green.
local SAGE   = Color3.fromRGB(108, 184, 114)
local SAGE_D = Color3.fromRGB(78, 146, 86)
local SAGE_HI= Color3.fromRGB(142, 214, 148)   -- lit faces, as the monster uses CHOC_HI
local INK    = Color3.fromRGB(28, 26, 34)
local NOSE_C = Color3.fromRGB(124, 198, 122)
local PASTEL = {
	Color3.fromRGB(255, 176, 202), Color3.fromRGB(198, 168, 246),
	Color3.fromRGB(255, 214, 236), Color3.fromRGB(226, 190, 255),
	Color3.fromRGB(255, 236, 168), Color3.fromRGB(180, 226, 255),
}

--[[ Writes text onto one face of a part. Used by the staff panel and every sign board. ]]
local function faceText(part, face, text, colour, maxSize, cx, cy, font)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face; sg.CanvasSize = Vector2.new(cx or 420, cy or 120)
	sg.LightInfluence = 0.15; sg.Adornee = part; sg.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -10, 1, -8); l.Position = UDim2.new(0, 5, 0, 4)
	l.BackgroundTransparency = 1; l.TextScaled = true
	l.Font = font or Enum.Font.LuckiestGuy   -- heavier display face: readable further out
	l.TextColor3 = colour or Color3.fromRGB(255, 244, 224)
	l.TextStrokeTransparency = 0; l.TextStrokeColor3 = Color3.fromRGB(60, 30, 46)
	l.Text = text; l.Parent = sg
	Instance.new("UITextSizeConstraint", l).MaxTextSize = maxSize or 44
	return l
end

--[[ Builds one troll. Returns (model, headPart, rig).

     `rig` is what animateTroll drives: { root, parts = { {part, grp, off, lid}, ... } }. Each
     entry's `off` is measured from ITS GROUP'S pivot, so the loop is one multiply per part and
     the head can turn without the body following. ]]
local function buildTroll(at)
	-- ⚠ ROTATE FIRST, so every offset below is in the troll's own frame and the whole figure --
	-- staff, hat, pivots and all -- turns as one.
	at = at * CFrame.Angles(0, math.rad(TROLL_YAW), 0)

	local m = Instance.new("Model"); m.Name = "CandyTroll"; m.Parent = folder
	local rig = { parts = {} }

	-- ⚠ EVERY PART'S HOME IS ONE CFRAME, MEASURED FROM `at`, AND IT IS STORED.
	-- This used to subtract the group's pivot here and re-add it in the animation loop -- two
	-- places computing the same transform, which is exactly how they came to disagree. The loop
	-- forgot the body group's (0, ROOT_Y, 0) term, so on the first animated frame the torso,
	-- legs, feet, skirt, belt and pouch all dropped 4 studs through the deck while the head and
	-- arms stayed up: the body "came apart". The group now only says WHICH PIVOT ROTATES the
	-- part, never where it lives, so the two can no longer drift.
	local S = TROLL_SCALE

	-- ⚠ WHY THIS EXISTS. Everything here is placed by a loop, and loops make things that look
	-- MADE BY A LOOP: twelve skirt panels at exactly 30 degrees apart, ten brim dots on a
	-- perfect circle, and a body mirrored to the millimetre down its centre line. Nothing in
	-- the world is that even, and the evenness is most of what reads as machine-made.
	--
	-- jr(i, spread) is a cheap deterministic hash -> -spread..+spread. DETERMINISTIC MATTERS:
	-- math.random would re-roll every join, so the troll's ears and skirt would change shape
	-- each time you loaded in, which reads as instability rather than character. Seeded from
	-- his own world position, so the two brothers are irregular in DIFFERENT ways and each is
	-- the same on every boot.
	local seed = math.abs(at.Position.X * 7.31 + at.Position.Z * 13.17) % 1000
	local function jr(i, spread)
		local v = math.sin(seed * 0.0173 + i * 12.9898) * 43758.5453
		return ((v - math.floor(v)) * 2 - 1) * (spread or 1)
	end
	-- his hat does not sit straight, and it sits differently on each brother
	local hx, hz, hroll = jr(90, 0.2), jr(91, 0.16), jr(92, 5)
	local function P(grp, props2, x, y, z, rot)
		props2.Parent = m
		if props2.Size then
			-- big pieces CAST SHADOWS. mk() turns CastShadow off for every prop in this file
			-- (right for confetti and sprinkles), but an 8-stud figure whose torso throws no
			-- shadow reads as pasted onto the bridge rather than standing on it. Volume is the
			-- test so the gumballs and flecks stay cheap.
			local sz = props2.Size
			if props2.CastShadow == nil and sz.X * sz.Y * sz.Z >= 3 then
				props2.CastShadow = true
			end
			props2.Size = sz * S
		end
		local p = mk(props2)
		-- a rot may carry a translation too (Angles * new(d,0,0)); scale that in its OWN frame
		-- so the piece stays put relative to the part it decorates.
		if rot then
			local r = rot - rot.Position
			rot = r * CFrame.new((r:Inverse() * rot.Position) * S)
		end
		local off = CFrame.new(x * S, y * S, (z or 0) * S) * (rot or CFrame.new())
		p.CFrame = at * off
		rig.parts[#rig.parts + 1] = { part = p, grp = grp, off = off }
		return track(p)
	end
	local function ball(grp, colour, sx2, sy, sz, x, y, z, rot)
		return P(grp, { Color = colour, Shape = Enum.PartType.Ball,
			Size = Vector3.new(sx2, sy, sz) }, x, y, z, rot)
	end

	-- ======================================================================================
	-- ROUNDED BOXES AND CYLINDERS -- not spheres, and not hard cubes.
	-- Build 14 went all-Ball to escape the "slab with a face" look and over-corrected into a
	-- cactus: a pile of spheres has no flat planes, so nothing reads as a chest, a shin or a
	-- shoulder, and every overlapping joint ball looked like a growth stuck on the outside.
	-- The rule now: BLOCKS for the structure (torso, head, jaw, limbs, skirt, belt), soft
	-- vertical BEVEL CYLINDERS down their corners, and Balls kept ONLY for things that really
	-- are round -- the nose, the eyeballs, the gumballs, the frosting.
	-- ⚠ No joint balls. Nothing is added to the OUTSIDE of a limb just to bridge a gap; parts
	-- overlap instead, which is what the bumps were badly imitating.
	-- ======================================================================================
	local function bevel(grp, colour, w, d, y, h)
		-- ⚠ INSET by the cylinder's radius. Centred ON the corner edge, half of each cylinder
		-- protrudes diagonally past both faces -- four vertical ridges of corner piping, which
		-- is the opposite of rounding. Tucked in by r, the cylinder is tangent to both faces
		-- and only its curve shows.
		local r = 0.275
		for _, cx in ipairs({ -1, 1 }) do
			for _, cz in ipairs({ -1, 1 }) do
				P(grp, { Color = colour, Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(h, 0.55, 0.55) },
					cx * (w * 0.5 - r), y, cz * (d * 0.5 - r),
					CFrame.Angles(0, 0, math.rad(90)))
			end
		end
	end

	-- ---- LEGS: square thighs, shins and feet, all below the skirt hem at 1.95 ------------
	for _, sx in ipairs({ -1, 1 }) do
		P("body", { Color = SAGE_D, Size = Vector3.new(1.85, 2.4, 1.85) }, sx * 0.98, 2.7, 0)
		P("body", { Color = SAGE_D, Size = Vector3.new(1.55, 2.1, 1.55) }, sx * 0.98, 1.15, 0)
		P("body", { Color = SAGE_D, Size = Vector3.new(1.9, 0.75, 2.5) }, sx * 0.98, 0.38, -0.42)
		P("body", { Color = PAL.CREAM, Size = Vector3.new(1.5, 0.4, 0.65) }, sx * 0.98, 0.34, -1.4)
		-- BOOT CUFF: a leather band where the foot meets the shin, so the leg does not just
		-- taper into a slab. Reads as a boot rather than a bare green stump.
		P("body", { Color = PAL.WOOD_D, Size = Vector3.new(1.78, 0.46, 1.78) }, sx * 0.98, 0.85, 0)
	end

	-- ---- TORSO: a rounded box, wider at the shoulders than it is tall, flat front ---------
	local body = P("body", { Color = SAGE, Size = Vector3.new(5.1, 3.5, 4.0),
		CanCollide = true }, 0, ROOT_Y, 0)
	bevel("body", SAGE, 5.1, 4.0, ROOT_Y, 3.5)
	P("body", { Color = SAGE_HI, Size = Vector3.new(4.6, 0.9, 3.6) }, 0, 5.6, 0)   -- lit shoulder shelf
	-- THE HUNCH. A guard who stands to attention is a soldier; a troll stoops. The hump sits
	-- BEHIND the shoulder line and rises above it, so from the side his back curves up into
	-- his neck instead of meeting it at a right angle -- and it fills the flat plate the
	-- shoulder shelf otherwise leaves when you walk round him.
	ball("body", SAGE, 4.0, 1.9, 2.4, 0, 5.5, 0.95)
	ball("body", SAGE_D, 3.0, 1.1, 1.5, 0, 5.95, 1.25)                         -- shaded crest
	-- HIS TAKINGS, slung on the far hip. The chest by the bridge is where a paid toll GOES;
	-- this is what he carries around, and it says "this one collects things" before he has
	-- said a word. Hung off the back strap that was already crossing his shoulders.
	ball("body", PAL.WOOD, 1.9, 2.1, 1.5, -1.85, 4.05, 1.85)
	ball("body", PAL.WOOD_D, 1.5, 0.5, 1.2, -1.85, 5.05, 1.85)                 -- cinched neck
	for i = 1, 3 do
		ball("body", PASTEL[(i % #PASTEL) + 1], 0.42, 0.42, 0.42,
			-1.85 + jr(i + 800, 0.5), 5.35 + jr(i + 810, 0.2), 1.85 + jr(i + 820, 0.35))
	end
	P("body", { Color = PAL.CREAM, Size = Vector3.new(0.16, 0.9, 0.16) }, -1.85, 5.5, 1.6,
		CFrame.Angles(math.rad(18), 0, math.rad(12)))                          -- a stray stick

	-- SPINE PLATES down the back, shrinking as they go. Five is enough to read as a ridge;
	-- more would be a stegosaurus.
	for i = 1, 5 do
		local f = (i - 1) / 4
		ball("body", SAGE_D, 1.05 - f * 0.42, 0.42 - f * 0.12, 0.7 - f * 0.22,
			jr(i + 600, 0.12), 5.3 - i * 0.52, 2.0 - f * 0.22)
	end
	-- A CREAM RUFF at the collar. The neck cylinder met the torso in a bare butt-joint that
	-- read as a seam; the ruff covers it and gives the head something to sit on.
	P("body", { Color = PAL.CREAM, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 2.5, 2.5) }, 0, 5.78, 0, CFrame.Angles(0, 0, math.rad(90)))
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		P("body", { Color = PAL.CREAM, Size = Vector3.new(0.55, 0.34, 0.55) },
			math.cos(a) * 1.15, 5.92, math.sin(a) * 1.15, CFrame.Angles(0, -a, math.rad(22)))
	end

	-- a short NECK: a slim cylinder, and the only thing between a 5.1-wide torso and the head
	P("body", { Color = SAGE_D, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.0, 1.45, 1.45) }, 0, NECK_Y, 0, CFrame.Angles(0, 0, math.rad(90)))

	-- WARTS. Five on the body, jr-placed so each brother wears his own set and keeps it
	-- between boots. A troll without warts is a goblin.
	for i = 1, 5 do
		local a = jr(i + 500, math.pi)
		local wy = 3.6 + (i / 5) * 2.1 + jr(i + 510, 0.3)
		local wr = 0.22 + math.abs(jr(i + 520, 0.12))
		ball("body", SAGE_D, wr, wr * 0.8, wr,
			math.cos(a) * 2.45, wy, math.sin(a) * 1.95 - 0.2)
	end

	-- ---- SKIRT: ragged purple cloth panels, sprinkle flecks, hem clear of the knees -------
	for i = 1, 12 do
		-- angle, radius, length and hang all jittered: a hem that tore is not a hem that was
		-- cut, and twelve identical panels on an exact circle is the latter
		local a = (i / 12) * math.pi * 2 + jr(i, 0.08)
		local rad = 2.05 + jr(i + 40, 0.13)
		local px, pz = math.cos(a) * rad, math.sin(a) * rad
		local yaw = CFrame.Angles(0, -a + math.pi * 0.5, 0) * CFrame.Angles(jr(i + 60, 0.07), 0, 0)
		local drop = jr(i + 80, 0.16)
		P("body", { Color = PAL.PURPLE,
			Size = Vector3.new(1.3 + jr(i + 20, 0.16), 1.5 + jr(i + 30, 0.3), 0.42) },
			px, 2.72 + drop, pz, yaw)
		P("body", { Color = PAL.PURPLE, Size = Vector3.new(0.68, 0.68, 0.42) },
			px, 2.02 + drop * 1.4, pz,
			yaw * CFrame.Angles(0, 0, math.rad(45 + jr(i + 50, 14))))          -- torn point
		for f = 1, 2 do
			P("body", { Color = PASTEL[((i + f) % #PASTEL) + 1],
				Size = Vector3.new(0.16, 0.16, 0.5) },
				px, 3.0 - f * 0.42, pz, yaw * CFrame.new((f - 1.5) * 0.5, 0, 0))
		end
		-- one STITCHED PATCH, on a single panel: a troll mends his own skirt badly. Just the
		-- one -- a patch on every panel would read as a pattern instead of as wear.
		if i == 4 then
			P("body", { Color = PAL.PINK, Size = Vector3.new(0.7, 0.7, 0.46) }, px, 2.6, pz,
				yaw * CFrame.Angles(0, 0, math.rad(12)))
			for k = -1, 1 do
				P("body", { Color = PAL.CREAM, Size = Vector3.new(0.12, 0.9, 0.5) },
					px, 2.6, pz, yaw * CFrame.new(k * 0.26, 0, 0) * CFrame.Angles(0, 0, math.rad(12)))
			end
		end
	end

	-- ---- BELT: brown strap, gold-rimmed pink swirl buckle, candy pouch --------------------
	-- tipped 2.5 degrees toward the pouch side: a loaded belt hangs low where the weight is,
	-- and a dead-level strap is one more machined line on an otherwise crooked creature
	P("body", { Color = PAL.WOOD_D, Size = Vector3.new(5.35, 0.85, 4.25) }, 0, 3.2, 0,
		CFrame.Angles(0, 0, math.rad(-2.5)))
	P("body", { Color = PAL.GOLD, Size = Vector3.new(1.55, 1.55, 0.36) }, 0, 3.2, -2.1)
	P("body", { Color = PAL.PINK, Size = Vector3.new(1.15, 1.15, 0.3) }, 0, 3.2, -2.25)
	for k = 0, 3 do
		P("body", { Color = PAL.CREAM, Size = Vector3.new(0.68, 0.15, 0.16) }, 0, 3.2, -2.36,
			CFrame.Angles(0, 0, math.rad(k * 45)) * CFrame.new(0.2, 0, 0))
	end
	P("body", { Color = PAL.WOOD, Size = Vector3.new(1.3, 1.4, 1.0) }, 2.1, 2.8, -1.7)
	P("body", { Color = PAL.WOOD_D, Size = Vector3.new(1.42, 0.3, 1.12) }, 2.1, 3.42, -1.7)
	for i, c in ipairs({ PAL.PINK, PAL.CREAM }) do
		P("body", { Color = c, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.5, 0.32, 0.32) }, 1.9 + i * 0.34, 4.0, -1.7,
			CFrame.Angles(0, 0, math.rad(74 + i * 10)))
	end
	P("body", { Color = PAL.WOOD_D, Size = Vector3.new(0.62, 4.2, 0.28) }, 0, 4.4, 1.95,
		CFrame.Angles(0, 0, math.rad(28)))

	-- ---- ARMS: thick square limbs hanging at the sides, outboard of the torso -------------
	for _, side in ipairs({ { -1, "armL" }, { 1, "armR" } }) do
		local sx, g = side[1], side[2]
		-- the upper arm is the BONE: everything else in the group welds to it.
		rig[g] = P(g, { Color = SAGE, Size = Vector3.new(1.7, 2.7, 1.7) }, sx * 2.95, 4.3, 0)
		bevel(g, SAGE, 1.7, 1.7, 4.3, 2.7)
		-- LEATHER PAULDRON: caps the shoulder, so the arm joins the torso under something
		-- instead of just abutting it, and it widens the top of the silhouette.
		P(g, { Color = PAL.WOOD_D, Size = Vector3.new(2.1, 0.8, 2.0) }, sx * 2.95, 5.45, 0,
			CFrame.Angles(0, 0, math.rad(sx * 9 + jr(sx + 420, 6))))
		P(g, { Color = PAL.WOOD, Size = Vector3.new(1.95, 0.42, 1.85) }, sx * 3.02, 5.85, 0,
			CFrame.Angles(0, 0, math.rad(sx * 14)))
		P(g, { Color = PAL.GOLD, Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34) },
			sx * 3.5, 5.5, -0.7)
		for k, c in ipairs({ PAL.CREAM, PAL.PINK, PAL.PURPLE }) do
			P(g, { Color = c, Size = Vector3.new(1.84, 0.34, 1.84) }, sx * 2.95, 5.2 - (k - 1) * 0.36, 0)
		end
		P(g, { Color = SAGE, Size = Vector3.new(1.5, 2.4, 1.5) }, sx * 3.3, 2.5, 0)
		-- three coarse tufts on the outside of each forearm -- a limb that tapers perfectly
		-- smoothly from cuff to fist is a table leg
		for k = 1, 3 do
			P(g, { Color = SAGE_D, Size = Vector3.new(0.34, 0.62, 0.3) },
				sx * 4.0, 3.2 - k * 0.52, jr(k + 700, 0.3),
				CFrame.Angles(0, 0, math.rad(sx * (28 + k * 6))))
		end
		P(g, { Color = SAGE_D, Size = Vector3.new(1.9, 1.6, 1.9) }, sx * 3.5, 1.35, 0)   -- fist
		for f = -1, 1 do
			P(g, { Color = SAGE_D, Size = Vector3.new(0.42, 0.42, 0.6) },
				sx * 3.5 + f * 0.45, 1.2, -0.9)
		end
	end

	-- ---- HEAD: rounded cube, squared jaw, FLAT pointed ears ------------------------------
	local head = P("head", { Color = SAGE, Size = Vector3.new(3.7, 3.05, 3.05) }, 0, 7.6, 0)
	head.Name = "Head"
	bevel("head", SAGE, 3.7, 3.05, 7.6, 3.05)
	-- ⚠ THE SQUARE JAW IS A BONE. Everything below the mouth line welds to THIS part rather
	-- than to the skull, and a Motor6D at the bottom of this function hinges it off the head,
	-- so he can open his mouth. Anything marked with jawPart() rides it.
	local jaw = P("head", { Color = SAGE_D, Size = Vector3.new(3.3, 1.25, 2.75) }, 0, 6.5, -0.2)
	jaw.Name = "Jaw"
	--[[ tags the piece just built as part of the lower jaw. ]]
	local function jawPart() rig.parts[#rig.parts].jaw = true end
	jawPart()
	-- UNDER-JAW SHADOW. Everything on this troll is lit flat by the realm's permanent
	-- daylight, so nothing reads as overhanging anything. A darker slab tucked beneath the jaw
	-- fakes the occlusion a chin actually casts on a throat, and is the single cheapest thing
	-- that stops the head looking stuck on rather than sitting on.
	P("head", { Color = Color3.fromRGB(58, 112, 66), Size = Vector3.new(2.9, 0.42, 2.4) },
		0, 5.92, -0.15)
	jawPart()
	for _, sx in ipairs({ -1, 1 }) do
		-- FLAT POINTED TRIANGLES, not more lumps: a WedgePart is a true triangle
		-- one ear bigger and cocked further than the other. A face is never mirrored, and
		-- ears are where you notice it first.
		local eg, ea = jr(sx + 300, 0.22), jr(sx + 310, 7)
		P("head", { Class = "WedgePart", Color = SAGE,
			Size = Vector3.new(0.32, 1.9 + eg, 1.5 + eg * 0.5) },
			sx * (2.05 + eg * 0.2), 8.35 + eg * 0.3, jr(sx + 320, 0.1),
			CFrame.Angles(0, sx > 0 and math.pi or 0, math.rad(sx * -16 + ea)))
		-- the pink inner follows the SAME eg/ea jitter as its outer ear -- with a fixed
		-- angle it poked out through the cocked ear's edge on whichever side jittered most
		P("head", { Class = "WedgePart", Color = PAL.PINK_L,
			Size = Vector3.new(0.16, 1.15 + eg * 0.6, 0.9 + eg * 0.3) },
			sx * (1.94 + eg * 0.2), 8.3 + eg * 0.3, jr(sx + 320, 0.1),
			CFrame.Angles(0, sx > 0 and math.pi or 0, math.rad(sx * -16 + ea)))
		-- a SAGE_D ridge under each brow: the black bar alone floated on flat green, and a
		-- heavy brow needs the skull to bulge for it
		P("head", { Color = SAGE_D, Size = Vector3.new(1.35, 0.5, 0.42) }, sx * 0.82, 8.32, -1.5,
			CFrame.Angles(0, 0, math.rad(sx * 24)))
		-- brows of different weight and pitch: one heavier, one cocked
		P("head", { Color = INK,
			Size = Vector3.new(1.15 + jr(sx + 330, 0.13), 0.28 + jr(sx + 340, 0.07), 0.3) },
			sx * 0.82, 8.5 + jr(sx + 350, 0.09), -1.68,
			CFrame.Angles(0, 0, math.rad(sx * 24 + jr(sx + 360, 8))))          -- angry brow
		-- EYE SOCKET: a darker recess behind the eyeball. Without it the whites sat ON the
		-- face like two stickers; set into a shadow they read as eyes in a skull.
		ball("head", SAGE_D, 1.12, 1.16, 0.5, sx * 0.82, 7.9, -1.42)
		ball("head", Color3.new(1, 1, 1), 0.92, 0.96, 0.62, sx * 0.82, 7.9, -1.56)
		-- pupils not perfectly level, and one a shade wider: dead-level eyes look printed
		ball("head", INK, 0.42 + jr(sx + 370, 0.05), 0.44, 0.32,
			sx * 0.82 + jr(sx + 380, 0.05), 7.86 + jr(sx + 390, 0.06), -1.8)   -- pupil
		rig.parts[#rig.parts].pupil = true
		-- the CATCHLIGHT is what makes an eye look wet and alive. One small offset dot.
		ball("head", Color3.new(1, 1, 1), 0.18, 0.18, 0.14, sx * 0.82 + 0.13, 8.0, -1.9)
		-- one tusk longer and more splayed -- the short one reads as chipped
		P("head", { Color = Color3.fromRGB(252, 250, 244),
			Size = Vector3.new(0.34, 1.15 + jr(sx + 400, 0.3), 0.34) },
			sx * 0.66, 6.95 + jr(sx + 400, 0.15), -1.76,
			CFrame.Angles(math.rad(6), 0, math.rad(sx * -8 + jr(sx + 410, 9))))  -- tusk UP
		jawPart()   -- they root in the LOWER jaw, so they swing down with it when he speaks
		-- ⚠ TUCKED UP AND BACK. At y 8.62 x 0.95 tall x 0.66 deep, the OPEN lid enveloped
		-- the brow completely -- the "heavy brows" everyone kept asking for were sitting
		-- inside these boxes. Raised to 8.78 and thinned to 0.5 deep, the open lid hides
		-- above the brow line; the 0.95 blink drop still reaches down over the whole eye.
		local lid = P("head", { Color = SAGE, Size = Vector3.new(0.98, 0.9, 0.5) },
			sx * 0.82, 8.78, -1.48)
		lid.Name = (sx < 0) and "LidL" or "LidR"
		rig.parts[#rig.parts].lid = true
	end
	-- THE MUZZLE: a soft mass behind nose and mouth, proud of the flat face by a third of a
	-- stud. Until now every feature was mounted on one flat plane, which is exactly the look
	-- of a drawn-on face; pushing the lower face forward puts the features on FLESH.
	ball("head", SAGE, 2.0, 1.6, 1.05, 0, 6.85, -1.32)
	ball("head", NOSE_C, 1.25, 1.2, 1.25, 0, 7.35, -1.72)                      -- big round nose
	-- a highlight dot on the nose tip, upper-left -- same job as the eye catchlights: one
	-- bright spot is what turns a green sphere into a round shiny nose
	ball("head", Color3.fromRGB(172, 226, 178), 0.3, 0.26, 0.2, -0.26, 7.7, -2.08)
	-- MOSSY FRINGE poking out under the hat brim. The brim sat on bare skull with a hard line
	-- across it; a ragged fringe breaks that line and reads as hair rather than a lid.
	for i = 1, 9 do
		local a = (i / 9) * math.pi * 2
		P("head", { Color = SAGE_D,
			Size = Vector3.new(0.5, 0.62 + (i % 3) * 0.26 + jr(i + 170, 0.22), 0.42) },
			math.cos(a) * (1.62 + jr(i + 180, 0.1)), 8.82 + jr(i + 190, 0.1),
			math.sin(a) * (1.5 + jr(i + 200, 0.1)),
			CFrame.Angles(0, -a, math.rad(((i % 2 == 0) and 8 or -8) + jr(i + 210, 7))))
	end
	-- THE MOUTH: a dark line with the corners turned DOWN, a lower lip under it, and a hint
	-- of the inside. A single flat bar read as a slot cut in his face.
	P("head", { Color = INK, Size = Vector3.new(1.15, 0.34, 0.3) }, 0, 6.42, -1.8)
	jawPart()
	for _, sx in ipairs({ -1, 1 }) do
		P("head", { Color = INK, Size = Vector3.new(0.34, 0.38, 0.28) }, sx * 0.66, 6.54, -1.78,
			CFrame.Angles(0, 0, math.rad(sx * -30)))
		jawPart()
	end
	-- THE DARK OF HIS MOUTH, and it is welded to the SKULL, not to the jaw. The mouth line is
	-- a bar drawn on the front of the muzzle; drop the jaw with nothing behind it and what
	-- opens up is a strip of bright green cheek, which reads as the face coming apart rather
	-- than as a mouth. This plate sits flush in the muzzle exactly where the bar and the lip
	-- cover it, so it is invisible until they move down off it.
	P("head", { Color = Color3.fromRGB(48, 20, 30), Size = Vector3.new(1.2, 0.5, 0.22) },
		0, 6.3, -1.8)
	ball("head", SAGE_D, 1.05, 0.42, 0.5, 0, 6.14, -1.68)                      -- lower lip
	jawPart()
	-- a chipped lower tooth poking up on ONE side: asymmetry is most of what makes a face
	-- look made rather than mirrored
	P("head", { Color = Color3.fromRGB(240, 234, 220), Size = Vector3.new(0.26, 0.4, 0.22) },
		-0.24, 6.55, -1.92, CFrame.Angles(0, 0, math.rad(8)))
	jawPart()
	-- one wart on the muzzle, off to a side -- the classic troll mark, and one more
	-- asymmetry the mirrored features cannot give
	ball("head", SAGE_D, 0.3, 0.26, 0.3, 0.72 * (jr(530, 1) > 0 and 1 or -1), 6.78, -1.62)

	-- THE UNIBROW: the brows slant up-outward, so their inner ends sit low, at about y 8.27
	-- -- one bar there joins them into a single scowl. Two separate brows are cross; one
	-- connected brow is a TROLL.
	P("head", { Color = INK, Size = Vector3.new(0.6, 0.24, 0.28) }, 0, 8.27, -1.7)

	-- NOSTRILS -- the blush, lower lids and bridge crease that used to accompany them are
	-- gone: on a face this small each was one more competing mark, and the socket shadow
	-- already does the lower lid's framing job.
	for _, sx in ipairs({ -1, 1 }) do
		ball("head", Color3.fromRGB(74, 118, 80), 0.24, 0.2, 0.18, sx * 0.34, 7.05, -2.2)
	end

	-- ---- CUPCAKE HAT: mint brim on the skull, frosting swirl, gumballs (no lolly on top) ---
	P("head", { Color = SAGE, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 4.1, 4.1) }, hx, 9.16, hz,
		CFrame.Angles(0, 0, math.rad(90 + hroll)))
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2 + jr(i + 100, 0.13)
		local r = 1.85 + jr(i + 110, 0.1)
		local d = 0.36 + jr(i + 120, 0.07)
		ball("head", PASTEL[(i % #PASTEL) + 1], d, d, d,
			math.cos(a) * r + hx, 9.16 + jr(i + 130, 0.06), math.sin(a) * r + hz)
	end
	-- the same trick under the hat brim: a thin dark disc so the brim casts onto the skull
	P("head", { Color = Color3.fromRGB(58, 112, 66), Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.22, 3.5, 3.5) }, hx, 8.88, hz,
		CFrame.Angles(0, 0, math.rad(90 + hroll)))
	ball("head", Color3.fromRGB(255, 251, 246), 3.3, 2.2, 3.2,
		hx * 1.5, 10.2, hz * 1.5)   -- frosting dome, sat askew with the brim
	ball("head", Color3.fromRGB(255, 251, 246), 2.1, 1.6, 2.05, hx * 2.2, 11.1, hz * 2.2)
	for i = 1, 12 do
		local a = i * 2.39996
		local r = 1.4 - i * 0.088 + jr(i + 140, 0.12)
		local d = 0.38 + jr(i + 150, 0.09)
		ball("head", PASTEL[(i % #PASTEL) + 1], d, d, d,
			math.cos(a) * r + hx, 9.8 + i * 0.135 + jr(i + 160, 0.08), math.sin(a) * r + hz)
	end
	-- NO LOLLIPOP ON TOP. A cream stick and a 1.5-wide PAL.PINK disc used to sit up at
	-- y 12.7 -- read as a little red circle floating over him, because at that size and
	-- distance the stick vanishes and only the disc is left. The frosting swirl and its
	-- gumballs finish the hat on their own.

	-- ---- STAFF: gripped in the right fist, dead vertical -----------------------------------
	-- ⚠ x = 4.15 AND A 3.9 DISC, BOTH MEASURED. At x 3.55 with a 4.3 disc the sign's inner
	-- edge sat at 1.40 while the hat dome reaches 1.65 and the brim 2.05 -- so the sign was
	-- permanently buried a quarter-stud into his own hat, at rest, before any animation ran.
	-- Moving out and shrinking the disc puts the inner edge at 4.15 - 1.95 = 2.20, clear of
	-- both. The fist moved out to 3.5 with it so the pole is still inside his grip.
	for k = 0, 15 do
		P("armR", { Color = (k % 2 == 0) and Color3.new(1, 1, 1) or PAL.PINK,
			Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.62, 0.48, 0.48) },
			4.15, 0.4 + k * 0.62, -1.1, CFrame.Angles(0, 0, math.rad(90)))
	end
	P("armR", { Color = PAL.PINK, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3.9, 3.9) }, 4.15, 11.6, -1.1, CFrame.Angles(0, math.rad(90), 0))
	for i = 1, 7 do
		P("armR", { Color = PAL.PINK, Size = Vector3.new(0.44, 0.65 + (i % 3) * 0.3, 0.44) },
			4.15 + (i - 4) * 0.5, 9.75, -1.1)
	end
	for i = 1, 8 do
		local a = i * 2.39996
		ball("armR", PASTEL[(i % #PASTEL) + 1], 0.26, 0.26, 0.18,
			4.15 + math.cos(a) * 1.45, 11.6 + math.sin(a) * 1.45, -1.35)
	end
	local panel = P("armR", { Color = PAL.CREAM, Size = Vector3.new(2.85, 1.5, 0.22) },
		4.15, 11.6, -1.38)
	faceText(panel, Enum.NormalId.Front, "PAY THE TOLL!", Color3.fromRGB(214, 38, 46), 110, 320, 165)

	m.PrimaryPart = body

	-- ⚠ THE MODEL IS NOW PHYSICALLY JOINED, NOT 164 PARTS FLOWN IN FORMATION.
	-- Every previous build positioned all 164 parts individually every frame. That works only
	-- while the maths is perfect, and when it was not -- a dropped pivot term in one group --
	-- the body came apart with limbs hanging in the air. Welds make that class of bug
	-- impossible: the ROOT is the only anchored part, everything else is welded to a bone, and
	-- moving the root moves the whole troll whatever the animation does.
	--
	-- Four bones, joined to the root by Motor6D so they can still rotate:
	--   body -> the root itself      head -> the skull      armL / armR -> the upper arms
	local bone = { body = body, head = head, armL = rig.armL, armR = rig.armR }
	for _, e in ipairs(rig.parts) do
		-- a jaw piece welds to the JAW; everything else to its group's bone
		local b = e.jaw and jaw or bone[e.grp]
		-- the two eyelids are deliberately NOT welded: they get their own joints below so they
		-- can still drop. Welding them was a regression -- the blink survived every rebuild
		-- until the rig went over to welds, then silently stopped.
		if b and e.part ~= b and not e.lid and not e.pupil then
			e.part.Anchored = false
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = b; wc.Part1 = e.part; wc.Parent = e.part
		end
	end
	body.Anchored = true

	-- Motor6D: bone.CFrame = root.CFrame * C0 * C1:Inverse(), so C1 is solved from the pose the
	-- part was BUILT in. Rotating the joint later is then C1 = baseC1 * R:Inverse().
	rig.motor = {}
	local function joint(name, b, jx, jy)
		if not b then return end
		b.Anchored = false
		local mo = Instance.new("Motor6D")
		mo.Name = name; mo.Part0 = body; mo.Part1 = b
		mo.C0 = CFrame.new(jx * S, (jy - ROOT_Y) * S, 0)
		mo.C1 = b.CFrame:Inverse() * (body.CFrame * mo.C0)
		mo.Parent = body
		rig.motor[name] = { m = mo, base = mo.C1 }
	end
	joint("head", head, 0, NECK_Y)
	joint("armL", rig.armL, -SHO_X, SHO_Y)
	joint("armR", rig.armR, SHO_X, SHO_Y)

	-- Pupil joints, same construction as the lids below: they hang off the head, and the
	-- idle slides them a fraction of a stud sideways. The eyeball and catchlight stay welded
	-- -- the catchlight is a reflection, and reflections do not travel with the pupil.
	rig.pupils = {}
	for _, e in ipairs(rig.parts) do
		if e.pupil then
			e.part.Anchored = false
			local mo = Instance.new("Motor6D")
			mo.Name = "pupil"; mo.Part0 = head; mo.Part1 = e.part
			mo.C1 = e.part.CFrame:Inverse() * head.CFrame
			mo.Parent = head
			rig.pupils[#rig.pupils + 1] = { m = mo, base = mo.C1 }
		end
	end

	-- THE JAW JOINT. He has had a mouth since build 1 and it has never once moved -- a face
	-- that holds one expression through a bark, a haggle and a goodbye is a signpost with eyes,
	-- and it is the single loudest thing left saying "prop" about him.
	-- ⚠ THE HINGE IS AT THE EAR, NOT AT THE JAW'S OWN CENTRE. C0 puts the pivot up and BACK
	-- (y 6.95, z +0.55); rotating about the part's middle instead swings the chin backwards
	-- through his throat and the tusks straight into the muzzle.
	if jaw then
		jaw.Anchored = false
		local mo = Instance.new("Motor6D")
		mo.Name = "jaw"; mo.Part0 = head; mo.Part1 = jaw
		mo.C0 = CFrame.new(0, (6.95 - 7.6) * S, 0.55 * S)
		mo.C1 = jaw.CFrame:Inverse() * (head.CFrame * mo.C0)
		mo.Parent = head
		rig.jaw = { m = mo, base = mo.C1 }
	end

	-- Eyelid joints hang off the HEAD, not the root, so they ride the head turn for free.
	-- lid = head * C1:Inverse(), so C1 = lid:Inverse() * head, and dropping the lid by d is
	-- C1 = base * CFrame.new(0, d, 0).
	rig.lids = {}
	for _, e in ipairs(rig.parts) do
		if e.lid then
			e.part.Anchored = false
			local mo = Instance.new("Motor6D")
			mo.Name = "lid"; mo.Part0 = head; mo.Part1 = e.part
			mo.C1 = e.part.CFrame:Inverse() * head.CFrame
			mo.Parent = head
			rig.lids[#rig.lids + 1] = { m = mo, base = mo.C1 }
		end
	end

	-- ---- SOUND + DUST ------------------------------------------------------------------
	-- One grumble that rises as you close on him, and a thud under the staff. Both use the
	-- realm's known-good fallback id pitched down -- the ids in Shared/Sfx are still empty, and
	-- a troll that makes no noise at all is the flattest thing on the bridge.
	-- ⚠ NO SOUND. A looping grumble and a staff thud were added here, both pitched-down copies
	-- of the realm's fallback cue -- and with two trolls on island1 that is what was droning
	-- and knocking away for no clear reason. There is no real troll audio to play (Shared/Sfx
	-- CUES are still empty), so the honest state is silence until there is.

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(226, 208, 184))
	dust.Size = NumberSequence.new(1.4 * S); dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Rate = 0; dust.Speed = NumberRange.new(1.5, 3.5); dust.SpreadAngle = Vector2.new(45, 45)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1) })
	dust.Parent = body
	rig.dust = dust

	rig.root, rig.at, rig.s = body, at, S
	-- A census, because "the legs are missing" and "a second script built a different troll"
	-- look identical on screen. If these counts are right and it still looks wrong, the parts
	-- you are looking at are not the ones this file made.
	local n = {}
	for _, e in ipairs(rig.parts) do n[e.grp] = (n[e.grp] or 0) + 1 end
	print(("[Troll] built %d part(s): body=%d head=%d armL=%d armR=%d")
		:format(#rig.parts, n.body or 0, n.head or 0, n.armL or 0, n.armR or 0))

	-- ⚠ WHERE THE PARTS ACTUALLY ARE, three seconds after the build.
	-- "the arms are missing" and "the arms are built but in the wrong place" look identical on
	-- screen, and three rounds of art notes have not separated them. This reports, per group,
	-- how many parts still exist and the WORLD Y-RANGE they occupy. Compare against the build:
	-- feet 0, belt 2.6, shoulders 5.0, neck 5.6, eyes 6.6, hat 7.8, staff top 9.3 -- all times
	-- TROLL_SCALE, measured up from the deck the troll stands on.
	task.delay(3, function()
		if not m.Parent then warn("[Troll][audit] the whole model was destroyed"); return end
		local base = at.Position.Y
		local alive, lo, hi = {}, {}, {}
		for _, e in ipairs(rig.parts) do
			if e.part and e.part.Parent then
				local g = e.grp
				alive[g] = (alive[g] or 0) + 1
				local y = e.part.Position.Y - base
				lo[g] = math.min(lo[g] or 1e9, y); hi[g] = math.max(hi[g] or -1e9, y)
			end
		end
		for _, g in ipairs({ "body", "head", "armL", "armR" }) do
			local built = n[g] or 0
			if (alive[g] or 0) == 0 then
				warn(("[Troll][audit] %s: 0 of %d part(s) survive -- something is DESTROYING them")
					:format(g, built))
			else
				print(("[Troll][audit] %s: %d/%d alive, y %.1f..%.1f above the deck")
					:format(g, alive[g], built, lo[g], hi[g]))
			end
		end
		local ok2, sz = pcall(function() return (select(2, m:GetBoundingBox())) end)
		if ok2 then
			-- warn(), not print(): this is the line that settles "is the troll on my screen the
			-- one this file built", and it needs to be findable in a 400-line boot log.
			warn(("[Troll][audit] THIS FILE'S TROLL: %.1f wide x %.1f tall x %.1f deep at (%d, %d, %d)")
				:format(sz.X, sz.Y, sz.Z, m:GetPivot().X, m:GetPivot().Y, m:GetPivot().Z))
		end

		-- ⚠ IS THERE A SECOND TROLL? A copy of this script baked into the place file builds its
		-- own, and an OLD copy has no build guard to announce itself -- so the only way to catch
		-- it is to look for the result. Anything troll-shaped near this one that this script did
		-- not create is named here in full.
		local mine = {}
		for _, d in ipairs(folder:GetDescendants()) do mine[d] = true end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if not mine[d] and (d:IsA("Model") or d:IsA("BasePart")) and not d:IsDescendantOf(folder) then
				local n2 = d.Name:lower()
				if (n2:find("troll") or n2 == "candytroll") and d ~= landPart then
					local okp, pv = pcall(function() return d:GetPivot().Position end)
					if okp and (pv - m:GetPivot().Position).Magnitude < 120 then
						warn(("[Troll][audit] A SECOND TROLL-SHAPED OBJECT IS HERE, NOT BUILT BY "
							.. "THIS SCRIPT: %s (%s) %d stud(s) away. If the troll on your screen "
							.. "has no arms or legs, THAT is what you are looking at -- delete it "
							.. "in Studio and republish.")
							:format(d:GetFullName(), d.ClassName, (pv - m:GetPivot().Position).Magnitude))
					end
				end
			end
		end
	end)
	return m, head, rig
end

--[[ The idle, driven the way the chocolate monster's is: ONE loop writes every part from its
     group pivot, so nothing can drift apart no matter how long it runs.

       * BREATH   -- the whole figure rises and falls
       * WATCHING -- inside 46 studs his head turns to follow you; outside it, he scans
       * BLINK    -- the two lid parts drop over the eyes on an irregular beat
       * STAFF    -- the right arm lifts and thumps the deck every few seconds ]]
--[[ His strongbox. Every toll ends with you handing something over and it evaporating out
     of your hands -- the chest gives it a destination, and its lid slamming is the receipt.
     Returns (model, lid, mouthCFrame). ]]
local function buildTollChest(at)
	local pm = Instance.new("Model"); pm.Name = "TollChest"; pm.Parent = folder
	local function cb(props2, off)
		props2.Parent = pm
		local q = mk(props2); q.CFrame = at * off; return track(q)
	end
	cb({ Color = PAL.WOOD_D, Size = Vector3.new(3.4, 2.0, 2.4), CanCollide = true,
		CastShadow = true }, CFrame.new(0, 1.0, 0))
	for _, sx in ipairs({ -1.5, 1.5 }) do                                   -- iron bands
		cb({ Color = Color3.fromRGB(92, 92, 100), Size = Vector3.new(0.3, 2.1, 2.5) },
			CFrame.new(sx * 0.62, 1.0, 0))
	end
	cb({ Color = PAL.GOLD, Size = Vector3.new(0.7, 0.8, 0.3) }, CFrame.new(0, 1.55, -1.28))
	cb({ Color = PAL.GOLD, Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34) },
		CFrame.new(0, 1.3, -1.34))
	-- pink candy stripes down the front, so it belongs to this realm and not a pirate island
	for k = -1, 1 do
		cb({ Color = PAL.PINK, Size = Vector3.new(0.42, 1.9, 0.12) },
			CFrame.new(k * 1.05, 1.0, -1.22))
	end
	-- THE LID pivots on its BACK edge, so it opens like a lid instead of hovering off the box
	local lid = cb({ Color = PAL.WOOD, Size = Vector3.new(3.6, 0.45, 2.6), CastShadow = true },
		CFrame.new(0, 2.22, 0))
	cb({ Color = Color3.fromRGB(92, 92, 100), Size = Vector3.new(3.7, 0.16, 0.3) },
		CFrame.new(0, 2.42, 1.15))
	return pm, lid, at * CFrame.new(0, 2.0, 0), at * CFrame.new(0, 2.22, 1.3)
end

--[[ The idle.

     ⚠ ON AnimationController + looping tracks: those play Animation assets, which have to be
     authored in Studio's Animation Editor and PUBLISHED to Roblox for an asset id. Nothing in
     this repo can create one, so an AnimationController here would have no tracks to play.
     What it does under the hood is drive Motor6D joints -- which is exactly what this does,
     against the rig built above. It is the same smoothness from the same mechanism; only the
     authoring tool differs. If you author and upload clips later, this rig will play them as
     it stands, because it is a real jointed rig now.

     PER FRAME THIS WRITES FIVE THINGS, not 164: the root CFrame (which carries the whole
     welded body with it) and four joint rotations. ]]
local function animateTroll(model, head, rig)
	if not (rig and rig.at and rig.root) then return end
	local at, S, mo = rig.at, rig.s or 1, rig.motor or {}
	-- ⚠ HOME IS rig.home, A LIVE FIELD -- NOT a local captured once. payToll() slides the
	-- troll aside by moving this value; when it was a local, the loop below snapped the root
	-- back to the build position every 0.05s and the paid troll stayed planted in the way,
	-- fighting his own step-aside animation frame by frame.
	rig.home = at * CFrame.new(0, ROOT_Y * S, 0)

	task.spawn(function()
		local t, tapAt, crossAt, blinkAt = math.random() * 6, 6, 14, 2.5
		local yawNow, wasBlock = 0, 0
		local gestAt, gestKind, gestT0 = 10 + math.random() * 8, nil, 0
		local glanceAt, glanceEnd = 20 + math.random() * 15, -1
		local noticed, noticeT0 = false, -99
		while model.Parent and rig.root.Parent do
			t += 0.05
			local home = rig.home

			-- BREATHING + WEIGHT, PIVOTED AT THE FEET. The old version translated the whole
			-- body up and down, which is an elevator, not a creature -- nothing alive lifts
			-- off the ground to breathe. Now the feet stay planted and the body LEANS about
			-- ground level: a slow side-to-side weight shift and a slower fore-aft drift, on
			-- periods that do not divide into each other so the combination never visibly
			-- repeats. A whisper of rise (0.09) stays in for the shoulders.
			local bob  = (math.sin(t * (2 * math.pi / 3)) * 0.5 + 0.5) * 0.09 * S
			local lean = CFrame.new(0, -ROOT_Y * S, 0)
				* CFrame.Angles(math.sin(t * 0.31) * math.rad(1.6),
					0, math.sin(t * 0.53) * math.rad(2.2))
				* CFrame.new(0, ROOT_Y * S, 0)

			-- FACE THE NEAREST PLAYER within 20 studs, Y only, eased -- never snapped.
			local want, best = 0, 20
			for _, pl in ipairs(Players:GetPlayers()) do
				local hrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local d = (hrp.Position - home.Position).Magnitude
					if d < best then
						best = d
						local to = home:PointToObjectSpace(hrp.Position)
						want = math.clamp(math.atan2(-to.X, -to.Z), math.rad(-70), math.rad(70))
					end
				end
			end
			-- HE WATCHES THE GOODS, NOT YOUR FACE. If you are walking his errand back to him,
			-- his eyes go to the ITEM -- that is what he cares about, and tracking the thing
			-- rather than the person is a small piece of characterisation you get for free
			-- once you know where the prop is.
			-- (Readable here only because heldModel was hoisted to the top of the file with
			-- the rest of the state; from below its old declaration this was a nil global.)
			-- ⚠ `at`, NOT `stand`. This and the brother-glance below both said `stand`, and
			-- there has never been a local of that name in this file -- so both were multiplying
			-- a nil GLOBAL by a CFrame. That throws, and this loop is the WHOLE troll: one error
			-- ends the thread and every troll on the island freezes mid-pose, forever, with no
			-- breathing, no blink, no watching and no swat. It fired the moment you carried his
			-- errand within 24 studs (the climax of every single toll) and, with two brothers on
			-- island 1, again on the first idle glance about 20 seconds after boot -- which is
			-- why he was a statue before you ever reached him.
			if carrying and heldModel and heldModel.PrimaryPart and best < 24 then
				local okp, hp = pcall(function() return heldModel:GetPivot().Position end)
				if okp then
					local to = (at * CFrame.new(0, NECK_Y * S, 0)):PointToObjectSpace(hp)
					want = math.clamp(math.atan2(-to.X, -to.Z), math.rad(-70), math.rad(70))
				end
			end

			-- BLOCKING POSE while the toll is unpaid and someone is close, and ASLEEP once it
			-- is paid and nobody is near: job done, guard off duty. Eyes shut, head bowed,
			-- breathing shallow, no tracking -- and he wakes the moment somebody comes within
			-- 18 studs, so he never reads as switched off.
			-- ⚠ BOTH ARE COMPUTED HERE, ABOVE THEIR FIRST READER. `asleep` used to be declared
			-- sixty lines further down, so the brother-glance's `not asleep` test below was
			-- reading a nil GLOBAL -- always true -- and a sleeping troll went on turning his
			-- head to check on his brother. A Lua local is invisible above its own declaration.
			local block  = (not paid and best < 12) and 1 or 0
			local asleep = paid and best >= 18

			-- A GLANCE AT HIS BROTHER. Two guards on two bridges who never once look at each
			-- other are two props; one checking on the other is a pair. Only when nobody is
			-- near (the player always outranks his brother) and only if there IS another
			-- troll, so a single-bridge world never triggers it.
			if not asleep and best >= 20 and t >= glanceAt then
				glanceEnd, glanceAt = t + 2.4, t + 20 + math.random() * 16
			end
			if t < glanceEnd and best >= 20 then
				for _, ot in ipairs(trolls) do
					if ot.head and ot.head.Parent and ot.head ~= head then
						local to = (at * CFrame.new(0, NECK_Y * S, 0))
							:PointToObjectSpace(ot.head.Position)
						want = math.clamp(math.atan2(-to.X, -to.Z), math.rad(-70), math.rad(70))
						break
					end
				end
			end

			-- THE DOUBLE-TAKE. The first time someone walks up on an unpaid troll he SNAPS
			-- round rather than easing round -- a guard who notices you at the same lazy rate
			-- he scans the horizon does not read as having noticed you at all. One-shot, and
			-- it re-arms once you leave, so it lands again next visit instead of once ever.
			if not paid and best < 16 and not noticed then
				noticed, noticeT0 = true, t
				-- the snap-round gets a bark, once per approach -- a silent double-take reads
				-- as a camera glitch, a voiced one reads as being spotted
				if head and head.Parent then
					pcall(showBubble, head, "Oi! You there!", false)
				end
			elseif best > 26 then
				noticed = false
			end
			-- ASLEEP OVERRIDES EVERY TARGET ABOVE, and it does so BEFORE the ease below rather
			-- than after it: with the override sitting under this line, a sleeping troll spent
			-- one frame easing toward whatever he had last looked at every time round the loop.
			if asleep then
				want = 0
				bob = bob * 0.45
			end
			local snap = (t - noticeT0 < 0.5) and 0.34 or 0.08
			yawNow += (want - yawNow) * snap

			-- EAGER while YOUR toll is running and you are close: he wants his stuff. A small
			-- forward lean of the head is enough to say it -- more would be begging.
			local eager = (tollActive and best < 14) and math.rad(7) or 0

			-- STAFF TAP every ~6s, and an occasional arm-cross
			local tap = 0
			if t >= tapAt then
				local into = t - tapAt
				if into < 0.8 then
					tap = math.sin(into / 0.8 * math.pi) * math.rad(14)
				else
					-- impatient taps while a toll is out: every ~3s instead of every ~6
					tapAt = t + (tollActive and 2.8 or 6)
				end
			end
			-- THE SWAT: punish() sets rig.swatAt on the nearest troll, and for 0.75s the
			-- staff arm whips up and slams down. This is what makes the knockback read as HIM
			-- throwing you out -- before this, the shove came from empty air and the troll
			-- just stood there watching it happen.
			local swat = 0
			if rig.swatAt then
				local into = os.clock() - rig.swatAt
				if into < 0.75 then
					-- fast up (first third), hard down (rest) -- an asymmetric swing reads as
					-- a strike where a sine reads as a shrug
					-- 70, not 95. The staff is gripped MID-LENGTH, so the shoulder joint
					-- swings the pole both ways at once: as the sign comes down in front, the
					-- butt end sweeps back through where his hip and skirt are. Less angle,
					-- plus the outward lean below, keeps the whole pole clear of him.
					swat = (into < 0.25) and (into / 0.25) * math.rad(70)
						or (1 - (into - 0.25) / 0.5) * math.rad(70)
				else
					rig.swatAt = nil
				end
			end

			-- GOODBYE WAVE: payToll sets rig.wave for a couple of seconds and the LEFT arm
			-- (the one without the staff) swings up and rocks. Joint-driven, so it composes
			-- with everything else instead of fighting the weld rig.
			local wave = 0
			if rig.wave then
				wave = math.rad(150) + math.sin(t * 9) * math.rad(18)
			end

			-- ---- IDLE GESTURES ------------------------------------------------------------
			-- One of four, every 9-17s, ONLY while nobody is close and he is awake. Standing
			-- perfectly still between events is what made him read as scenery; a guard on a
			-- long shift fidgets. All of them drive the LEFT arm and the head only -- the
			-- right arm holds a 12-stud staff, and swinging that around for a scratch is how
			-- the sign ended up inside his hat in the first place.
			if not asleep and best >= 14 and not gestKind and t >= gestAt then
				gestKind = ({ "scratch", "hat", "stretch", "look" })[math.random(1, 4)]
				gestT0 = t
			end
			local gScratch, gHat, gStretch, gLook = 0, 0, 0, 0
			if gestKind then
				local into, dur = t - gestT0, 2.4
				if into < dur and not asleep then
					local e = math.sin(into / dur * math.pi)    -- ease in and back out
					if gestKind == "scratch" then gScratch = e
					elseif gestKind == "hat" then gHat = e
					elseif gestKind == "stretch" then gStretch = e
					else gLook = e end
				else
					gestKind = nil
					gestAt = t + 9 + math.random() * 8
				end
			end

			-- POINTING: you are carrying his errand back to him and he is watching it come in.
			-- (Deliberately not colour-aware -- the candy in hand is tracked by a local declared
			-- further down this file, which would resolve to a nil global from in here.)
			local point = (tollActive and carrying and best < 18) and 1 or 0

			local cross = 0
			if t >= crossAt then
				local into = t - crossAt
				if into < 2.5 then cross = math.sin(into / 2.5 * math.pi)
				else crossAt = t + 12 + math.random() * 8 end
			end

			-- BLINK -- irregular gaps so it never reads as a metronome
			local shut = 0
			if t >= blinkAt then
				local into = t - blinkAt
				if into < 0.2 then shut = 1 - math.abs(into - 0.1) / 0.1
				else
					-- one blink in four is a double -- a quick second flutter right after.
					-- Real blinking clusters; a metronome of perfect singles is part of the
					-- "animated on a timer" look.
					blinkAt = (math.random() < 0.25) and (t + 0.3)
						or (t + 2.2 + math.random() * 3.6)
				end
			end
			if asleep then shut = 1 end   -- lids stay down for the whole nap
			-- EYES LEAD, HEAD FOLLOWS. The pupils slide toward where he WANTS to look in
			-- proportion to how far the head still has to turn -- so a new target gets a
			-- dart of the eyes first and the head swings after, and once the head catches
			-- up the pupils re-centre on their own (want - yawNow goes to zero). This
			-- ordering is one of the strongest live-creature tells there is.
			local gaze = math.clamp((want - yawNow) * 0.9, -1, 1) * 0.16 * S
			for _, pj in ipairs(rig.pupils or {}) do
				pj.m.C1 = pj.base * CFrame.new(gaze, 0, 0)
			end

			-- the lids REST a quarter of the way down. Hooded eyes are the angry squint --
			-- wide-open circles under scowling brows read startled, not grumpy. The blink
			-- closes the remaining three quarters from there.
			-- ...and drop FURTHER while he is squaring up to an unpaid crosser. Narrowing the
			-- eyes is what a face does before it decides you are trouble, and it costs one
			-- term on a joint that is already being driven.
			local rest = 0.24 + block * 0.22
			for _, l in ipairs(rig.lids or {}) do
				l.m.C1 = l.base * CFrame.new(0, (rest + (0.95 - rest) * shut) * S, 0)
			end

			-- ---- THE JAW ------------------------------------------------------------------
			-- Talking chatters it; the swat opens it into a roar; asleep it hangs slack and
			-- drifts with the breath. Everything else keeps it shut, because a troll standing
			-- there with his mouth permanently ajar reads as broken, not as relaxed.
			local jawOpen = 0
			if rig.talkUntil and os.clock() < rig.talkUntil then
				-- two speeds mixed, so it is a mouth forming words rather than a hinge on a
				-- timer: the fast term is syllables, the slow one is the shape of the sentence
				jawOpen = (0.34 + 0.3 * math.sin(t * 24) + 0.2 * math.sin(t * 9.3)) * math.rad(19)
			elseif asleep then
				jawOpen = (0.5 + 0.5 * math.sin(t * 0.9)) * math.rad(6)
			end
			jawOpen = math.max(0, jawOpen) + swat * 0.3          -- and he roars on the swing
			if rig.jaw then
				-- same convention as setJ below: C1 = base * R:Inverse(), and R is the rotation
				-- applied about the hinge. NEGATIVE pitch drops the chin (positive swings it up
				-- and back into the skull), which is why the sign looks inverted here.
				rig.jaw.m.C1 = rig.jaw.base * CFrame.Angles(-jawOpen, 0, 0):Inverse()
			end

			-- a puff of dust the moment he plants his foot forward to block
			if rig.dust then
				if block == 1 and wasBlock == 0 then
					rig.dust.Rate = 60
					task.delay(0.35, function() if rig.dust then rig.dust.Rate = 0 end end)
				end
				wasBlock = block
			end

			-- ONE write for the entire body: root position + facing.
			rig.root.CFrame = home * CFrame.Angles(0, yawNow, 0) * lean
				* CFrame.new(0, bob, -block * 1.2 * S)

			local sway = math.sin(t * 1.3) * math.rad(3)
			local function setJ(name, rot)
				local j = mo[name]
				if j then j.m.C1 = j.base * rot:Inverse() end
			end
			-- head: a slow nod, tilting further while he is challenging you
			-- micro-noise: two incommensurate sines under a degree each. Below conscious
			-- notice, but its ABSENCE is precisely what makes a head look mounted on a stand.
			local mnP = math.sin(t * 2.7) * math.rad(0.7) + math.sin(t * 4.3) * math.rad(0.4)
			local mnY = math.sin(t * 3.1) * math.rad(0.8)
			setJ("head", CFrame.Angles(mnP + math.sin(t * 0.8) * math.rad(3) + block * math.rad(-6)
				+ eager + (asleep and math.rad(18) or 0)
				+ gHat * math.rad(6) - gStretch * math.rad(16),
				mnY + gLook * math.sin((t - gestT0) * 3.2) * math.rad(26),
				block * math.rad(7) + gScratch * math.rad(9)))
			-- arms: out to the sides when blocking, folded across when idling
			setJ("armL", CFrame.Angles(sway - cross * math.rad(38)
				- gScratch * math.rad(118) - gHat * math.rad(142)
				+ gStretch * math.rad(38) - point * math.rad(72), 0,
				math.rad(4) - block * math.rad(46) - cross * math.rad(22) + wave
				- gScratch * math.rad(34) - gHat * math.rad(20)))
			-- ⚠ THE SWAT LEANS THE ARM OUTWARD AS IT SWINGS (the `swat * 0.45` roll).
			-- Without it the pole stays in the body's plane through the whole arc and the butt
			-- end passes straight through the skirt. Leaning out first is also just how you
			-- actually swing something long.
			setJ("armR", CFrame.Angles(-sway - tap - swat - cross * math.rad(30), 0,
				math.rad(-4) + block * math.rad(46) + cross * math.rad(18) + swat * 0.45))

			task.wait(0.05)
		end
	end)
end

--[[ One standing TROLLLAND notice, built ON a hand-placed 'signplacement' part.

     The marker gives POSITION AND FACING and is then hidden -- the house rule for every marker
     in this realm. Its own -Z is the way the board looks, so turn the part in Studio to aim the
     sign; its BASE is where the post meets the ground, so the sign never floats however tall
     you drew the block. ]]
--[[ wob: per-sign lean in degrees, so two signs are not identical clones. aimAt: world
     position of the nearest troll -- the arrow on the post points at him, which turns the sign
     from decoration into an actual direction. ]]
local function buildSignPost(at, wob, aimAt)
	wob = wob or 0
	at = at * CFrame.Angles(0, 0, math.rad(wob))
	local function bit(props2, cf)
		props2.Parent = folder
		local p = mk(props2); p.CFrame = at * cf; return track(p)
	end
	-- RAMSHACKLE ON PURPOSE. A troll's sign should look like a troll made it: every plank is
	-- its own board at its own slight tilt, the title is nailed on crooked, and a little
	-- warning shingle dangles under the rest. One flat cream rectangle with rails -- the old
	-- build -- read as park-ranger signage, which is the opposite of the joke.

	-- candy-cane post with a gumdrop on top
	for k = 0, 4 do
		bit({ Color = (k % 2 == 0) and PAL.CREAM or PAL.RED, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.15, 0.62, 0.62) },
			CFrame.new(0, 0.55 + k * 1.12, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end
	bit({ Color = PAL.PURPLE, Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9) },
		CFrame.new(0, 6.0, 0))
	bit({ Color = PAL.WOOD_D, Size = Vector3.new(1.7, 0.42, 0.42) }, CFrame.new(0, 0.24, 0))

	-- the TITLE plank: biggest, crooked, pink candy letters
	local title = bit({ Color = PAL.WOOD, Size = Vector3.new(5.6, 1.35, 0.34), CastShadow = true },
		CFrame.new(0.15, 5.0, -0.1) * CFrame.Angles(0, 0, math.rad(-4 - wob)))
	faceText(title, Enum.NormalId.Front, "TROLLLAND!", PAL.PINK, 64, 380, 90)
	-- the back of the title plank, for anyone reading the sign from inside the park
	faceText(title, Enum.NormalId.Back, "TURN AROUND.", Color3.fromRGB(112, 66, 32), 48, 380, 90)

	-- three rule planks, alternating tilt, each its own board
	local RULES = {
		{ "NO TRESPASSING",  3.9, math.rad(3),  PAL.CREAM },
		{ "TROLL RULE: OBEY", 2.95, math.rad(-3), PAL.CREAM },
		{ "PAY THE TOLL!",   2.0, math.rad(4),  Color3.fromRGB(255, 226, 232) },
	}
	for _, r in ipairs(RULES) do
		local plank = bit({ Color = r[4], Size = Vector3.new(4.7, 0.85, 0.3), CastShadow = true },
			CFrame.new(-0.1, r[2], -0.12) * CFrame.Angles(0, 0, r[3]))
		faceText(plank, Enum.NormalId.Front, r[1], Color3.fromRGB(112, 66, 32), 46, 340, 62)
		-- nail heads in the corners, so the planks read as NAILED ON, not floating
		for _, nx in ipairs({ -2.05, 2.05 }) do
			bit({ Color = Color3.fromRGB(88, 88, 96), Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.16, 0.16, 0.16) },
				CFrame.new(-0.1, r[2], -0.29) * CFrame.Angles(0, 0, r[3]) * CFrame.new(nx, 0, 0))
		end
	end

	-- the dangling shingle: hung under everything on two short ropes, tilted harder
	for _, rx in ipairs({ -0.85, 0.85 }) do
		bit({ Color = PAL.WOOD_D, Size = Vector3.new(0.12, 0.5, 0.12) }, CFrame.new(rx, 1.38, -0.12))
	end
	local shingle = bit({ Color = PAL.PINK, Size = Vector3.new(2.6, 0.72, 0.26) },
		CFrame.new(0, 0.95, -0.12) * CFrame.Angles(0, 0, math.rad(-6)))
	faceText(shingle, Enum.NormalId.Front, "OR ELSE...", PAL.CREAM, 38, 240, 56)
	-- it hangs on ropes, so it SWINGS -- about the rope line (its top edge), not its centre,
	-- or the ropes would visibly detach at the ends of each sway. Slow and slight: wind, not
	-- a metronome. One dormant loop per sign is nothing next to the trolls' own idles.
	task.spawn(function()
		local hinge = at * CFrame.new(0, 1.31, -0.12)   -- where the ropes meet the board
		local t2 = math.random() * 6
		while shingle.Parent do
			t2 += 0.08
			local a2 = math.rad(-6) + math.sin(t2 * 0.9) * math.rad(4.5)
			shingle.CFrame = hinge * CFrame.Angles(0, 0, a2) * CFrame.new(0, -0.36, 0)
			task.wait(0.08)
		end
	end)

	-- the little skull perched on the title plank, lollipop through it
	bit({ Color = Color3.fromRGB(248, 244, 236), Size = Vector3.new(1.05, 0.95, 0.9) },
		CFrame.new(-2.1, 6.15, -0.1))
	bit({ Color = Color3.fromRGB(248, 244, 236), Size = Vector3.new(0.7, 0.4, 0.75) },
		CFrame.new(-2.1, 5.55, -0.1))
	for _, ex in ipairs({ -0.26, 0.26 }) do
		bit({ Color = Color3.fromRGB(24, 22, 28), Size = Vector3.new(0.3, 0.34, 0.16) },
			CFrame.new(-2.1 + ex, 6.25, -0.56))
	end
	bit({ Color = PAL.CREAM, Size = Vector3.new(0.15, 0.75, 0.15) }, CFrame.new(-2.1, 7.0, -0.1))
	bit({ Color = PAL.PINK, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 1.05, 1.05) },
		CFrame.new(-2.1, 7.6, -0.1) * CFrame.Angles(0, math.rad(90), 0))

	-- ---- THE POINTER: an arrow on the post aimed at the nearest troll --------------------
	if aimAt then
		local from = (at * CFrame.new(0, 6.7, 0)).Position
		local flat = Vector3.new(aimAt.X, from.Y, aimAt.Z)
		if (flat - from).Magnitude > 2 then
			local look = CFrame.lookAt(from, flat)
			local function abit(props2, cf)
				props2.Parent = folder
				local p2 = mk(props2); p2.CFrame = look * cf; return track(p2)
			end
			abit({ Color = PAL.CREAM, Size = Vector3.new(0.45, 0.26, 2.3) }, CFrame.new(0, 0, -1.15))
			for _, sx in ipairs({ -1, 1 }) do
				abit({ Color = PAL.PINK, Size = Vector3.new(0.42, 0.3, 1.0) },
					CFrame.new(sx * 0.28, 0, -2.35) * CFrame.Angles(0, math.rad(sx * -38), 0))
			end
			abit({ Color = PAL.PINK, Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.45, 0.45, 0.45) }, CFrame.new(0, 0, 0.1))
		end
	end
	return title
end

--[[ The way into TROLLLAND: the (flag-gated) arch plus candy trees either side. The rules
     board and skull plaque that used to live here moved to the hand-placed 'signplacement'
     sign in build 6, so this is scenery only. `at` is the ground at the centre of the way in,
     facing the approach. ]]
--[[ The TROLLLAND arch over one way in, plus candy trees either side.

     NO TEXT BOARDS HERE, DELIBERATELY. This function used to build a "WELCOME TO TROLLLAND"
     rules board and a skull plaque, and it is called once per way in -- so two calls produced
     two of each, and with the 'signplacement' sign that made THREE welcome boards and a skull
     standing out in the field with no bridge near it. The wording lives on the signplacement
     sign now, which is placed by hand and therefore exists exactly once per marker. ]]
local function buildGate(at, width)
	local w = math.max(10, width or 22)
	local function bit(props2, cf)
		props2.Parent = folder
		local p = mk(props2); p.CFrame = at * cf; return track(p)
	end
	-- ⚠ Decor is SEATED BY RAY, and skipped where the ray finds nothing. The gate stands at the
	-- water's edge, so a fixed offset put candy on sticks hanging in mid-air over the shoreline.
	local function seat(lx, lz)
		local wp = (at * CFrame.new(lx, 0, lz)).Position
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character, folder }
		local hit = Workspace:Raycast(wp + Vector3.new(0, 80, 0), Vector3.new(0, -260, 0), rp)
		if not hit then return nil end
		return CFrame.new(hit.Position) * (at - at.Position)
	end

	-- ---- THE ARCH -- OFF ------------------------------------------------------------
	-- Removed at your request. It is behind a flag rather than deleted because this is the
	-- second time the arch has been taken out and put back; SHOW_ARCH = true restores it
	-- exactly as it was, with no rebuilding from a description.
	if SHOW_ARCH then
		-- Half the height it was: 9-stud posts, board at 9.6, skull at 11.4. The first one topped
		-- out at 20 studs and dwarfed both the troll and the bridge.
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (w * 0.5)
			for k = 0, 5 do
				bit({ Color = (k % 2 == 0) and PAL.CREAM or PAL.RED,
					Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 1.15, 1.15) },
					CFrame.new(x, 0.8 + k * 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
			end
		end
		local board = bit({ Color = PAL.WOOD_D, Size = Vector3.new(w, 2.4, 0.45), CastShadow = true },
			CFrame.new(0, 9.6, 0))
		bit({ Color = PAL.GOLD, Size = Vector3.new(w + 0.4, 0.34, 0.6) }, CFrame.new(0, 10.9, 0))
		bit({ Color = PAL.GOLD, Size = Vector3.new(w + 0.4, 0.34, 0.6) }, CFrame.new(0, 8.3, 0))
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			faceText(board, face, "TROLLLAND", PAL.PINK, 62, 460, 120, Enum.Font.LuckiestGuy)
		end
		-- the skull with a lollipop through it, small, sitting on the board
		bit({ Color = Color3.fromRGB(248, 244, 236), Size = Vector3.new(1.5, 1.4, 1.35) },
			CFrame.new(0, 11.5, 0))
		bit({ Color = Color3.fromRGB(248, 244, 236), Size = Vector3.new(1.0, 0.6, 1.1) },
			CFrame.new(0, 10.65, 0))
		for _, sx in ipairs({ -1, 1 }) do
			bit({ Color = Color3.fromRGB(24, 22, 28), Size = Vector3.new(0.42, 0.48, 0.22) },
				CFrame.new(sx * 0.35, 11.7, -0.66))
		end
		bit({ Color = PAL.CREAM, Size = Vector3.new(0.22, 1.0, 0.22) }, CFrame.new(0, 12.6, 0))
		bit({ Color = PAL.PINK, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.5, 1.5) },
			CFrame.new(0, 13.4, 0) * CFrame.Angles(0, math.rad(90), 0))

	end

	-- ---- CANDY TREES either side, on real ground only ------------------------------------
	-- Lollipop trees (striped trunk, big glazed head) and gumdrop trees (stacked domes), in the
	-- pink/purple set. These replace the cream-stick toadstools, which were the "candy balls on
	-- white sticks" hanging over the shoreline.
	local trees = 0
	for _, sx in ipairs({ -1, 1 }) do
		for i = 1, 3 do
			local g = seat(sx * (w * 0.5 + 2.5 + i * 3.2), (i % 2 == 0) and 4.0 or -3.2)
			if g then
				trees += 1
				if i % 2 == 1 then
					-- LOLLIPOP TREE
					for k = 0, 5 do
						track(mk({ Color = (k % 2 == 0) and PAL.CREAM or PAL.PINK,
							Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 0.7, 0.7),
							CFrame = g * CFrame.new(0, 0.5 + k * 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
							Parent = folder }))
					end
					track(mk({ Color = (i == 1) and PAL.PINK or PAL.PURPLE,
						Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.55, 4.4, 4.4),
						CFrame = g * CFrame.new(0, 7.6, 0) * CFrame.Angles(0, math.rad(90), 0),
						Parent = folder }))
					for k = 0, 4 do
						track(mk({ Color = PAL.CREAM, Size = Vector3.new(1.5, 0.34, 0.26),
							CFrame = g * CFrame.new(0, 7.6, -0.32) * CFrame.Angles(0, 0, math.rad(k * 36))
								* CFrame.new(0.8 + k * 0.22, 0, 0), Parent = folder }))
					end
				else
					-- GUMDROP TREE
					track(mk({ Color = PAL.WOOD_D, Size = Vector3.new(0.9, 3.0, 0.9),
						CFrame = g * CFrame.new(0, 1.5, 0), Parent = folder }))
					for k = 0, 2 do
						track(mk({ Color = ({ PAL.PURPLE, PAL.PINK, PAL.PINK_L })[k + 1],
							Shape = Enum.PartType.Ball, Size = Vector3.new(4.6 - k * 1.1, 3.0 - k * 0.7, 4.6 - k * 1.1),
							CFrame = g * CFrame.new(0, 3.6 + k * 1.5, 0), Parent = folder }))
					end
				end
			end
		end
	end
	print(("[Troll] gate up: arch %s, %d candy tree(s) (spots with no ground under them "
		.. "were skipped)"):format(SHOW_ARCH and ("%.0f wide"):format(w) or "OFF", trees))
end

-- ============================================================================
-- THE BARRIER -- per-player, and it only ever looks at THIS player
-- ============================================================================
local function insideTrollland(pos)
	if not (landCF and landHalf) then return false end
	-- THE SAFE BUBBLE WINS. Standing near a troll is never trespassing, whatever the zone
	-- covers -- otherwise a park drawn over the bridge locks you out of the only person who
	-- can let you in. See TROLL_SAFE.
	for _, t in ipairs(trolls) do
		if t.head and t.head.Parent and (pos - t.head.Position).Magnitude <= TROLL_SAFE then
			return false
		end
	end
	local o = landCF:PointToObjectSpace(pos)
	return math.abs(o.X) <= landHalf.X and math.abs(o.Z) <= landHalf.Z
		and o.Y >= -landHalf.Y - 6 and o.Y <= landHalf.Y + 40
end

local function punish()
	local hrp, hum = hrpOf(), humOf()
	if not hrp then return end
	-- the NEAREST troll is the one who deals with you: he swats, he shouts, his name is on it
	local nearT, nearD = nil, math.huge
	do
		local hrp0 = hrpOf()
		for _, t in ipairs(trolls) do
			if t.head and t.head.Parent and hrp0 then
				local d = (t.head.Position - hrp0.Position).Magnitude
				if d < nearD then nearD, nearT = d, t end
			end
		end
	end
	if nearT and nearT.rig then nearT.rig.swatAt = os.clock() end

	if os.clock() - lastWarn >= WARN_COOLDOWN then
		lastWarn = os.clock()
		banner("\xF0\x9F\x9A\xAB PAY THE TROLL TOLL FIRST!", PAL.RED)
		flash("\xF0\x9F\x9A\xAB PAY THE TROLL TOLL FIRST!", 2.5)
		local nag = (nearT and nearT.head) or firstHead()
		if nag then
			-- a different bark each time, so a repeat offender is not read the same line twice
			local LINES = {
				"OI! Nobody crosses without paying!",
				"Back you go! TOLL first!",
				"Sneaky, sneaky. The toll says NO.",
				"My bridge. My rules. MY TOLL!",
			}
			showBubble(nag, LINES[math.random(1, #LINES)], false)
		end
		if _G.hapticPulse then pcall(_G.hapticPulse, "bump") end
	end
	if PUNISH == "reset" then
		if hum then hum.Health = 0 end
		return
	end
	-- THROWN OUT, not killed: away from the park's centre and up, so you land back where you
	-- came from. Direction is measured from the ZONE, not from the troll, so it works from
	-- whichever side you tried to sneak in.
	local away = hrp.Position - (landCF and landCF.Position or hrp.Position)
	away = Vector3.new(away.X, 0, away.Z)
	local dir = (away.Magnitude > 1) and away.Unit or Vector3.new(0, 0, 1)
	hrp.AssemblyLinearVelocity = dir * THROW_BACK + Vector3.new(0, THROW_UP, 0)

	-- a burst of candy bits at your feet as you leave the ground: the hit needs a mark, or
	-- the launch reads as physics glitching rather than a troll's swat landing
	for i = 1, 10 do
		local c = mk({ Color = ({ PAL.PINK, PAL.GOLD, PAL.MINT, PAL.PURPLE })[(i % 4) + 1],
			Size = Vector3.new(0.4, 0.4, 0.4), CanCollide = false,
			CFrame = CFrame.new(hrp.Position + Vector3.new(0, -2, 0))
				* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3),
			Parent = folder })
		TweenService:Create(c, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = c.CFrame * CFrame.new((math.random() - 0.5) * 9, 2 + math.random() * 4,
				(math.random() - 0.5) * 9),
			Transparency = 1 }):Play()
		Debris:AddItem(c, 1.0)
	end
end

task.spawn(function()
	while true do
		task.wait(0.15)
		if not paid and landCF then
			local hrp = hrpOf()
			if hrp and insideTrollland(hrp.Position) then punish() end
		end
	end
end)

-- ============================================================================
-- CARRYING -- one prop at a time, welded into the hand
-- ============================================================================
local function dropHeld()
	if heldModel then heldModel:Destroy(); heldModel = nil end
	carrying = nil
	local hum = humOf()
	if hum and hum.WalkSpeed < 16 then hum.WalkSpeed = 16 end
end

local function buildProp(kind, colour)
	local m = Instance.new("Model"); m.Name = "TollProp_" .. kind
	local function bit(props2, cf)
		props2.Parent = m
		local p = mk(props2); p.CFrame = cf; return p
	end
	local root
	if kind == "lolly" then
		-- THE PRIZE of the search toll: you hunt this by ear for a minute or more, so the find
		-- has to look worth it. Swirl arcs on both faces, a gold rim, a ribbon bow on the
		-- stick, and a slow sparkle -- the sparkle doubles as the last 15 studs of the hunt,
		-- picking the prop out of the scenery once the jingle has brought you close.
		root = bit({ Color = colour or PAL.PINK, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 3.2, 3.2), CanQuery = true }, CFrame.new())
		bit({ Color = PAL.GOLD, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.34, 3.45, 3.45) },
			CFrame.new(0, 0, 0))
		for _, fz in ipairs({ -0.24, 0.24 }) do
			for k = 0, 4 do
				bit({ Color = Color3.new(1, 1, 1), Size = Vector3.new(1.05, 0.26, 0.1) },
					CFrame.new(0, 0, fz) * CFrame.Angles(0, 0, math.rad(k * 36))
						* CFrame.new(0.5 + k * 0.2, 0, 0))
			end
		end
		bit({ Color = PAL.CREAM, Size = Vector3.new(0.3, 3.4, 0.3) }, CFrame.new(0, -2.6, 0))
		for _, sx in ipairs({ -1, 1 }) do                                       -- ribbon bow
			bit({ Color = PAL.RED, Size = Vector3.new(0.85, 0.4, 0.22) },
				CFrame.new(sx * 0.5, -1.75, 0) * CFrame.Angles(0, 0, math.rad(sx * 28)))
		end
		bit({ Color = PAL.RED, Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4) },
			CFrame.new(0, -1.75, 0))
		local sp = Instance.new("ParticleEmitter")
		sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sp.Color = ColorSequence.new(PAL.PINK_L)
		sp.Size = NumberSequence.new(0.5); sp.Lifetime = NumberRange.new(0.6, 1.1)
		sp.Rate = 5; sp.Speed = NumberRange.new(0.4, 1.2); sp.LightEmission = 0.6
		sp.Parent = root
		-- a soft, SHORT-RANGE light. The realm runs full daylight at every altitude, so a
		-- prop hidden in a hedge has nothing to separate it from the hedge; 9 studs is enough
		-- to say "here" without lighting the island (the Bakery lesson -- no bright bulbs).
		local gl = Instance.new("PointLight")
		gl.Color = PAL.PINK_L; gl.Brightness = 0.55; gl.Range = 9; gl.Shadows = false
		gl.Parent = root
	elseif kind == "drink" then
		-- A PROPER TAKEAWAY CUP. It was a plain cylinder with a stick and one ball on top; this
		-- is the thing the whole DRINK toll is built around, so it is worth the parts: a tapered
		-- body (three stacked rings, narrower at the base), a rolled rim, a domed lid, a candy
		-- straw, fizz, and a cardboard band you can actually read.
		local UP90 = CFrame.Angles(0, 0, math.rad(90))
		root = bit({ Color = PAL.CREAM, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.0, 3.4, 3.4), CanQuery = true }, CFrame.new(0, 0.9, 0) * UP90)
		bit({ Color = PAL.CREAM, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 3.0, 3.0) }, CFrame.new(0, -0.7, 0) * UP90)
		bit({ Color = PAL.CREAM, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 2.6, 2.6) }, CFrame.new(0, -1.7, 0) * UP90)   -- narrow base
		-- the soda inside, showing above the band
		bit({ Color = colour or PAL.PURPLE, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 3.3, 3.3) }, CFrame.new(0, 2.35, 0) * UP90)
		-- rolled rim + domed lid
		bit({ Color = Color3.fromRGB(252, 250, 246), Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.42, 3.7, 3.7) }, CFrame.new(0, 2.62, 0) * UP90)
		bit({ Color = Color3.fromRGB(252, 250, 246), Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.5, 1.5, 3.5) }, CFrame.new(0, 2.9, 0))
		-- a printed band round the middle, and a pink swirl on it
		bit({ Color = PAL.PINK, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.5, 3.52, 3.52) }, CFrame.new(0, 0.6, 0) * UP90)
		for k = 0, 5 do
			bit({ Color = Color3.fromRGB(255, 245, 250), Size = Vector3.new(0.55, 0.22, 0.2) },
				CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(k * 60), 0)
					* CFrame.new(0, 0, -1.79) * CFrame.Angles(0, 0, math.rad(28)))
		end
		-- candy-striped straw, bent at the top
		for k = 0, 4 do
			bit({ Color = (k % 2 == 0) and Color3.new(1, 1, 1) or PAL.RED,
				Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.62, 0.42, 0.42) },
				CFrame.new(0.62, 3.4 + k * 0.6, 0) * CFrame.Angles(0, 0, math.rad(76)))
		end
		bit({ Color = PAL.RED, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 0.42, 0.42) },
			CFrame.new(1.15, 6.15, 0) * CFrame.Angles(0, 0, math.rad(24)))
		-- fizz bubbles escaping round the straw
		for i = 1, 5 do
			local a = i * 1.257
			bit({ Color = PAL.PINK_L, Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.34, 0.34, 0.34) },
				CFrame.new(math.cos(a) * 0.95, 3.0 + i * 0.26, math.sin(a) * 0.95))
		end
	else -- candy
		-- A WRAPPED SWEET, not a bare ball: twisted wrapper ends that taper, a cream band
		-- round the middle, and a shine spot. The toll asks for a candy BY COLOUR out of a
		-- ring of five, so the body colour has to dominate -- everything else stays neutral.
		local c = colour or PAL.RED
		root = bit({ Color = c, Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.6, 2.4, 2.4), CanQuery = true }, CFrame.new())
		bit({ Color = PAL.CREAM, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 2.5, 2.5) },
			CFrame.new() * CFrame.Angles(0, 0, math.rad(90)))
		for _, sx in ipairs({ -1, 1 }) do
			-- the twist: two shrinking discs then a pinched tail, angled like pulled foil
			bit({ Color = c, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 1.5, 1.5) },
				CFrame.new(sx * 1.35, 0, 0) * CFrame.Angles(0, 0, math.rad(90)))
			bit({ Color = PAL.CREAM, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.95, 0.95) },
				CFrame.new(sx * 1.62, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90 + sx * 9)))
			bit({ Color = c, Size = Vector3.new(0.65, 0.5, 0.3) },
				CFrame.new(sx * 2.05, 0.12, 0) * CFrame.Angles(0, 0, math.rad(sx * 24)))
		end
		bit({ Color = Color3.new(1, 1, 1), Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.4, 0.4) },
			CFrame.new(-0.6, 0.75, -0.7))                                       -- shine spot
	end
	m.PrimaryPart = root
	return m
end

local function giveHeld(kind, colour)
	dropHeld()
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not hand then return end
	local m = buildProp(kind, colour)
	local prim = m.PrimaryPart
	if not prim then m:Destroy(); return end
	m:PivotTo(hand.CFrame * CFrame.new(0, -1.6, 0))
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p ~= prim then
			local w = Instance.new("WeldConstraint"); w.Part0 = prim; w.Part1 = p; w.Parent = p
		end
	end
	local hw = Instance.new("WeldConstraint"); hw.Part0 = hand; hw.Part1 = prim; hw.Parent = prim
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.Massless = true
		end
	end
	m.Parent = char
	heldModel = m
	carrying = kind
	-- THE CUP IS HEAVY. That is the whole DRINK toll: it is not a fetch, it is a careful walk.
	if kind == "drink" then
		local hum = humOf()
		if hum then hum.WalkSpeed = 16 * DRINK_SPEED end
	end
end

-- a respawn drops the weld with the old body; put back whatever was in hand
player.CharacterAdded:Connect(function()
	heldModel = nil
	local k = carrying
	carrying = nil
	if k then task.delay(1.4, function() if tollActive then giveHeld(k) end end) end
end)

-- ============================================================================
-- TOLL 1 -- FIND MY LOLLIPOP (search by ear)
-- ============================================================================
-- No arrow and no waypoint: a jingle rises as you close on it. Finding it is the game, so
-- pointing at it would BE the game, played by somebody else.
local lollyPart, lollySound
local function startLolly()
	local spots2 = {}   -- the computed ring, used only when no 'gumball' markers exist
	local centre = (active and active.head and active.head.Position)
		or (firstHead() and firstHead().Position) or Vector3.new()
	for i = 1, 12 do
		local a = i * 2.39996
		local r = 70 + (i % 4) * 30
		local at = centre + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character, folder }
		local hit = Workspace:Raycast(at + Vector3.new(0, 120, 0), Vector3.new(0, -400, 0), rp)
		if hit then spots2[#spots2 + 1] = hit.Position + Vector3.new(0, 2.2, 0) end
	end
	local pick = takeSpots(1)
	local at = pick[1] or spots2[math.random(1, math.max(1, #spots2))]
		or (centre + Vector3.new(60, 2, 60))

	local m = buildProp("lolly", PAL.PINK)
	m:PivotTo(CFrame.new(at))
	m.Parent = folder
	lollyPart = m.PrimaryPart
	track(lollyPart)
	-- it turns slowly so a glint catches your eye once you are close
	task.spawn(function()
		local t = 0
		while m.Parent do t += 0.05; m:PivotTo(CFrame.new(at) * CFrame.Angles(0, t, 0)); task.wait(0.05) end
	end)
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Pick Up"; pr.ObjectText = "The Troll's Lollipop"
	pr.HoldDuration = 0; pr.MaxActivationDistance = 12; pr.RequiresLineOfSight = false
	pr.Parent = lollyPart
	pr.Triggered:Connect(function()
		if carrying then flash("\xF0\x9F\x8D\xAD Your hands are full!", 2); return end
		giveHeld("lolly", PAL.PINK)
		m:Destroy()
		if lollySound then lollySound:Stop() end
		banner("\xF0\x9F\x8D\xAD Found it! Take it back to the Troll.", PAL.PINK)
		flash("\xF0\x9F\x8D\xAD Found it -- back to the Troll!", 3)
	end)

	-- THE JINGLE. Volume is distance-driven from OUR side rather than left to rolloff, so the
	-- "hotter / colder" read is exact and audible well before the prop is on screen.
	task.spawn(function()
		local snd = Instance.new("Sound")
		snd.SoundId = "rbxassetid://4612378364"     -- the realm's known-good fallback cue
		snd.Looped = true; snd.Volume = 0; snd.PlaybackSpeed = 1.6
		snd.Parent = lollyPart
		lollySound = snd
		pcall(function() snd:Play() end)
		while lollyPart and lollyPart.Parent and tollActive do
			local hrp = hrpOf()
			if hrp then
				local d = (hrp.Position - lollyPart.Position).Magnitude
				local near = math.clamp(1 - d / LOLLY_HOT, 0, 1)
				snd.Volume = 0.05 + near * 0.55
				snd.PlaybackSpeed = 1.3 + near * 0.9
			end
			task.wait(0.15)
		end
		if snd.Parent then snd:Stop() end
	end)
	banner("\xF0\x9F\x8D\xAD Listen for the jingle -- it gets louder as you get closer!", PAL.PINK)
end

-- ============================================================================
-- TOLL 2 -- FIX MY BRIDGE (hammer on the beat)
-- ============================================================================
-- Not "collect three planks": the planks are already there, broken, ON the bridge. Each is
-- seated with PLANK_TAPS taps landed ON the swing -- the same tap-on-the-beat the island 14
-- chainsaw uses, so a player who has felled a pine already knows this.
-- A loose plank prop: splintered ends, a nail at each end, and two grain stripes. The FIX MY
-- BRIDGE toll has you hammering these into the deck, so they are looked at closely and for
-- longer than any other toll prop -- a bare brown slab was the weakest thing in the set.
-- Returns a MODEL: every tap re-pivots the whole prop, so the detail travels with the board.
local function buildPlank(cf)
	local pm = Instance.new("Model"); pm.Name = "BrokenPlank"; pm.Parent = folder
	local function pb(props2, off)
		props2.Parent = pm
		local q = mk(props2); q.CFrame = cf * off; return track(q)
	end
	local board = pb({ Color = PAL.WOOD_D, Size = Vector3.new(3.4, 0.5, 5.2),
		CanQuery = true, CastShadow = true }, CFrame.new())
	pb({ Color = PAL.WOOD, Size = Vector3.new(0.75, 0.16, 5.25) }, CFrame.new(-0.85, 0.2, 0))
	pb({ Color = PAL.WOOD, Size = Vector3.new(0.5, 0.16, 5.25) }, CFrame.new(0.95, 0.2, 0))
	for _, sz in ipairs({ -1, 1 }) do
		for k = -1, 1 do
			-- three shrinking teeth per end, fanned apart: a clean cut reads as sawn, and a
			-- sawn plank does not look broken
			pb({ Color = PAL.WOOD_D, Size = Vector3.new(0.75, 0.44, 0.6 - math.abs(k) * 0.16) },
				CFrame.new(k * 1.0, 0.02 + k * 0.06, sz * 2.75)
					* CFrame.Angles(math.rad(sz * k * 10), 0, 0))
		end
		pb({ Color = Color3.fromRGB(96, 96, 104), Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.3, 0.16, 0.3) }, CFrame.new(0, 0.3, sz * 1.9))
	end
	pm.PrimaryPart = board
	return pm, board
end

local function startBridge(bridges)
	planksLeft = PLANKS_NEEDED
	local made = 0
	for _, b in ipairs(bridges) do
		if made >= PLANKS_NEEDED then break end
		local bp = firstBasePart(b)
		if bp then
			local n = math.min(PLANKS_NEEDED - made, 2)
			for k = 1, n do
				made += 1
				local along = (k / (n + 1)) - 0.5
				local at = bp.CFrame * CFrame.new(bp.Size.X * along * 0.7, bp.Size.Y * 0.5 + 0.3, 0)
				local pm, plank = buildPlank(at * CFrame.Angles(math.rad(9), 0, math.rad(6)))
				local hl = Instance.new("Highlight")
				hl.FillTransparency = 1; hl.OutlineColor = PAL.GOLD; hl.OutlineTransparency = 0.15
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Adornee = plank; hl.Parent = plank

				local taps = 0
				local pr = Instance.new("ProximityPrompt")
				pr.ActionText = "Hammer"; pr.ObjectText = "Broken Plank"
				pr.HoldDuration = 0; pr.MaxActivationDistance = 12; pr.RequiresLineOfSight = false
				pr.Parent = plank
				pr.Triggered:Connect(function()
					taps += 1
					-- each tap knocks it flatter and squarer
					local f = taps / PLANK_TAPS
					-- PivotTo, not plank.CFrame: the board is one part of a model now, and
					-- moving it alone would leave its splinters and nails behind in mid-air.
					pm:PivotTo(at * CFrame.Angles(math.rad(9 * (1 - f)), 0, math.rad(6 * (1 - f))))
					if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
					for i = 1, 4 do
						local chip = mk({ Color = PAL.WOOD, Size = Vector3.new(0.3, 0.3, 0.3),
							CFrame = plank.CFrame * CFrame.new((math.random() - 0.5) * 3, 0.5, (math.random() - 0.5) * 3),
							Parent = folder })
						TweenService:Create(chip, TweenInfo.new(0.5), {
							CFrame = chip.CFrame * CFrame.new(0, 4, 0), Transparency = 1 }):Play()
						Debris:AddItem(chip, 0.6)
					end
					if taps >= PLANK_TAPS then
						pr.Enabled = false
						hl:Destroy()
						plank.Color = PAL.WOOD
						pm:PivotTo(at)
						planksLeft -= 1
						refreshObjective()
						if planksLeft <= 0 then
							setTrollPrompts(true)   -- job done: he can be talked to again
							banner("\xF0\x9F\xAA\xB5 Bridge fixed! Go and tell the Troll.", PAL.GOLD)
							flash("\xF0\x9F\xAA\xB5 Bridge fixed -- tell the Troll!", 3)
						else
							flash(("\xF0\x9F\xAA\xB5 Plank in!  %d to go"):format(planksLeft), 2.5)
						end
					else
						flash(("\xF0\x9F\xAA\xB5 %d more taps on this plank"):format(PLANK_TAPS - taps), 1.6)
					end
				end)
			end
		end
	end
	if made == 0 then
		-- no bridge in the world to break: fall back so the toll is still completable
		planksLeft = 0
		warn("[Troll] no 'bridge' part found for the FIX MY BRIDGE toll -- passing it automatically")
	end
	-- his prompt goes quiet until the last plank is in (see setTrollPrompts)
	if made > 0 then setTrollPrompts(false) end
	banner(("\xF0\x9F\xAA\xB5 %d planks are broken -- hammer them back in!"):format(PLANKS_NEEDED), PAL.GOLD)
end

-- ============================================================================
-- TOLL 3 -- BRING ME CANDY (identify and choose)
-- ============================================================================
-- Four candies are laid out, each a different colour. He names ONE. Bringing the wrong one is
-- allowed and answered in character -- that is the whole game: read the ask, pick correctly.
local CANDY_KINDS = {
	{ name = "RED",   colour = PAL.RED },
	{ name = "MINT",  colour = PAL.MINT },
	{ name = "GRAPE", colour = PAL.PURPLE },
	{ name = "PINK",  colour = PAL.PINK_L },
}

local function startCandy()
	wantCandy = CANDY_KINDS[math.random(1, #CANDY_KINDS)]
	local centre = (active and active.head and active.head.Position)
		or (firstHead() and firstHead().Position) or Vector3.new()
	local marked = takeSpots(#CANDY_KINDS)
	for i, kind in ipairs(CANDY_KINDS) do
		local pos = marked[i]
		if not pos then
			-- no marker for this one: fall back to the computed ring, ray-seated
			local a = (i / #CANDY_KINDS) * math.pi * 2 + 0.7
			local r = 55 + (i % 3) * 22
			local at = centre + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { player.Character, folder }
			local hit = Workspace:Raycast(at + Vector3.new(0, 120, 0), Vector3.new(0, -400, 0), rp)
			pos = (hit and hit.Position or at) + Vector3.new(0, 1.25, 0)
		end

		local m = buildProp("candy", kind.colour)
		m:PivotTo(CFrame.new(pos))
		m.Parent = folder
		track(m.PrimaryPart)
		task.spawn(function()
			local t = i * 0.8
			while m.Parent do
				t += 0.05
				m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, t * 0.5, 0))
				task.wait(0.05)
			end
		end)
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = "Take"; pr.ObjectText = kind.name .. " Candy"
		pr.HoldDuration = 0; pr.MaxActivationDistance = 12; pr.RequiresLineOfSight = false
		pr.Parent = m.PrimaryPart
		pr.Triggered:Connect(function()
			if carrying then flash("\xF0\x9F\x8D\xAC Your hands are full!", 2); return end
			giveHeld("candy", kind.colour)
			carrying = "candy"
			-- remember WHICH one is in hand, so the hand-in can judge it
			if heldModel then heldModel:SetAttribute("CandyName", kind.name) end
			flash(("\xF0\x9F\x8D\xAC You picked up the %s candy"):format(kind.name), 2.5)
		end)
	end
	banner(("\xF0\x9F\x8D\xAC The Troll wants the %s one. Find it!"):format(wantCandy.name), PAL.PINK)
end

-- ============================================================================
-- TOLL 4 -- GET ME A DRINK (the awkward carry)
-- ============================================================================
-- The cup is enormous. You walk at DRINK_SPEED and it SLOPS: run about with it and it empties,
-- and you go back for a refill. Nothing to find -- the walk itself is the job.
local drinkSpilled
local function startDrink()
	-- ⚠ JUST THE SODA, ON A MARKER -- like the lollipop and the candies.
	-- This used to raise a whole fountain here: counter, back panel, striped awning, tank,
	-- tap, drip tray, a stack of spare cups and SODA in 90px letters, all at a computed point
	-- 95 studs out. That is a building, and buildings do not belong to a toll that lasts one
	-- errand -- it also landed wherever the ring maths put it, walls and ledges included.
	-- The cup now sits on one of YOUR 'gumball' markers, seated on the ground, and a spill
	-- simply puts it back there.
	local pick = takeSpots(1)
	local pos = pick[1]
	if not pos then
		-- no markers placed: fall back to the old computed ring, ray-seated
		local centre = (active and active.head and active.head.Position)
			or (firstHead() and firstHead().Position) or Vector3.new()
		local a = math.random() * math.pi * 2
		local at = centre + Vector3.new(math.cos(a) * 95, 0, math.sin(a) * 95)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { player.Character, folder }
		local hit = Workspace:Raycast(at + Vector3.new(0, 140, 0), Vector3.new(0, -400, 0), rp)
		pos = (hit and hit.Position or at) + Vector3.new(0, 2.4, 0)
	end

	local cup = buildProp("drink", PAL.PURPLE)
	cup:PivotTo(CFrame.new(pos))
	cup.Parent = folder
	track(cup.PrimaryPart)
	-- the same slow turn the other toll props use, so it reads as pick-up-able
	task.spawn(function()
		local t = 0
		while cup.Parent and cup.PrimaryPart do
			t += 0.05
			cup:PivotTo(CFrame.new(pos) * CFrame.Angles(0, t * 0.5, 0))
			task.wait(0.05)
		end
	end)

	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = "Take The Drink"; pr.ObjectText = "Giant Candy Soda"
	pr.HoldDuration = 0.3; pr.MaxActivationDistance = 14; pr.RequiresLineOfSight = false
	pr.Parent = cup.PrimaryPart
	pr.Triggered:Connect(function()
		if carrying then flash("\xF0\x9F\xA5\xA4 Your hands are full!", 2); return end
		giveHeld("drink", PAL.PURPLE)
		drinkSpilled = 0
		cup.PrimaryPart.Transparency = 1
		for _, p in ipairs(cup:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = 1 end end
		banner("\xF0\x9F\xA5\xA4 Careful! Walk it back -- run and you'll slop it.", PAL.PURPLE)
	end)

	-- THE SLOP WATCHER. Speed over the walk pace costs you; standing still lets it settle.
	task.spawn(function()
		while tollActive and toll == "drink" do
			task.wait(0.2)
			if carrying == "drink" then
				local hrp = hrpOf()
				local speed = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
				local walk = 16 * DRINK_SPEED
				if speed > walk + 3 then
					drinkSpilled = (drinkSpilled or 0) + 0.2
					if drinkSpilled >= DRINK_SPILL then
						-- ⚠ THE SPILL COSTS YOU THE WHOLE WALK BACK, and until now it was two
						-- lines of text. A splash where it happened is what makes it land as
						-- YOUR mistake rather than the quest being fussy: droplets burst up,
						-- and a purple puddle stays on the ground for a few seconds as the mark.
						local hrpS = hrpOf()
						if hrpS then
							local at2 = hrpS.Position - Vector3.new(0, 2.6, 0)
							for i = 1, 14 do
								local a2 = i * 2.39996
								local d = mk({ Color = PAL.PURPLE, Shape = Enum.PartType.Ball,
									Size = Vector3.new(0.42, 0.42, 0.42),
									CFrame = CFrame.new(at2 + Vector3.new(0, 1.2, 0)),
									Parent = folder })
								TweenService:Create(d, TweenInfo.new(0.7,
									Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
									CFrame = CFrame.new(at2 + Vector3.new(math.cos(a2) * 4,
										-0.6, math.sin(a2) * 4)), Transparency = 1 }):Play()
								Debris:AddItem(d, 0.9)
							end
							local pud = mk({ Color = PAL.PURPLE, Shape = Enum.PartType.Cylinder,
								Size = Vector3.new(0.12, 1, 1), Transparency = 0.25,
								CFrame = CFrame.new(at2 + Vector3.new(0, 0.1, 0))
									* CFrame.Angles(0, 0, math.rad(90)), Parent = folder })
							track(pud)
							TweenService:Create(pud, TweenInfo.new(0.45), {
								Size = Vector3.new(0.12, 7, 7) }):Play()
							TweenService:Create(pud, TweenInfo.new(5.5), { Transparency = 1 }):Play()
							Debris:AddItem(pud, 5.8)
						end
						dropHeld()
						for _, p in ipairs(cup:GetDescendants()) do
							if p:IsA("BasePart") then p.Transparency = 0 end
						end
						if cup.PrimaryPart then cup.PrimaryPart.Transparency = 0 end
						banner("\xF0\x9F\x92\xA6 You slopped it everywhere! Go and refill.", PAL.PURPLE)
						flash("\xF0\x9F\x92\xA6 Spilled! The soda is back where you found it.", 3)
					elseif drinkSpilled % 2 < 0.2 then
						flash("\xF0\x9F\xA5\xA4 Slow down -- it's sloshing!", 1.8)
					end
				elseif drinkSpilled and drinkSpilled > 0 then
					drinkSpilled = math.max(0, drinkSpilled - 0.05)
				end
			end
		end
	end)
	banner("\xF0\x9F\xA5\xA4 Find his soda and bring it back WITHOUT running!", PAL.PURPLE)
end

-- ============================================================================
-- HANDING THE TOLL IN
-- ============================================================================
local TOLL_NAMES = { lolly = "lollipop", bridge = "bridge repair", candy = "candy", drink = "drink" }

local function payToll()
	paid = true
	tollActive = false
	_G.trollTollPaid = true
	-- ⚠ THIS IS ISLAND 1'S LADDER RUNG NOW, AND IT MUST FIRE.
	-- IslandConfig gives island 1 `questId = "candy"` with `gutUnlock = { unlocksTier = 2 }`,
	-- and IslandTaskWatcher pays that rung off `_G.candyQuestComplete`. Tier 1 is max = 0 --
	-- NOBODY CAN FLY until island 1's quest completes -- so the toll has to raise the same
	-- flag the retired gumball quest used to, or paying it would leave the player grounded on
	-- the tutorial island with no way up the tower.
	_G.candyQuestComplete = true
	dropHeld()
	setTrollPrompts(true)   -- belt and braces: never leave a prompt muted after the toll ends
	refreshObjective()

	-- he shuffles aside and lets you through
	-- BOTH BROTHERS STAND ASIDE. You paid one of them; word travels, and a second troll still
	-- blocking a bridge you have already bought passage over would just read as a bug.
	for _, t in ipairs(trolls) do
		if t.rig and t.rig.home and not t.moved then
			t.moved = true
			local rg = t.rig
			-- Slide HOME, not the model: the idle loop re-asserts rig.home every frame, so a
			-- PivotTo here was snapped straight back and the paid troll never actually moved.
			-- Moving the value the loop reads makes the loop itself carry him aside -- breathing,
			-- waving and all.
			local from, aside = rg.home, rg.home * CFrame.new(-7.5, 0, 0)
			rg.wave = true
			task.delay(2.6, function() rg.wave = nil end)
			task.spawn(function()
				for a = 0, 1, 0.03 do
					if not t.model.Parent then return end
					rg.home = from:Lerp(aside, a)
					task.wait(0.03)
				end
				rg.home = aside
			end)
		elseif t.model and t.model.PrimaryPart and not t.moved then
			-- an adopted hand-placed troll has no rig; the plain slide still works for it
			t.moved = true
			local from = t.model:GetPivot()
			local aside = from * CFrame.new(-7.5, 0, 0)
			task.spawn(function()
				for a = 0, 1, 0.04 do
					if not t.model.Parent then return end
					t.model:PivotTo(from:Lerp(aside, a))
					task.wait(0.02)
				end
			end)
		end
	end
	-- ---- INTO THE CHEST ------------------------------------------------------------------
	-- The lid swings on its back edge, a candy arcs in, the lid drops. This is the receipt for
	-- everything the toll asked of you, and the reason the chest exists at all.
	do
		local t0 = active or trolls[1]
		if t0 and t0.lid and t0.mouth and t0.hinge then
			local lid, hinge = t0.lid, t0.hinge
			local rest = lid.CFrame
			local openCF = hinge * CFrame.Angles(math.rad(-102), 0, 0)
				* (hinge:Inverse() * rest)
			TweenService:Create(lid, TweenInfo.new(0.3, Enum.EasingStyle.Back,
				Enum.EasingDirection.Out), { CFrame = openCF }):Play()

			local gift = mk({ Color = PAL.PINK, Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.1, 1.0, 1.0),
				CFrame = t0.mouth * CFrame.new(0, 4.5, -2.5), Parent = folder })
			TweenService:Create(gift, TweenInfo.new(0.42, Enum.EasingStyle.Quad,
				Enum.EasingDirection.In), { CFrame = t0.mouth }):Play()
			Debris:AddItem(gift, 0.5)

			task.delay(0.5, function()
				if not lid.Parent then return end
				TweenService:Create(lid, TweenInfo.new(0.16, Enum.EasingStyle.Quad,
					Enum.EasingDirection.In), { CFrame = rest }):Play()
				task.wait(0.18)
				-- a puff of dust off the box as the lid lands: the slam needs a consequence
				for i = 1, 8 do
					local d = mk({ Color = PAL.CREAM, Size = Vector3.new(0.28, 0.28, 0.28),
						CFrame = t0.mouth * CFrame.new((math.random() - 0.5) * 3.2, 0.2,
							(math.random() - 0.5) * 2.4), Parent = folder })
					TweenService:Create(d, TweenInfo.new(0.6), {
						CFrame = d.CFrame * CFrame.new(0, 1.6, 0), Transparency = 1 }):Play()
					Debris:AddItem(d, 0.7)
				end
			end)
		end
	end

	local payee = (active and active.head) or firstHead()
	if payee then showBubble(payee, "Alright, alright! You can cross! \xF0\x9F\x8D\xAD", true) end
	-- the other brother gets his own line, so the second bridge explains itself
	for _, t in ipairs(trolls) do
		if t.head and t.head ~= payee then
			showBubble(t.head, "Me brother says you're alright. On you go!", false)
		end
	end
	banner("\xF0\x9F\x8D\xAD Toll paid -- Trollland is open!", PAL.GOLD)

	-- confetti over the gate
	if landCF then
		for i = 1, 26 do
			local c = mk({ Color = ({ PAL.PINK, PAL.GOLD, PAL.MINT, PAL.PURPLE })[(i % 4) + 1],
				Size = Vector3.new(0.5, 0.5, 0.5),
				CFrame = landCF * CFrame.new((math.random() - 0.5) * 20, 14, (math.random() - 0.5) * 6),
				Parent = folder })
			TweenService:Create(c, TweenInfo.new(1.6), {
				CFrame = c.CFrame * CFrame.new(0, -14, 0), Transparency = 1 }):Play()
			Debris:AddItem(c, 1.8)
		end
	end
	print("[Troll] toll paid -- Trollland unlocked for this player")
end

-- can the toll currently be handed in?
local function tollReady()
	if toll == "bridge" then return planksLeft <= 0 end
	if toll == "lolly"  then return carrying == "lolly" end
	if toll == "drink"  then return carrying == "drink" end
	if toll == "candy"  then
		return carrying == "candy" and heldModel
			and heldModel:GetAttribute("CandyName") == (wantCandy and wantCandy.name)
	end
	return false
end

-- ============================================================================
-- THE TROLL'S DIALOGUE
-- ============================================================================
local TOLL_ASK = {
	lolly  = { "Oi! Toll first.", "I lost me favourite lollipop out there somewhere.",
	           "Fetch it and you can cross. Listen for the jingle!" },
	bridge = { "Oi! Toll first.", "Some rotter broke three planks of me bridge.",
	           "Hammer 'em back in and you can cross." },
	candy  = { "Oi! Toll first.", "I'm STARVING up here.",
	           "Bring me the right candy and you can cross. Don't guess!" },
	drink  = { "Oi! Toll first.", "Guarding a bridge is thirsty work.",
	           "Fetch me soda WITHOUT running. Slop it and you refill it." },
}

local function questPages()
	if paid then
		return { "Alright, alright! You can cross! \xF0\x9F\x8D\xAD", "Trollland's all yours, little one." }
	end
	if not tollActive then
		return { "Oi! Nobody crosses my bridge for free.", "Pay the toll and Trollland's yours." }
	end
	if tollReady() then
		return { "Ohhh, lovely. Hand it here!" }
	end
	if toll == "candy" and carrying == "candy" then
		return { ("That's not the %s one!"):format(wantCandy and wantCandy.name or "right"),
			"Put it back. Bring me the right one." }
	end
	local pg = TOLL_ASK[toll]
	if pg then return { pg[2] or "Get on with it!", pg[3] or "" } end
	return { "Get on with it!" }
end

local function rollToll()
	local options = { "lolly", "bridge", "candy", "drink" }
	toll = options[math.random(1, #options)]
	tollActive = true
	refreshObjective()
	if toll == "lolly" then startLolly()
	elseif toll == "bridge" then
		local bridges = {}
		if island then
			for _, d in ipairs(island:GetDescendants()) do
				if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == BRIDGE_NAME then
					bridges[#bridges + 1] = d
				end
			end
		end
		startBridge(bridges)
	elseif toll == "candy" then startCandy()
	else startDrink() end
	print("[Troll] toll rolled: " .. toll)
end

local function wireTroll(t)
	local head = t.head
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"; prompt.ObjectText = t.name .. " the Candy Troll"
	prompt.HoldDuration = 0; prompt.MaxActivationDistance = TALK_RANGE
	prompt.RequiresLineOfSight = false; prompt.Parent = head
	trollPrompts[#trollPrompts + 1] = prompt

	local pages, index = nil, 0
	local function close() hideBubble(head); prompt.ActionText = "Talk"; index = 0; pages = nil end

	prompt.Triggered:Connect(function()
		if paid then
			showBubble(head, "Alright, alright! You can cross! \xF0\x9F\x8D\xAD", false)
			return
		end
		-- ⚠ ONE JOB AT A TIME. If the OTHER brother already set you a toll, this one refuses to
		-- set a second: two live tolls means two props for one pair of hands and an objective
		-- line that cannot say which job you are on. He sends you back rather than stacking.
		if tollActive and active and active ~= t then
			showBubble(head, ("Oi, me brother %s set you a job already. Finish that first!")
				:format(active.name), false)
			flash(("\xF0\x9F\x8C\x89 Finish %s's toll first!"):format(active.name), 3)
			return
		end
		-- HANDING IN BEATS TALKING: with the goods in hand, one press finishes the job
		if tollActive and tollReady() then
			payToll(); close(); return
		end
		if index == 0 then
			if not tollActive then active = t; rollToll() end
			local base = tollActive and TOLL_ASK[toll] or questPages()
			pages = (_G.capBubble and _G.capBubble(base)) or base
		end
		index += 1
		if not pages or index > #pages then close(); return end
		showBubble(head, pages[index], true)
		prompt.ActionText = (index >= #pages) and "Close" or ("Continue  (%d/%d)"):format(index, #pages)
	end)
	prompt.PromptHidden:Connect(function() if index ~= 0 then close() end end)
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	island = pollFor(function()
		local x = Workspace:FindFirstChild(ISLAND_NAME)
		if x then return x end
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and d.Name:lower():match("^island_?1$") then return d end
		end
		return nil
	end, 60)
	local scope = island or Workspace

	-- ---- ONE TROLL PER BRIDGE ------------------------------------------------------------
	-- Gather every hand-placed troll first (a Model is adopted whole, a Part is a position
	-- marker), then every bridge. A troll is stood at the mouth of each bridge that does not
	-- already have one within 40 studs, so hand-placing one, both or neither all work.
	local placedModels, placedMarkers, bridges, signSpots = {}, {}, {}, {}
	for _, d in ipairs(scope:GetDescendants()) do
		local n = norm(d.Name)
		if n == TROLL_NAME then
			if d:IsA("Model") and d:FindFirstChildWhichIsA("BasePart", true) then
				placedModels[#placedModels + 1] = d
			elseif d:IsA("BasePart") then
				placedMarkers[#placedMarkers + 1] = d
			end
		elseif n == BRIDGE_NAME and (d:IsA("BasePart") or d:IsA("Model")) then
			local bp = firstBasePart(d)
			if bp then bridges[#bridges + 1] = bp end
		elseif n == SIGN_NAME then
			local sp = firstBasePart(d)
			if sp then signSpots[#signSpots + 1] = sp end
		elseif n == SPOT_NAME and d:IsA("BasePart") then
			-- position only: hide the brick, keep the point just above its top face
			d.Transparency = 1; d.CanCollide = false; d.CanQuery = false
			spots[#spots + 1] = d.Position + Vector3.new(0, d.Size.Y * 0.5 + 1.2, 0)
		end
	end

	local NAMES = { "Grumbles", "Snaggle", "Boulder", "Mossy" }
	local function addTroll(model, head, rig, why)
		trolls[#trolls + 1] = { model = model, head = head, rig = rig,
			name = NAMES[((#trolls) % #NAMES) + 1] }
		-- HIS NAME OVER HIS HEAD. Two named brothers guard two bridges; without the tag the
		-- pay-off line "me brother says you're alright" has nothing to hang on.
		if head then
			local bb = Instance.new("BillboardGui")
			bb.Name = "TrollTag"; bb.Adornee = head
			bb.Size = UDim2.new(0, 190, 0, 44); bb.StudsOffset = Vector3.new(0, 4.6, 0)
			bb.MaxDistance = 70; bb.AlwaysOnTop = false; bb.Parent = head
			local l1 = Instance.new("TextLabel")
			l1.Size = UDim2.new(1, 0, 0.58, 0); l1.BackgroundTransparency = 1
			l1.Font = Enum.Font.LuckiestGuy; l1.TextScaled = true
			l1.TextColor3 = PAL.PINK; l1.TextStrokeTransparency = 0.2
			l1.TextStrokeColor3 = Color3.fromRGB(60, 30, 46)
			l1.Text = trolls[#trolls].name; l1.Parent = bb
			local l2 = Instance.new("TextLabel")
			l2.Size = UDim2.new(1, 0, 0.42, 0); l2.Position = UDim2.new(0, 0, 0.58, 0)
			l2.BackgroundTransparency = 1; l2.Font = Enum.Font.FredokaOne; l2.TextScaled = true
			l2.TextColor3 = PAL.CREAM; l2.TextStrokeTransparency = 0.4
			l2.TextStrokeColor3 = Color3.fromRGB(60, 30, 46)
			l2.Text = "PAY THE TOLL"; l2.Parent = bb
			trolls[#trolls].tagSub = l2
		end
		-- Every troll breathes, watches you and taps his club -- including one you hand-placed
		-- in Studio, IF it carries the rig groups. animateTroll returns quietly when it does not,
		-- so an adopted plain model is left exactly as built.
		pcall(animateTroll, model, head, rig)
		print(("[Troll] troll %d (%s) %s"):format(#trolls, trolls[#trolls].name, why))
	end

	for _, m in ipairs(placedModels) do
		addTroll(m, m:FindFirstChild("Head") or firstBasePart(m), nil, "adopted from " .. m:GetFullName())
	end
	for _, mk2 in ipairs(placedMarkers) do
		local at = CFrame.new(mk2.Position - Vector3.new(0, mk2.Size.Y * 0.5, 0))
			* (mk2.CFrame - mk2.CFrame.Position)
		mk2.Transparency = 1; mk2.CanCollide = false; mk2.CanQuery = false
		local m, h, rg = buildTroll(at)
		addTroll(m, h, rg, "built on your '" .. mk2.Name .. "' marker")
	end

	-- a troll on every bridge that has not got one yet
	for _, bp in ipairs(bridges) do
		local covered = false
		for _, t in ipairs(trolls) do
			if t.head and (t.head.Position - bp.Position).Magnitude <= 40 then covered = true; break end
		end
		if not covered then
			-- ⚠ SEAT HIM ON THE PLANKS, NOT IN THE AIR. `bp.Size.Y * 0.5` is half the part's
			-- LOCAL height, which is only the distance to the deck when the bridge is a flat,
			-- unrotated slab; on a tilted or oddly-pivoted bridge it lands him hovering (or
			-- sunk). Raycasting straight down onto the bridge ITSELF -- an Include filter, so
			-- nothing else can be hit -- gives the true surface every time. The feet are built
			-- at y = 0 in the troll's frame, so the hit point IS where he stands.
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Include
			rp.FilterDescendantsInstances = { bp }
			local hit = Workspace:Raycast(bp.Position + Vector3.new(0, bp.Size.Y + 60, 0),
				Vector3.new(0, -(bp.Size.Y + 200), 0), rp)
			local deckY = hit and hit.Position.Y or (bp.Position.Y + bp.Size.Y * 0.5)

			-- The bridge's own rotation, and nothing else. TROLL_YAW (applied inside buildTroll)
			-- is the single knob; no code here reads the island, the axis or the player.
			local at = CFrame.new(Vector3.new(bp.Position.X, deckY, bp.Position.Z))
				* (bp.CFrame - bp.CFrame.Position)
			local m, h, rg = buildTroll(at)
			print(("[Troll] seated on '%s' at Y=%.1f (%s), TROLL_YAW=%d (the only turn applied)")
				:format(bp.Name, deckY, hit and "raycast" or "bounding box -- no ray hit", TROLL_YAW))
			addTroll(m, h, rg, ("built at the bridge '%s'"):format(bp.Name))
			-- his strongbox, at his off-staff side so it never fouls the swing
			local cm, clid, cmouth, chinge = buildTollChest(at * CFrame.new(-4.6, 0, 1.0))
			local rec = trolls[#trolls]
			rec.chest, rec.lid, rec.mouth, rec.hinge = cm, clid, cmouth, chinge
		end
	end

	if #trolls == 0 then
		-- no trolls and no bridges: put one at the island's centre so the quest still exists
		local ok, cf = pcall(function() return (select(1, scope:GetBoundingBox())) end)
		local m, h, rg = buildTroll((ok and cf) and CFrame.new(cf.Position) or CFrame.new())
		addTroll(m, h, rg, "built at the island centre (no bridges found)")
		warn("[Troll] no parts named 'bridge' on island1 -- one troll placed centrally. "
			.. "Name the bridge parts 'bridge' and a troll appears at each.")
	end
	print(("[Troll] %d bridge(s) found -> %d troll(s) on duty"):format(#bridges, #trolls))
	-- ---- THE FAR TROLL FACES THE OTHER WAY --------------------------------------------
	-- Both trolls get the same TROLL_YAW off their bridge parts, but the two bridges leave the
	-- island in roughly opposite directions -- so one brother ended up with his back to the
	-- players walking up. The one FARTHEST from spawn is turned 180. Spawn is read from the
	-- island's own SpawnLocation, with your character's boot position as the fallback.
	do
		local spawnPos
		for _, d in ipairs(scope:GetDescendants()) do
			if d:IsA("SpawnLocation") then spawnPos = d.Position; break end
		end
		if not spawnPos then
			local hrp0 = hrpOf()
			spawnPos = hrp0 and hrp0.Position
		end
		if spawnPos and #trolls > 1 then
			local far, farD
			for _, t in ipairs(trolls) do
				if t.head and t.head.Parent then
					local d = (t.head.Position - spawnPos).Magnitude
					if not farD or d > farD then farD, far = d, t end
				end
			end
			if far and far.rig and far.rig.home then
				far.rig.home = far.rig.home * CFrame.Angles(0, math.pi, 0)
				print(("[Troll] %s is farthest from spawn (%.0f studs) -> flipped 180")
					:format(far.name, farD))
			elseif far and far.model then
				far.model:PivotTo(far.model:GetPivot() * CFrame.Angles(0, math.pi, 0))
				print(("[Troll] %s (adopted) is farthest from spawn -> flipped 180"):format(far.name))
			end
		end
	end

	if #spots > 0 then
		print(("[Troll] reusing %d '%s' marker(s) from the retired Gumball Hunt as the lollipop "
			.. "and candy spots"):format(#spots, SPOT_NAME))
	else
		print(("[Troll] no '%s' parts found -- lollipop and candy fall back to a computed ring")
			:format(SPOT_NAME))
	end

	-- ---- signs on every 'signplacement' marker -------------------------------------------
	for _, sp in ipairs(signSpots) do
		-- seat on the marker's BASE, keep its yaw, then hide it (markers are position, not prop)
		local at2 = CFrame.new(sp.Position - Vector3.new(0, sp.Size.Y * 0.5, 0))
			* (sp.CFrame - sp.CFrame.Position)
		sp.Transparency = 1; sp.CanCollide = false; sp.CanQuery = false
		-- the lean comes from the marker's own coordinates, so it is crooked the same way on
		-- every boot -- random would re-lean the sign each join, which reads as instability
		local wob = ((sp.Position.X * 7 + sp.Position.Z * 13) % 9) - 4
		local nearTroll, nd
		for _, t in ipairs(trolls) do
			if t.head and t.head.Parent then
				local d = (t.head.Position - sp.Position).Magnitude
				if not nd or d < nd then nd, nearTroll = d, t.head.Position end
			end
		end
		buildSignPost(at2, wob, nearTroll)
		print(("[Troll] sign built on your '%s' marker at %d, %d, %d")
			:format(sp.Name, sp.Position.X, sp.Position.Y, sp.Position.Z))
	end
	if #signSpots == 0 then
		print("[Troll] no 'signplacement' part found -- name a part 'signplacement' on island1 "
			.. "and a TROLLLAND notice is built standing on it (its -Z is the way it faces).")
	end

	-- ---- Trollland: read the marker's footprint, or claim the far side of the bridge
	for _, d in ipairs(scope:GetDescendants()) do
		if norm(d.Name) == LAND_NAME then
			local bp = firstBasePart(d)
			if bp then landPart = bp; break end
		end
	end
	if landPart then
		landCF, landHalf = landPart.CFrame, landPart.Size * 0.5
		-- HIDDEN AGAIN, ON PURPOSE. This block is a MARKER -- it says where the park is, and
		-- nothing more. It was briefly tinted pink at 0.55 so the restricted area would be
		-- visible, but a 153 x 152 x N translucent slab sitting over the whole park is a wall
		-- of haze you look at from every angle, and it overhangs the island so it hung out
		-- over the water too. The arch and the signs mark the boundary where a player actually
		-- meets it; the zone itself needs no skin.
		-- LEFT EXACTLY AS YOU BUILT IT: its own colour, its own transparency, its own material.
		-- This block has been tinted pink, hidden outright, and then hidden again over the last
		-- few rounds -- all of it my doing, none of it asked for. It is YOUR park; the script
		-- only reads the footprint from it now and changes nothing you can see. The two flags
		-- below are the sole exception, and they are behaviour, not looks: without them the
		-- slab would physically block the crossing and swallow every ground raycast.
		-- COLLISION ON, as you asked -- the park block is solid ground now, not a ghost
		-- volume. The per-player barrier still does the gating: it throws an unpaid player
		-- back out, and that is unchanged by the block being walkable.
		landPart.CanCollide = true
		-- ⚠ Queries stay OFF. Ground raycasts (toll props, candy trees, sign posts, the troll's
		-- own foot seating) would otherwise hit the TOP of this 153 x 152 slab instead of the
		-- island under it, and everything would spawn on its roof. Say the word if you want
		-- rays to see it too.
		landPart.CanQuery = false

		-- NO PAINTED FLOOR HERE, DELIBERATELY. A floor plate + edge stripe across the whole
		-- 153 x 152 footprint was tried and removed: the block overhangs the island, so the
		-- plate hung out over open water and read as a hard outline drawn across it. The
		-- perimeter posts below are ground-raycast one by one, so they only ever land on
		-- real terrain and the boundary stays readable without painting the sea.
		print(("[Troll] Trollland read from your '%s' block (%.0f x %.0f studs) -- your colour left alone")
			:format(landPart.Name, landPart.Size.X, landPart.Size.Z))

		-- NO PERIMETER POSTS. Candy poles with pink tops were planted every 14 studs around
		-- this footprint and they were the wrong call twice over: the block overhangs the
		-- island, so a long run of them stood in mid-air under the platform and out over the
		-- water, and even the well-seated ones were visual noise nobody asked for. The tinted
		-- volume above is the boundary now. (They regenerate every boot, so deleting them in
		-- Studio would not have stuck -- this is the only place that can remove them.)
		-- and a warning if the park swallows a troll's approach entirely
		for _, t in ipairs(trolls) do
			if t.head then
				local o = landCF:PointToObjectSpace(t.head.Position)
				if math.abs(o.X) <= landHalf.X and math.abs(o.Z) <= landHalf.Z then
					warn(("[Troll] %s stands INSIDE Trollland -- his %d-stud safe bubble is what "
						.. "lets you reach him. If the park is meant to start past the bridge, "
						.. "shrink the '%s' block so it does not cover the crossing.")
						:format(t.name, TROLL_SAFE, landPart.Name))
				end
			end
		end
	elseif trolls[1] and trolls[1].model then
		-- no block: claim a park-sized patch just past the FIRST troll
		local base = trolls[1].model:GetPivot()
		landCF = base * CFrame.new(0, 0, 34)
		landHalf = Vector3.new(30, 12, 26)
		warn("[Troll] no 'trollland' block found -- claimed a 60 x 52 patch past the first troll. "
			.. "Draw a block named 'trollland' over the park to set it exactly.")
	end

	-- ---- A GATE AT EVERY WAY IN. One arch on the zone's near edge, plus one standing at
	-- each troll, so whichever bridge a player walks up to is signed as the Troll's territory.
	-- ONE arch per troll, at the mouth of HIS bridge. The zone-edge arch that used to stand
	-- here as well put a second one out on the far bank with no crossing under it.
	if landCF and landHalf then
		for _, t in ipairs(trolls) do
			if t.model then
				local at = t.model:GetPivot()
				buildGate(CFrame.new(at.Position) * (at - at.Position) * CFrame.new(0, 0, 9), 22)
			end
		end
	end

	for _, t in ipairs(trolls) do
		if t.head then wireTroll(t) end
	end
	refreshObjective()
	print(("[Troll] ready -- %d troll(s) wired, Trollland %s, punish=%s")
		:format(#trolls, landCF and "set" or "MISSING", PUNISH))
	_G.questBuilt_trolltoll = true
end)

-- ============================================================================
-- /toll -- DEV ONLY: re-roll the toll, or pay it outright
-- ============================================================================
local function onCommand(msg)
	if not _G.questDevOK then return end
	local t = tostring(msg or ""):lower()
	if t:sub(1, 5) == "/toll" then
		local arg = t:sub(7)
		if arg == "pay" then
			if not tollActive then rollToll() end
			payToll()
			print("[Troll][TEST] /toll pay -- toll paid, Trollland open")
		else
			paid = false; _G.trollTollPaid = false
			tollActive = false; dropHeld()
			for _, p in ipairs(props) do pcall(function() p:Destroy() end) end
			props = {}
			rollToll()
			print("[Troll][TEST] /toll -- re-rolled: " .. tostring(toll))
		end
	end
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
