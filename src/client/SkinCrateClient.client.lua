-- ============================================================================================================
-- SKIN CRATE CLIENT -- the crate shop, the CS:GO-style reveal, and the skin inventory.
-- ============================================================================================================
-- THE CLIENT NEVER DECIDES A REWARD. It asks the server to open a crate, receives the already-granted result
-- (including the reel index it must stop on), and animates to exactly that item. Tampering with this file can
-- change what the animation looks like and nothing else -- the item is decided and saved before the reel moves.
--
-- THREE TABS in one 700x520 panel, matching the Shop panel's geometry, palette and fonts so the cosmetics menu
-- reads as part of the same game:
--   CRATES     -- one card per crate: icon, blurb, token price, OPEN. Plus the real odds, printed from the
--                 SAME shared table the server rolls on.
--   INVENTORY  -- every skin owned, with its trait and duplicate count. A skin for a pet you haven't unlocked
--                 still shows, reading "Unlock <Pet> to equip" -- never hidden.
--   TOKENS     -- the Robux token packs.
--
-- THE REEL (openReveal below) is the CS:GO case feel: a long horizontal strip of items scrolls left, fast at
-- first, easing to a crawl, and stops with the winning cell under the centre marker. A tick plays every time a
-- cell crosses the marker, so the slowdown is audible as well as visible. A Gold pull gets its own sound, a
-- gold flash, and a server-wide announcement.
-- ============================================================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")
local Debris            = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Shared      = ReplicatedStorage:WaitForChild("Shared")
local PetSkins    = require(Shared:WaitForChild("PetSkins"))
local PetTraits   = require(Shared:WaitForChild("PetTraits"))
local PetTier     = require(Shared:WaitForChild("PetTier"))
local SkinCrates  = require(Shared:WaitForChild("SkinCrates"))
local CrateTokens = require(Shared:WaitForChild("CrateTokens"))
local PetCollection = require(Shared:WaitForChild("PetCollection"))
local Gamepasses  = require(Shared:WaitForChild("Gamepasses"))

local SkinRemotes    = ReplicatedStorage:WaitForChild("SkinRemotes", 30)
local GetSkinState   = SkinRemotes:WaitForChild("GetSkinState")
local OpenCrate      = SkinRemotes:WaitForChild("OpenCrate")
local EquipSkin      = SkinRemotes:WaitForChild("EquipSkin")
local BuyTokens      = SkinRemotes:WaitForChild("BuyTokens")
local SkinStateEvent = SkinRemotes:WaitForChild("SkinStateEvent")
local GoldAnnounce   = SkinRemotes:WaitForChild("GoldAnnounce")
local AssignPetLevels = SkinRemotes:WaitForChild("AssignPetLevels")  -- c->s RF: pour pending levels into a pet
-- Set when the post-open level picker is built; called again whenever fresh state lands so the pet rows
-- follow hatches, trades and levels landing elsewhere.
local levelPickerRefresh = nil
local TradeUpRF      = SkinRemotes:WaitForChild("TradeUp")
local CollectAnnounce = SkinRemotes:WaitForChild("CollectAnnounce")
local FreeCrateReveal = SkinRemotes:WaitForChild("FreeCrateReveal")  -- s->c: a crate the server opened for us

-- ===== SOUNDS =====
-- REVEAL is the game's existing crate/wheel payoff sound, reused deliberately so the three random-reward systems
-- feel like one game. TICK is the UI click, which is short enough to read as a reel tick.
-- GOLD: upload a dedicated fanfare and paste its id here. Until then it plays the reveal sound pitched DOWN and
-- layered, which is distinctly different from a normal pull without risking a broken asset id.
local TICK_SOUND   = "rbxassetid://101638558691673"
local REVEAL_SOUND = "rbxassetid://4612378364"
local GOLD_SOUND   = nil -- e.g. "rbxassetid://<your gold fanfare>"

local function playSound(id, volume, pitch)
	if not id then return end
	local s = Instance.new("Sound")
	s.SoundId = id; s.Volume = volume or 0.5
	if pitch then s.PlaybackSpeed = pitch end
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
	return s
end

-- ===== HOUSE UI HELPERS (same shape as the Shop / HUD scripts) =====
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
-- ===== BorderSizePixel = 0 ON ALL THREE. READ THIS BEFORE REMOVING IT. =====
-- Roblox defaults every GuiObject to BorderSizePixel = 1 in BLACK, and that border is drawn as a SQUARE
-- rectangle that ignores UICorner. So every rounded thing this file builds -- cards, chips, pills, tiles,
-- the icon discs -- was being outlined by a 1px black box whose corners poked out past the rounding. That
-- shows up as little black dots at the corners of each card and a thin dark edge under the tab row, and it
-- is why the odds chips read as flat rectangles even though they have had a UICorner all along.
--
-- Setting it here rather than on each call site fixes it for every element in the panel at once, including
-- the ones written before this note. `body` already set it by hand, which is the tell that this had been
-- hit and patched in one place before.
--
-- It is set BEFORE the props loop, so any caller that genuinely wants a border can still pass one.
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.BorderSizePixel = 0; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); f.BorderSizePixel = 0; for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); b.BorderSizePixel = 0; for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end

-- House palette: bright blue / white / lime / gold. No dark panels.
local PANEL      = Color3.fromRGB( 30, 120, 220)
local PANEL_DARK = Color3.fromRGB( 20,  60, 160)
local HEADER     = Color3.fromRGB( 15,  60, 140)
local CARD       = Color3.fromRGB( 20,  90, 200)
-- THE UNSELECTED TAB FILL -- the Pet Hub's exact value (PetFollow's syncNav paints 18,66,150), NOT this
-- panel's CARD blue. The two four-tab bars are meant to read as ONE bar that follows you between the two
-- panels, and they almost did: same geometry, same gold selected state, same strokes -- but unselected tabs
-- here sat on CARD (20,90,200) while the hub's sat on 18,66,150, so every hand-off visibly repainted the
-- three tabs you had NOT pressed. One constant, shared meaning; if the hub's bar is ever retuned, change
-- this to match it, not to match CARD.
local TAB_IDLE   = Color3.fromRGB( 18,  66, 150)
-- THE UNSELECTED TAB'S OUTLINE AND WORD. Both used to be pure white / gold at full strength, which made the
-- four tabs read as four equally-important buttons and left the selected one having to shout to be heard.
-- A soft blue edge and a near-white word are legible on the navy without competing: the SELECTED tab is the
-- only thing in the bar allowed to be a solid colour, which is what makes it obvious at a glance.
local TAB_EDGE   = Color3.fromRGB( 72, 126, 214)
local TAB_INK    = Color3.fromRGB(214, 230, 255)
local GOLD       = Color3.fromRGB(255, 220,   0)
local LIME       = Color3.fromRGB( 50, 220,  50)
local LIME_DARK  = Color3.fromRGB( 30, 130,  30)
local RED        = Color3.fromRGB(255,  60,  60)
local WHITE      = Color3.new(1, 1, 1)

local function playUIClick() if _G.playUIClick then pcall(_G.playUIClick) end end

-- ============================================================================================================
-- RARITY FLAIR -- what makes a rare pull actually LOOK rare
-- ============================================================================================================
-- Escalating, deliberately: Common and Uncommon get NOTHING. That's the whole point -- if every row shimmers,
-- none of them do. The plain majority is what makes a Rare border-pulse read as special and a Gold stop you.
--
--   Rare       edge pulse
--   Epic       + shimmer sweep
--   Legendary  + twinkling sparkles
--   Gold       + a breathing glow behind the card, faster/wider pulse
--
-- `lite` (the 56 reel cells) keeps only the cheap layers -- pulse + sweep. Sparkles and the glow image are
-- skipped there: at ~18 Rare+ cells flying past in 5 seconds nobody reads them, and they'd cost real frame time.
local FLAIR = {
	Common    = nil,
	Uncommon  = nil,
	Rare      = { pulse = 1.0 },
	Epic      = { pulse = 0.9, sweep = 2.6 },
	Legendary = { pulse = 0.8, sweep = 2.2, sparkles = 2 },
	-- `prize` is deliberately GOLD-ONLY. In CS:GO exactly one band -- the knife -- gets the special
	-- treatment, and that scarcity is the whole reason it reads as a prize. Give Legendary one too and
	-- neither means anything.
	Gold      = { pulse = 0.55, sweep = 1.6, sparkles = 3, glow = true, prize = true },
}

-- Looping tweens per frame, so a REUSED frame (the result card) can be reset between reveals instead of
-- stacking a second pulse on the same stroke. Weak keys: rows/cells that get destroyed drop out on their own.
local flairTweens = setmetatable({}, { __mode = "k" })

local function clearRarityFlair(frame)
	for _, t in ipairs(flairTweens[frame] or {}) do pcall(function() t:Cancel() end) end
	flairTweens[frame] = nil
	for _, d in ipairs(frame:GetChildren()) do
		if d.Name == "RarityShine" or d.Name == "RaritySparkle" or d.Name == "RarityGlow"
			or d.Name == "RarityPrize" then d:Destroy() end
	end
end

local function applyRarityFlair(frame, tier, lite)
	local f = FLAIR[tier]
	if not f then return end -- Common / Uncommon stay flat on purpose
	local col = PetSkins.tierColor(tier)
	local mine = {}; flairTweens[frame] = mine

	-- (1) EDGE PULSE -- breathe the existing rarity stroke instead of adding a second one, so the border
	-- thickens and brightens in place rather than doubling up.
	if f.pulse then
		local st = frame:FindFirstChildOfClass("UIStroke")
		if not st then st = Instance.new("UIStroke"); st.Color = col; st.Parent = frame end
		local base = st.Thickness
		st.Transparency = 0
		local t = TweenService:Create(st, TweenInfo.new(f.pulse, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = base + (tier == SkinCrates.GOLD_TIER and 2.5 or 1.5), Transparency = 0.25 })
		t:Play(); mine[#mine + 1] = t
	end

	-- (2) SHIMMER SWEEP -- a soft diagonal highlight crossing the card.
	--
	-- THE BAND ITSELF IS NO LONGER ROTATED, AND THAT IS THE WHOLE FIX. It used to be a Frame with
	-- Rotation = 14, and a ROTATED GuiObject IGNORES ClipsDescendants -- its own and every ancestor's. So
	-- this 1.8x-tall band spilled out of the reel cell, out of the reel window, out of the crate panel and
	-- swept across the entire screen during an opening, with a dozen Epic+ cells doing it at once. The
	-- clipping was set correctly the whole time; the rotation was quietly cancelling it.
	--
	-- The tilt now lives on the UIGradient instead. Gradient rotation is a paint-time property -- it tilts
	-- the highlight without rotating the frame, so clipping applies again. Same white, same 0.72
	-- transparency, same soft-edged band, same 0.85s Sine sweep and the same `f.sweep` gap between passes:
	-- the only thing that changed is that it can no longer leave the frame it belongs to.
	if f.sweep then
		frame.ClipsDescendants = true
		local shine = Instance.new("Frame")
		shine.Name = "RarityShine"; shine.BackgroundColor3 = Color3.new(1, 1, 1); shine.BackgroundTransparency = 0.72
		shine.BorderSizePixel = 0
		-- 0.22 wide, 1.8 tall starting at -0.4: the overhang top and bottom guarantees the band covers the
		-- full height at every point of its travel, and the frame's own clipping trims it to the card.
		shine.Size = UDim2.new(0.22, 0, 1.8, 0); shine.Position = UDim2.new(-0.35, 0, -0.4, 0)
		shine.ZIndex = (frame.ZIndex or 1) + 6; shine.Parent = frame
		local g = Instance.new("UIGradient", shine)
		g.Rotation = 14 -- the diagonal, moved off the Frame and onto the paint
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1),
		})
		task.spawn(function()
			while shine.Parent do
				shine.Position = UDim2.new(-0.35, 0, -0.4, 0)
				TweenService:Create(shine, TweenInfo.new(0.85, Enum.EasingStyle.Sine), { Position = UDim2.new(1.15, 0, -0.4, 0) }):Play()
				task.wait(f.sweep)
			end
		end)
	end

	if lite then return end -- reel cells stop here

	-- (2b) PRIZE ROSETTE -- the top tier gets a struck-medal badge on the item, the way CS:GO stars its
	-- Placed AFTER the `lite` gate on purpose. In the REEL a Gold item is masked -- the whole cell is
	-- one big rosette and nothing else (see buildCell) -- so a corner badge there would just be a
	-- rosette stamped on a rosette. This badge is for the places that DO show the item: the reveal
	-- card, the inventory rows and a completed collection.
	--
	-- Sits at (16, 3): clear of the inventory row's rarity stripe (x 6-14) and of the EQUIP button on the
	-- right, so it never lands on top of something clickable in any of the four places flair is applied.
	if f.prize then
		local medal = Instance.new("Frame")
		medal.Name = "RarityPrize"
		medal.Size = UDim2.fromOffset(24, 24)
		-- Centre-anchored so the breathing tween below grows it evenly in every direction; anchored at the
		-- corner it would swell down-and-right and drift off the item it is marking.
		medal.AnchorPoint = Vector2.new(0.5, 0.5)
		medal.Position = UDim2.new(0, 28, 0, 15)
		medal.BackgroundColor3 = col
		medal.ZIndex = (frame.ZIndex or 1) + 8 -- above the pet thumbnail (ZIndex +3) and the shimmer sweep
		medal.Parent = frame
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = medal -- a disc
		local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(92, 58, 8); rs.Thickness = 2; rs.Parent = medal
		-- struck-metal look: bright at the top, darker at the bottom
		local rg = Instance.new("UIGradient"); rg.Rotation = 90; rg.Parent = medal
		rg.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), col)
		local star = mkLabel(medal, {
			Text = "\xE2\x98\x85", Font = Enum.Font.FredokaOne, TextScaled = true,
			TextColor3 = Color3.fromRGB(92, 58, 8), Size = UDim2.new(1, -4, 1, -4),
			Position = UDim2.new(0, 2, 0, 2),
		})
		star.ZIndex = medal.ZIndex + 1
		-- A slow breath, not a spin. It has to catch the eye at reel speed without becoming a second moving
		-- thing competing with the reel itself.
		local pt = TweenService:Create(medal,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = UDim2.fromOffset(29, 29) })
		pt:Play(); mine[#mine + 1] = pt
	end

	-- (3) SPARKLES -- twinkle in place, no movement. Fixed spots so they read as part of the card.
	if f.sparkles then
		local spots = { {0.06, 0.22}, {0.94, 0.30}, {0.10, 0.78} }
		for i = 1, math.min(f.sparkles, #spots) do
			local tw = Instance.new("TextLabel")
			tw.Name = "RaritySparkle"; tw.BackgroundTransparency = 1; tw.Font = Enum.Font.GothamBold
			tw.Text = "\xE2\x9C\xA6"; tw.TextColor3 = col
			tw.TextSize = 10 + i * 3; tw.Size = UDim2.fromOffset(18, 18)
			tw.AnchorPoint = Vector2.new(0.5, 0.5); tw.Position = UDim2.fromScale(spots[i][1], spots[i][2])
			tw.ZIndex = (frame.ZIndex or 1) + 7; tw.Parent = frame
			local t = TweenService:Create(tw, TweenInfo.new(0.6 + i * 0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ TextTransparency = 0.85 })
			t:Play(); mine[#mine + 1] = t
		end
	end

	-- (4) GOLD GLOW -- a breathing halo BEHIND the card (ZIndex 0), so the top tier is visible from across the
	-- panel before you've read a single word.
	if f.glow then
		local glow = Instance.new("ImageLabel")
		glow.Name = "RarityGlow"; glow.BackgroundTransparency = 1
		glow.Image = "rbxassetid://1316045217"; glow.ImageColor3 = col; glow.ImageTransparency = 0.55
		glow.ScaleType = Enum.ScaleType.Slice; glow.SliceCenter = Rect.new(10, 10, 118, 118)
		glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 26, 1, 26); glow.ZIndex = 0; glow.Parent = frame
		local t = TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ ImageTransparency = 0.2, Size = UDim2.new(1, 40, 1, 40) })
		t:Play(); mine[#mine + 1] = t
	end
end

-- ===== MAIN-MENU MUTUAL EXCLUSIVITY (shared; reuse the game's if present) =====
if not _G.MainMenuManager then
	local mgr = { current = nil, hiders = {} }
	function mgr.register(name, hideFn) mgr.hiders[name] = hideFn end
	function mgr.setHud(visible)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("BottomStackGui")
		if g then g.Enabled = visible end
	end
	function mgr.notifyOpened(name)
		if mgr.current and mgr.current ~= name then local h = mgr.hiders[mgr.current]; if h then pcall(h) end end
		mgr.current = name; mgr.setHud(false)
	end
	function mgr.notifyClosed(name)
		if mgr.current == name then mgr.current = nil end
		if mgr.current == nil then mgr.setHud(true) end
	end
	function mgr.isOtherOpen(name) return mgr.current ~= nil and mgr.current ~= name end
	_G.MainMenuManager = mgr
end

-- ============================================================================================================
-- PET THUMBNAILS (static, CS:GO-style)
-- ============================================================================================================
-- A crate item is a PET plus a SKIN, so the picture has to be that pet wearing that skin -- a Honey Maple Fox
-- cell shows a Maple Fox painted Honey. A flat colour swatch could never do that.
--
-- STATIC on purpose. These sit still like a CS:GO case cell; there is no rotate loop, which also means no
-- per-frame cost for the ~56 cells a reel builds.
--
-- Two things keep this affordable:
--   * ONE base model is built per pet and cached, then CLONED per cell. Building is the expensive half.
--   * Builds are queued one-per-frame behind a paw placeholder, so a 56-cell reel never blocks a frame. The
--     reel spins for SPIN_TIME seconds, which is far longer than the queue needs to drain.
local previewBase = {}     -- [petId] = one unparented model, built once and cloned from
local previewQueue = {}
local previewWorking = false

-- The Trait Crate reel's stand-in: every cell shows the trait worn by this pet in the Classic skin, because
-- the real ride-along is rolled at open time. One species for every cell on purpose -- the MODEL reads as
-- "demo mannequin" and the TRAIT reads as the thing that changes cell to cell.
local TRAIT_DEMO_PET = "ButterDuck"

local function basePetModel(petId)
	local cached = previewBase[petId]
	if cached then return cached end
	-- PetFollow owns model construction (server union templates, with client fallbacks). Guarded because this
	-- script must still work if PetFollow failed to load -- the cells just keep their placeholder.
	if not _G.petBuildModel then return nil end
	local ok, built = pcall(_G.petBuildModel, petId)
	if not ok or typeof(built) ~= "Instance" or not built:IsA("Model") then return nil end
	built.Parent = nil
	previewBase[petId] = built
	return built
end

local function startPreviewWorker()
	if previewWorking then return end
	previewWorking = true
	task.spawn(function()
		while #previewQueue > 0 do
			local req = table.remove(previewQueue, 1)
			-- The cell may have been destroyed while queued (reel rebuilt, tab switched). Skip it.
			if req.vp and req.vp.Parent then
				local base = basePetModel(req.petId)
				if base then
					local ok, err = pcall(function()
						-- CLEAR EVERYTHING BUT THE CAMERA. A viewport populated twice keeps both models stacked at the
						-- origin and renders as one pet with two sets of eyes. Filtering on Model/BasePart was not enough:
						-- the pet template is built server-side, so its top-level shape is not this file's to assume -- a
						-- Folder or an Accessory wrapping the geometry would have slipped straight through.
						-- The placeholder goes too; req.ph is re-checked for a live Parent before it is touched below.
						for _, old in ipairs(req.vp:GetChildren()) do
							if not old:IsA("Camera") then old:Destroy() end
						end
						local clone = base:Clone()
						if _G.applyPetSkinPreview then
							_G.applyPetSkinPreview(clone, req.skin, req.trait, req.static)
						end
						clone.Parent = req.vp
						-- Fixed three-quarter view, framed from the model's own bounds so every pet fills the
						-- cell about equally regardless of how big it was built.
						local cf, size = clone:GetBoundingBox()
						local reach = math.max(size.X, size.Y, size.Z)
						local dist = reach * 1.85 + 1
						local centre = cf.Position
						req.cam.CFrame = CFrame.lookAt(
							centre + Vector3.new(dist * 0.60, dist * 0.40, dist * 0.72), centre)
						if req.ph then
							if req.ph.Parent then req.ph:Destroy() end -- already gone if the clear above took it
							req.ph = nil
						end
					end)
					if not ok then warn("[SkinCrate] thumbnail failed for " .. tostring(req.petId) .. ": " .. tostring(err)) end
				end
			end
			task.wait() -- one per frame: no single heavy synchronous burst
		end
		previewWorking = false
		if #previewQueue > 0 then startPreviewWorker() end -- close the enqueue-as-we-exit race
	end)
end

-- Returns the ViewportFrame immediately; the model lands a frame or two later.
-- `static` false gives the full look (particles, light, trait) -- used only for the one reveal card.
local function makePetPreview(parent, petId, skinId, traitId, size, pos, static)
	local vp = Instance.new("ViewportFrame")
	vp.Size = size; vp.Position = pos
	vp.BackgroundTransparency = 1
	-- Explicit ZIndex: the reel cell draws this OVER its skin-coloured backdrop. Same-ZIndex siblings fall
	-- back to creation order, which works but silently breaks the moment anyone reorders the cell build.
	vp.ZIndex = 3
	vp.Ambient = Color3.fromRGB(190, 190, 200)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.5)
	vp.Parent = parent
	-- ONE camera per viewport, created here and reused for its whole life -- the worker only ever writes
	-- its CFrame, never re-creates it. FindFirstChildOfClass first so a re-entrant build reuses the
	-- existing camera instead of leaving an orphan that CurrentCamera no longer points at.
	local cam = vp:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera")
		cam.FieldOfView = 50
		cam.Parent = vp
	end
	vp.CurrentCamera = cam
	local ph = mkLabel(vp, {
		Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = Color3.fromRGB(150, 180, 235), Size = UDim2.new(1, 0, 1, 0),
	})
	previewQueue[#previewQueue + 1] = {
		vp = vp, cam = cam, ph = ph, petId = petId, skin = skinId, trait = traitId,
		static = (static ~= false),
	}
	startPreviewWorker()
	return vp
end


-- ============================================================================================================
-- STATE (a local mirror of the server's push; never used to decide what the player owns)
-- ============================================================================================================
local state = { tokens = 0, skins = {}, equipped = {}, unlocked = {}, collection = {} }
local refreshTabs -- forward
-- FORWARD DECL. The tab-click handler (which hands PETS/TRADE/QUESTS back to the Pet Hub) has to close
-- this panel, but setOpen is defined ~1000 lines below with the rest of the open/close plumbing. Without
-- this line that handler compiles `setOpen` as a GLOBAL, finds nil at click time, and errors -- which is
-- exactly why those three tabs did nothing. Declared here, assigned there.
local setOpen -- forward

local function applyState(s)
	if type(s) ~= "table" then return end
	state.tokens   = tonumber(s.tokens) or 0
	state.skins    = s.skins    or {}
	state.equipped = s.equipped or {}
	state.unlocked = s.unlocked or {}
	state.collection = s.collection or {}
	-- The pet roster the post-open level picker draws, plus how many levels are waiting to be placed.
	-- pendingLevels of 0 is the normal resting state: it only goes above zero between opening a Pet Level
	-- Crate and choosing where those levels land.
	state.levelPets     = s.levelPets or {}
	state.pendingLevels = tonumber(s.pendingLevels) or 0
	-- Repaint the picker if the crate list has already built one. This is what makes the button follow a
	-- hatch, a trade, a pet maxing out, or the server refusing a stale target -- every one of those ends in a
	-- pushState, and every pushState lands here.
	if levelPickerRefresh then pcall(levelPickerRefresh) end
	-- Publish the balance so the Pet Hub header can show the same number this panel does. Pushed on the
	-- SERVER's state, not on a local guess, so the two headers cannot drift apart.
	_G.crateTokenBalance = state.tokens
	if _G.petHubTokensChanged then pcall(_G.petHubTokensChanged, state.tokens) end
	if refreshTabs then refreshTabs() end
end

-- ============================================================================================================
-- THE PANEL
-- ============================================================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "SkinCrateGui"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.DisplayOrder = 100 -- above the HUD, same as the Shop
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
-- KEEP CoreClient'S TEXT SWEEP OFF THIS PANEL.
-- applyScaling/repositionGUIs blanket-force TextScaled = true on every TextLabel/TextButton in every ScreenGui.
-- TextScaled IGNORES TextSize and inflates each label to fill its frame, so this panel's authored sizes (tab
-- labels, crate blurbs, odds lines) get overwritten -- the same "text goes huge and overlaps" bug the Pet Hub
-- hit. NoTextSweep is that sweep's documented opt-out and PetFollow already sets it on the Pet Hub (invGui).
--
-- IT WAS SET ON ONLY ONE OF THE TWO PANELS, which is why text looked different depending on the tab: PETS kept
-- its authored sizes, CRATES got swept. Worse, THIS panel calls _G.applyHudScaling() when it opens, so pressing
-- CRATES was itself the thing that triggered the sweep. Both panels opt out, or neither does.
gui:SetAttribute("NoTextSweep", true)
gui.Parent = PlayerGui

-- Full-screen catcher. Active=false so a click OUTSIDE falls through to the HUD menu buttons (click-to-switch).
-- It is NOT a close button: this menu closes on the X only -- a stray screen tap must never shut a panel.
mkFrame(gui, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Active = false })

local panel = mkFrame(gui, {
	Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, Active = true, ClipsDescendants = true,
})
local PANEL_RADIUS = 20   -- the panel's own rounding; the scrolling body matches it (see below)
mkCorner(panel, PANEL_RADIUS); mkStroke(panel, PANEL_DARK, 3)

-- ===== STARFIELD =====
-- Faint stars scattered across the panel's own fill, behind everything. The crate cards are dark and
-- self-contained, so the blue between them was a large flat empty area -- this gives it depth without
-- putting anything there you could mistake for content. Nothing is interactive and nothing moves.
--
-- THEY ARE BUILT FIRST, and that -- not a ZIndex -- is what puts them behind everything. Among siblings of
-- equal ZIndex Roblox draws in creation order, and the header, tab bar, body and banner are all created
-- after this block, so they all cover it. Using ZIndex 0 would express the same intent while relying on
-- below-default values behaving, which is a needless bet when the ordering is already free.
-- The body scroll is transparent, which is what lets the stars show through the gaps between cards -- the
-- only place they are actually visible.
--
-- SEEDED, not math.random: a fixed seed means every player sees the same sky and a reload cannot reshuffle
-- it into a clump. Two sizes and two shapes so it reads as scattered rather than as a dot grid.
do
	local rnd = Random.new(20260902)
	for k = 1, 22 do
		local big = (k % 5 == 0)
		local s = big and 11 or 6
		mkLabel(panel, {
			Text = big and "\xE2\x9C\xA6" or "\xE2\x80\xA2", Font = Enum.Font.FredokaOne,
			TextSize = s, TextScaled = true, TextColor3 = WHITE,
			TextTransparency = big and 0.86 or 0.92,
			Size = UDim2.fromOffset(s, s),
			-- FROM y=118, NOT 64. The tab bar is a TRANSPARENT frame spanning 66..104, so stars placed in that
			-- band showed through the gaps between the four tab pills as speckle under the row. The body
			-- starts at 120, so 118 is the first row of pixels where a star has an actual backdrop.
			Position = UDim2.new(0, rnd:NextInteger(14, 676), 0, rnd:NextInteger(118, 452)),
		}):SetAttribute("BTS_Skip", true)
	end
end

local header = mkFrame(panel, { Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = HEADER })
mkCorner(header, 20)

-- ===== PAW-PRINT WATERMARK =====
-- Four paws scattered across the header at 92% transparency and a few degrees of rotation each. It is
-- texture, not decoration: a flat navy bar 700px wide reads as a placeholder, and the paw is already this
-- feature's motif (the Pet Hut's sign, its mat and its wall plaques all carry one).
--
-- ZINDEX IS LOAD-BEARING. These are siblings of the title, the pill and the X inside `header`, and the
-- default ZIndexBehavior is Sibling -- so without an explicit order the paws would draw ON TOP of whatever
-- was built before them. They sit at 1 and every piece of real content below is raised to 3.
do
	for _, s in ipairs({ { 20, -6, 44, -18 }, { 196, 22, 34, 14 }, { 330, -10, 38, 8 }, { 470, 18, 30, -12 } }) do
		local w = mkLabel(header, {
			Text = "\xF0\x9F\x90\xBE", Font = Enum.Font.FredokaOne, TextSize = s[3], TextScaled = true,
			TextColor3 = WHITE, TextTransparency = 0.92, Rotation = s[4],
			Size = UDim2.new(0, s[3], 0, s[3]), Position = UDim2.new(0, s[1], 0, s[2]), ZIndex = 1,
		})
		-- The legibility sweep would repaint a 92%-transparent watermark as readable text.
		w:SetAttribute("BTS_Skip", true)
	end
end

-- WHITE, not gold. The title is the loudest thing on the panel and gold-on-navy was competing with the
-- token pill (also gold) two inches to its right; white with the black outline it already had is both
-- stronger and leaves gold to mean "tickets" everywhere on this screen.
local titleLbl = mkLabel(header, {
	Text = "\xF0\x9F\x8E\x81 PET SKIN CRATES", Font = Enum.Font.FredokaOne, TextSize = 26, TextScaled = true,
	TextColor3 = WHITE, Size = UDim2.new(0, 330, 0, 34), Position = UDim2.new(0, 14, 0, 6),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
})
mkStroke(titleLbl, Color3.new(0, 0, 0), 2)
mkLabel(header, {
	-- A BULLET, not a plus. "Skin + a Trait" reads as arithmetic -- as though the two combine into one
	-- thing -- and they do not: they are two independent rolls that are then scored together, which is
	-- exactly what the rest of the sentence says.
	Text = "Every pull is a Skin \xE2\x80\xA2 a Trait. Together they set the pet's Tier.",
	Font = Enum.Font.Gotham, TextSize = 13,
	TextScaled = true, TextColor3 = Color3.fromRGB(215, 228, 255), Size = UDim2.new(0, 330, 0, 15),
	Position = UDim2.new(0, 14, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
})

-- ===== TOKEN BALANCE PILL =====
-- The ticket icon is RED and the number is dark brown, as two labels rather than one string. One label
-- cannot do it: a TextLabel has a single TextColor3, so "icon + number" in one string forces the icon to
-- take the number's colour. Red is the ticket's own colour everywhere else on this panel (the tile on every
-- pack row, the pair on the footer banner), and it is what makes the pill scan as tickets rather than coins.
local tokenPill = mkFrame(header, {
	Size = UDim2.new(0, 158, 0, 34), Position = UDim2.new(1, -212, 0, 13), BackgroundColor3 = GOLD, ZIndex = 3,
})
mkCorner(tokenPill, 17); mkStroke(tokenPill, Color3.fromRGB(180, 122, 20), 2)
mkLabel(tokenPill, {
	Text = CrateTokens.ICON, Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
	TextColor3 = RED, Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 8, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5), ZIndex = 4,
}):SetAttribute("BTS_Skip", true)
local tokenLbl = mkLabel(tokenPill, {
	Text = "0", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true,
	TextColor3 = Color3.fromRGB(92, 58, 8), Size = UDim2.new(1, -46, 1, -6), Position = UDim2.new(0, 38, 0, 3),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
})
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 20; c.Parent = tokenLbl end

-- ===== THE X, AND WHY IT IS A CHILD LABEL IN A DIFFERENT FONT =====
-- The button rendered EMPTY. Two things were wrong and both had to be fixed:
--
--   1. FredokaOne does not carry U+2715 (the ✕ this was switched to). A display font's glyph coverage is
--      basically Latin, digits and common punctuation -- ask it for a dingbat and you get nothing at all,
--      which is exactly what a blank red square is. GothamBold carries it. (The original "X" was an ASCII
--      capital letter, which is why the old button was never blank.)
--   2. Even with a glyph, a UIStroke on a FILLED text object outlines the object's BORDER, not its letters,
--      so the dark edge that keeps the mark readable on red can only come from a transparent label on top.
--      That is the same rule the tab bar, the buy buttons and the bottom nav all follow in this file.
local closeBtn = mkButton(header, {
	Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -48, 0, 10), BackgroundColor3 = RED,
	Text = "", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = WHITE, ZIndex = 3,
})
mkCorner(closeBtn, 12); mkStroke(closeBtn, Color3.fromRGB(150, 40, 32), 2)
do
	local x = mkLabel(closeBtn, {
		Text = "\xE2\x9C\x95", Font = Enum.Font.GothamBold, TextSize = 20, TextScaled = true,
		TextColor3 = WHITE, Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
	})
	mkStroke(x, Color3.fromRGB(70, 12, 8), 2)
	local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = x
	closeBtn:SetAttribute("BTS_Skip", true); x:SetAttribute("BTS_Skip", true)
end

-- NO BACK BUTTON. THE TAB BAR IS THE WAY BACK.
--
-- There used to be one here, shown only when this panel was opened from the Pet Hub. That made it a second
-- door to a place the first door already goes: the PETS tab at the top of this panel closes this and reopens
-- the hub, and it does that on EVERY page -- whereas BACK appeared on some openings and not others. Two
-- controls for one destination, one of which comes and goes, is harder to learn than one that is always
-- there, and it was crowding the header beside the token chip and the X.

-- ===== TABS =====
-- Five tabs across a 680px bar. Widths are authored (not scale-based) because the bar sits inside the panel's
-- fixed 700px layout, and 8px of padding between five buttons leaves exactly 129 each: 5*129 + 4*8 = 677.
-- THE SAME FIVE PAGES THE PET HUB SHOWS, in the same order and the same geometry. Two of them (CRATES,
-- TOKENS) are built here; the other three live in the Pet Hub and this bar hands off to it. Matching the
-- bar pixel-for-pixel is the whole point -- tabbing between the panels should feel like one interface
-- changing pages, not two menus swapping places.
--
-- INVENTORY / TRADE UP / COLLECTION are no longer top-level tabs. They are sub-pages now, reached from the
-- page they belong to (View Collection on a crate, Trade Up from the crate list, skins from a pet), which
-- is what gives each top-level page one job instead of five competing ones.
-- ===== TWO TABS, NOT FIVE =====
-- This bar used to mirror the Pet Hub's five pages (PETS/CRATES/TOKENS/TRADE/QUESTS) and hand
-- three of them off to the hub, so the two panels read as one interface. That was reversed on
-- purpose: five tabs of which several have their OWN sub-page rows underneath read as
-- overwhelming, and pressing Pets vs Crates from the menu landed players in "the same GUI,
-- different tab", which felt broken. Crates is its own menu again -- it hosts exactly the two
-- pages it owns, and the Pet Hub keeps its three. The `hub` field / TAB_TO_HUB machinery below
-- still works if a cross-tab is ever wanted back: add the entry, done.
-- ===== ONE HUB, FOUR PAGES =====
-- Pets and crates are ONE interface again, entered through the PETS rail button: this bar mirrors the
-- Pet Hub's bar exactly (same four tabs, same geometry) and the two panels hand off to each other, so
-- tabbing feels like one menu changing pages. The de-overwhelm vs the old five-tab bar is TOKENS: it is
-- no longer a top-level destination -- it is a page INSIDE Crates (the GET TOKENS button and the token
-- chip lead there), because it is a shop for the crates page, not a collection of its own.
local TABS = {
	{ id = "pets",   label = "\xF0\x9F\x90\xBE PETS",   hub = "pets"   },
	{ id = "crates", label = "\xF0\x9F\x93\xA6 CRATES" },
	{ id = "trade",  label = "\xF0\x9F\x94\x84 TRADE",  hub = "trade"  },
	{ id = "quests", label = "\xF0\x9F\x93\x9C QUESTS", hub = "quests" },
}
-- id -> the Pet Hub page to jump to, for the tabs this panel does not host
local TAB_TO_HUB = {}
for _, t in ipairs(TABS) do if t.hub then TAB_TO_HUB[t.id] = t.hub end end
-- Fill the same 677px the five 129px tabs used to occupy: n tabs + 8px gaps between them.
local TAB_W = math.floor((677 - 8 * (#TABS - 1)) / #TABS)
local activeTab = "crates"
local tabBar = mkFrame(panel, { Size = UDim2.new(1, -20, 0, 38), Position = UDim2.new(0, 10, 0, 66), BackgroundTransparency = 1 })
do
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, 8); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = tabBar
end
local tabButtons = {}
for i, t in ipairs(TABS) do
	local b = mkButton(tabBar, {
		Size = UDim2.new(0, TAB_W, 1, 0), LayoutOrder = i, BackgroundColor3 = TAB_IDLE, Text = "",
		Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = TAB_INK,
	})
	mkCorner(b, 12); mkStroke(b, TAB_EDGE, 1.5)
	-- THE WORD IS A CHILD LABEL, NOT THE BUTTON'S OWN TEXT -- identical to the Pet Hub's copy of this bar.
	-- A UIStroke on a FILLED text object outlines the object's BORDER, not its glyphs, so the stroke these
	-- tabs already had was the white/gold edge round the tab and the word itself could not be outlined from
	-- the same instance. A transparent label on top has no border to draw, so its stroke lands on the
	-- letters. GOLD, not WHITE: pure white on the blue card was the brightest thing on the panel and pulled
	-- the eye off the content -- this is the same tone as the 'PET SKIN CRATES' title.
	local lbl = Instance.new("TextLabel"); lbl.Name = "Label"
	lbl.Size = UDim2.new(1, -8, 1, -6); lbl.Position = UDim2.new(0, 4, 0, 3)
	lbl.BackgroundTransparency = 1; lbl.Text = t.label
	lbl.Font = Enum.Font.FredokaOne; lbl.TextSize = 15; lbl.TextScaled = true
	lbl.TextColor3 = TAB_INK; lbl.ZIndex = b.ZIndex + 1; lbl.Parent = b
	mkStroke(lbl, Color3.new(0, 0, 0), 2)
	lbl:SetAttribute("BTS_Skip", true)
	do local lc = Instance.new("UITextSizeConstraint"); lc.MaxTextSize = 15; lc.Parent = lbl end
	-- HANDS OFF -- SAME REASON AS THE PET HUB'S COPY OF THIS BAR (PetFollow's HubNav).
	-- The refresh below paints selected as dark-on-gold with a 2.5px gold-brown outline and unselected as
	-- gold-on-blue with a 1.5px white one: the colour IS which tab you're on. ButtonTextStyle's legibility
	-- sweep repaints every button cream with a 2px dark stroke and darkens the fill from whichever state it
	-- first saw, which erases that distinction.
	--
	-- THIS BAR AND THE PET HUB'S ARE TWO SEPARATE BUILDS OF THE SAME FOUR TABS, in two different scripts, and
	-- pressing PETS/CRATES swaps which panel you are looking at. Protecting only one of them is what made the
	-- tabs appear to change font and outline as you clicked between them -- so both carry the flag or neither.
	b:SetAttribute("BTS_Skip", true)
	-- CoreClient force-sets TextScaled on every label in PlayerGui, so a plain TextSize won't hold -- the
	-- ceiling has to come from a constraint or "COLLECTION" would scale up and crowd its neighbours.
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = b end
	tabButtons[t.id] = b
end

-- one scrolling body shared by the tabs; each tab rebuilds its contents into it
local BODY_PAD, BODY_BAR = 10, 6
-- What a full-width card actually gets, spelled out rather than rediscovered per card:
--   panel 700  -  body inset 2*10  -  BODY_PAD 10  -  (BODY_PAD 10 + BODY_BAR 6)  =  654
local CARD_W = 700 - 20 - BODY_PAD - (BODY_PAD + BODY_BAR)
local body = Instance.new("ScrollingFrame")
-- ===== WHERE THE BODY STARTS AND STOPS =====
-- BOTTOM: the bottom navigation is 56 tall and sits 10 off the panel's bottom edge, so the body stops 66
-- short of it plus a 10px gap. Shortening the body is what keeps the bar OUT of the scroll -- park it
-- inside and it scrolls away with the crates.
--
-- TOP: y=120, not 110. The tab bar runs 66..104, so the body used to begin 6px under it -- close enough
-- that the first card read as welded to the tabs, and the moment you scrolled, a card passing the top
-- boundary got sliced flat right beneath them with nothing between the two. 120 puts a clear 16px lane
-- there. The height compensates by the same 10 (1,-196 from 1,-186) so the BOTTOM edge does not move and
-- the gap above the bottom nav is unchanged.
-- -204, not -196: the bottom bar grew from a bare 56px button row to a 64px GET TICKETS banner (see below),
-- and the body has to give back the 8 or the banner's top edge eats the last card's rounded lip.
body.Position = UDim2.new(0, 10, 0, 120); body.Size = UDim2.new(1, -20, 1, -204)
body.BackgroundTransparency = 1; body.BorderSizePixel = 0
-- A THIN, LIGHT BAR. It was gold, which put a bright saturated stripe down the right edge of every page --
-- the same gold the token pill, the value stars and the GET TICKETS banner use, so it read as one more thing
-- demanding attention rather than as a scroll position. Pale blue at 6px states where you are and nothing else.
body.ScrollBarThickness = BODY_BAR; body.ScrollBarImageColor3 = Color3.fromRGB(150, 190, 245)
body.CanvasSize = UDim2.new(0, 0, 0, 0); body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.ScrollingDirection = Enum.ScrollingDirection.Y
-- ===== A ROUNDED CLIP REGION, MATCHING THE PANEL =====
-- A ScrollingFrame clips its canvas by definition, and by default that clip is a hard rectangle -- so the
-- corners of the list were square inside a panel whose own corners are round, and a card reaching the top
-- was cut with a straight edge across its full width. ClipsDescendants + UICorner makes the mask itself
-- rounded, so the list ends in the same curve the panel does.
--
-- BE HONEST ABOUT WHAT THIS DOES AND DOES NOT FIX: it rounds the boundary, it does not soften it. A card
-- scrolling PAST the top edge is still cut where it crosses -- that is what a scroll region is. What the
-- rounding and the padding below fix is the resting state, which is where the flat edge was actually
-- being seen.
body.ClipsDescendants = true
mkCorner(body, PANEL_RADIUS)
body.Parent = panel
do
	local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Vertical
	ll.Padding = UDim.new(0, 14); ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center; ll.Parent = body
	-- THE SCROLLBAR WAS BEING DRAWN OVER THE CARDS. Roblox paints a ScrollingFrame's bar INSIDE the frame's
	-- own rect, so a card sized to the full width runs underneath it -- which is why the right-hand column of
	-- every crate card (the token cost and the OPEN / NEED TOKENS button) looked clipped.
	--
	-- BODY_PAD is the inset on both sides, BODY_BAR is the bar's width reserved on the right, and every card
	-- below is scale-sized to what is left, so nothing has to guess at a magic negative offset again.
	local pd = Instance.new("UIPadding")
	-- PaddingTop was simply absent, which is why the first card sat flush against the very top of the
	-- scroll: its rounded top corners landed exactly on the clip boundary and got shaved off, and the card
	-- read as cut straight across. 8px is enough for the corner radius and the stroke to sit inside the
	-- mask instead of on it.
	pd.PaddingTop = UDim.new(0, 8)
	pd.PaddingBottom = UDim.new(0, 10)
	pd.PaddingLeft = UDim.new(0, BODY_PAD)
	pd.PaddingRight = UDim.new(0, BODY_PAD + BODY_BAR)
	pd.Parent = body
end

-- ============================================================================================================
-- PERMANENT BOTTOM NAVIGATION
-- ============================================================================================================
-- ONE BUTTON. This bar carried MY SKINS, COLLECTION and TOKENS; the first two are gone.
--
-- MY SKINS was a flat list of every skin you own -- but a skin is already shown on the pet it belongs to,
-- reached by tapping that pet in the hub. Two places to look for the same thing is worse than one, and the
-- pet is the one a player actually thinks in terms of. The COLLECTION BOOK was a third view of the same
-- data, sorted a third way.
--
-- TOKENS stays because it is not a view of anything -- it is where you get more, and it has to be reachable
-- from every page of this panel rather than only from the crate you happened to be looking at.
--
-- Same design system as the tab bar above it: TAB_IDLE fill (the shared unselected-tab blue -- the top bar
-- and this one sitting two different blues apart read as a mistake, not a hierarchy), 1.5px white edge,
-- FredokaOne, and the same lit-gold selected state -- so the top bar says which hub page you are on and
-- this one says which part of Crates.
-- ===== IT IS A BANNER NOW, NOT A BUTTON ROW =====
-- This was one 220px pill floating in a transparent strip, which read as an afterthought parked at the
-- bottom of the panel -- and it is the only route to the thing that funds every crate on the shelf. As a
-- filled banner it becomes the panel's foot: a darker navy plinth the body sits on, with the offer stated in
-- words (a headline and a reason) and the button as its call to action rather than as the whole feature.
--
-- ONE BUTTON STILL, and the same click it always had. `bottomNavButtons` keeps its shape so refreshTabs'
-- lit-state loop below needs no change.
local bottomNav = mkFrame(panel, {
	Size = UDim2.new(1, -20, 0, 64), Position = UDim2.new(0, 10, 1, -74),
	BackgroundColor3 = Color3.fromRGB(11, 42, 104), ClipsDescendants = true,
})
mkCorner(bottomNav, 16); mkStroke(bottomNav, Color3.fromRGB(58, 108, 190), 1.5)
local bottomNavButtons = {}
do
	-- RADIAL GLOW, built from three concentric discs rather than an image. UIGradient is linear-only and
	-- there is no radial one, so the alternative would be shipping a texture asset -- three rounded frames at
	-- 0.88 / 0.93 / 0.97 transparency give the same warm falloff behind the tickets for nothing, and cannot
	-- break if an asset id is ever mis-typed or moderated.
	-- Centred on x=48, the single ticket's centre -- it was 62, which was the midpoint of the old overlapping
	-- pair and left the glow sitting off to the ticket's right once that became one icon.
	for _, r in ipairs({ { 132, 0.88 }, { 96, 0.93 }, { 60, 0.97 } }) do
		local d = mkFrame(bottomNav, {
			Size = UDim2.new(0, r[1], 0, r[1]), Position = UDim2.new(0, 48, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = GOLD, BackgroundTransparency = r[2],
			ZIndex = 1,
		})
		mkCorner(d, math.floor(r[1] / 2))
	end

	-- ===== ONE BIG TICKET, NOT TWO =====
	-- The pair was two rotated 30/34px glyphs overlapping at x=26 and x=52. Rotation grows an object's
	-- bounding box, the banner clips its descendants, and the left one sat 11px from the edge -- so its
	-- corner was shaved off and the pair read as broken rather than as a handful. One larger upright ticket
	-- has nothing to clip and is a stronger mark at this size anyway.
	--
	-- IT IS A TEXT GLYPH, NOT AN ImageLabel. CrateTokens.ICON is the 🎟 emoji -- this project has no ticket
	-- IMAGE asset anywhere, and an ImageLabel needs a real rbxassetid. Inventing one renders an empty box.
	-- Swap this for an ImageLabel the moment there is an uploaded ticket asset to point at.
	mkLabel(bottomNav, {
		Text = CrateTokens.ICON, Font = Enum.Font.FredokaOne, TextSize = 46, TextScaled = true,
		TextColor3 = RED, Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 48, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3,
	}):SetAttribute("BTS_Skip", true)
	for _, sp in ipairs({ { 14, 10, 12, 0.3 }, { 72, 38, 10, 0.45 }, { 62, 6, 9, 0.5 } }) do
		mkLabel(bottomNav, {
			Text = "\xE2\x9C\xA6", Font = Enum.Font.FredokaOne, TextSize = sp[3], TextScaled = true,
			TextColor3 = GOLD, TextTransparency = sp[4],
			Size = UDim2.new(0, sp[3], 0, sp[3]), Position = UDim2.new(0, sp[1], 0, sp[2]), ZIndex = 4,
		}):SetAttribute("BTS_Skip", true)
	end

	-- ----- the words -----
	local hl = mkLabel(bottomNav, {
		Text = "GET TICKETS!", Font = Enum.Font.FredokaOne, TextSize = 26, TextScaled = true,
		TextColor3 = GOLD, Size = UDim2.new(0, 250, 0, 30), Position = UDim2.new(0, 100, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	})
	mkStroke(hl, Color3.new(0, 0, 0), 2)
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 26; c.Parent = hl end
	hl:SetAttribute("BTS_Skip", true)
	-- WHITE, not the muted blue it started as: under a gold headline on a dark plinth this is the line that
	-- has to carry, and pale blue on navy was the weakest text on the panel.
	local sub = mkLabel(bottomNav, {
		Text = "More tickets. More pulls. More pets!", Font = Enum.Font.GothamBold, TextSize = 13,
		TextScaled = true, TextColor3 = WHITE,
		Size = UDim2.new(0, 250, 0, 18), Position = UDim2.new(0, 100, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	})
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 13; c.Parent = sub end

	-- ----- the call to action -----
	-- YELLOW, not the tab bar's blue: on this plinth it is the only thing the player is being asked to press,
	-- and gold is already what "tickets" means everywhere on this panel.
	-- The bottom shadow is a darker slab sitting 4px lower, drawn BEFORE the button so the button covers all
	-- but its bottom lip -- the same physical-key treatment the crate OPEN buttons and the Pet Hut's primary
	-- buttons use, so every button in the feature presses the same way.
	do
		local sh = mkFrame(bottomNav, {
			Size = UDim2.new(0, 208, 0, 44), Position = UDim2.new(1, -12, 0.5, 4),
			AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.fromRGB(150, 100, 14), ZIndex = 3,
		})
		mkCorner(sh, 16)
	end
	local b = mkButton(bottomNav, {
		Size = UDim2.new(0, 208, 0, 44), Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = GOLD, Text = "",
		Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = Color3.fromRGB(92, 58, 8), ZIndex = 4,
	})
	mkCorner(b, 16); mkStroke(b, Color3.fromRGB(180, 122, 20), 2.5)
	b.ClipsDescendants = true
	-- SPEED LINES. Three tapering bars raked across the button's left edge, in the darker gold of its own
	-- outline at low opacity. They imply the button is moving toward you rather than sitting still, which is
	-- the whole difference between a call to action and a label -- and being clipped by the button means they
	-- run off its edge instead of stopping in mid-air.
	for _, ln in ipairs({ { 6, 10, 34 }, { 2, 22, 46 }, { 8, 34, 28 } }) do
		local sl = mkFrame(b, {
			Size = UDim2.fromOffset(ln[3], 4), Position = UDim2.new(0, ln[1], 0, ln[2]),
			BackgroundColor3 = Color3.fromRGB(180, 122, 20), BackgroundTransparency = 0.6,
			Rotation = -12, ZIndex = 4,
		})
		mkCorner(sl, 2)
	end
	local lbl = mkLabel(b, {
		Name = "Label", Size = UDim2.new(1, -12, 1, -10), Position = UDim2.new(0, 6, 0, 5),
		Text = "\xF0\x9F\x8E\x9F\xEF\xB8\x8F GET TICKETS!", Font = Enum.Font.FredokaOne, TextSize = 16,
		TextScaled = true, TextColor3 = Color3.fromRGB(92, 58, 8), ZIndex = 5,
	})
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 18; c.Parent = lbl end
	b:SetAttribute("BTS_Skip", true); lbl:SetAttribute("BTS_Skip", true)
	bottomNavButtons.tokens = b

	b.MouseButton1Click:Connect(function()
		playUIClick()
		-- ALREADY ON THE PACKS? Then switching page would do nothing visible and the button would feel dead.
		-- Scroll the shelf back to the top and pulse every row's edge instead, so the press always answers.
		if activeTab == "tokens" then
			body.CanvasPosition = Vector2.new(0, 0)
			for _, ch in ipairs(body:GetChildren()) do
				local st = ch:IsA("GuiObject") and ch:FindFirstChildOfClass("UIStroke")
				if st then
					local was, wasT = st.Color, st.Thickness
					st.Color, st.Thickness = GOLD, 3
					TweenService:Create(st, TweenInfo.new(0.55, Enum.EasingStyle.Quad),
						{ Color = was, Thickness = wasT }):Play()
				end
			end
			return
		end
		activeTab = "tokens"; refreshTabs()
	end)
end

local function clearBody()
	for _, ch in ipairs(body:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end

	-- ===== THE TAIL SPACER, AND WHY PaddingBottom IS NOT ENOUGH =====
	-- body already sets PaddingBottom = 10, and that is genuinely not what reserves the room:
	-- AutomaticCanvasSize measures the ScrollingFrame's CHILDREN, and a UIPadding is not a child. So the
	-- canvas ends flush with the bottom of the last card and the scroll simply cannot travel any further --
	-- the card's 2.5px stroke and its bottom rounded lip are the part that falls outside, which reads as
	-- "the last row has square corners" even though its UICorner is right there in the code.
	--
	-- A spacer IS a child, so it is measured, and the canvas grows by exactly its height. Built here rather
	-- than at the end of each build function so it cannot be forgotten: clearBody runs before every tab, so
	-- every page gets it, including any page added later.
	-- 76 = the GET TICKETS banner's 64 + 12 of breathing room.
	--
	-- WHY THE SPACER AND NOT UIPadding.PaddingBottom: the note above is the whole reason -- AutomaticCanvasSize
	-- measures CHILDREN, and a UIPadding is not one, so PaddingBottom does not extend the scrollable range by
	-- a single pixel. It was 16, which cleared the last card's stroke and its rounded lip but left the card
	-- bottom sitting right on the clip boundary with the banner immediately beneath it -- so the last crate
	-- read as sliced flat and tucked under the footer even though the two never actually overlap (the body
	-- ends at y=436 and the banner starts at 446). At 76 the last card can travel clear of the edge and the
	-- gap between it and the banner is visible, which is what makes it read as "below" rather than "under".
	local tail = Instance.new("Frame")
	tail.Name = "TailSpacer"
	tail.Size = UDim2.new(1, 0, 0, 76)
	tail.BackgroundTransparency = 1
	tail.BorderSizePixel = 0
	-- Far above any real row's order (the crates tab's footer note uses 999) so nothing can sort past it.
	tail.LayoutOrder = 100000
	tail.Parent = body
end

-- ============================================================================================================
-- TAB: CRATES
-- ============================================================================================================
local openRequestInFlight = false
local doOpenCrate -- forward (defined with the reveal, below)

-- ===== PER-CRATE CARD THEME =====
-- Each crate gets its own colour story rather than all seven sharing one blue card: the Pet Level Crate is
-- cool and electric, the Pet Crate is warm and gold. That is the difference between a list of rows and a
-- shelf of products, and it is the fastest way to tell two crates apart before reading either name.
--
-- ONLY THE TWO HEADLINE CRATES ARE AUTHORED. Everything else falls back to a navy card tinted with its own
-- `crate.color` (SkinCrates already gives every crate one), so the five other crates keep working and a
-- crate added later styles itself. This table is decoration only -- no price, no odds, nothing the server
-- reads -- so it can never disagree with the crate config.
--   fill/edge  : the card and its outline        glow/disc : the lit disc behind the icon
--   descA/descB: first sentence / the rest       muted     : the NEED TICKETS button
--   pedestal   : draw a plinth under the icon instead of leaving it floating on the disc
local CRATE_SKIN = {
	PetLevels = {
		fill = Color3.fromRGB( 16,  46, 104), edge = Color3.fromRGB( 64, 150, 255),
		glow = Color3.fromRGB( 70, 190, 255), disc = Color3.fromRGB( 26,  84, 176),
		descA = Color3.fromRGB(168, 212, 255), descB = Color3.fromRGB(168, 212, 255),
		muted = Color3.fromRGB( 40,  78, 142), mutedEdge = Color3.fromRGB( 74, 124, 196),
	},
	Pets = {
		fill = Color3.fromRGB( 72,  44,  20), edge = Color3.fromRGB(255, 176,  64),
		glow = Color3.fromRGB(255, 194,  96), disc = Color3.fromRGB(190, 134,  40),
		descA = Color3.fromRGB(255, 176,  64), descB = Color3.new(1, 1, 1),
		muted = Color3.fromRGB( 88,  58,  30), mutedEdge = Color3.fromRGB(154, 110,  56),
		pedestal = true,
	},
}

local function buildCratesTab()
	-- NO SUB-PAGE ROW. This page is the crates and nothing else.
	--
	-- TRADE UP used to sit here as a button above the crate cards, which put it on the one page it has least
	-- to do with: trading up burns DUPLICATE SKINS YOU ALREADY OWN and hands back a better one. It never
	-- opens a crate and it never costs a token. Its entry point is the Pet Hub's PETS page now, next to the
	-- pets whose duplicates it consumes -- the page moved, the page itself did not change (see
	-- _G.openSkinTradeUp at the bottom of this file).
	for i, crate in ipairs(SkinCrates.CRATES) do
		-- The Pet Level Crate card is now the same height as every other crate card. It used to be 44px
		-- taller to carry a "LEVELS GO TO:" picker, which asked you to choose a pet BEFORE opening -- i.e.
		-- before you knew whether you had won +1 or +7, which is the fact that decides which pet you want to
		-- feed. That picker is gone; you choose after the reveal instead. See levelPickerRefresh below.
		-- 152, not 132. Removing the TRADE UP sub-row above gave this page 44px back, and the card was the
		-- thing that needed it: name, blurb, six odds pills, a price and a 44px button inside 132px left the
		-- pills sitting 16px off the bottom edge and the whole card reading as full to bursting.
		-- ===== THE CARD'S INTERNAL GRID =====
		-- Everything on this card was positioned with its own hand-picked negative offset (-260, -244, -266,
		-- -162), so no two columns agreed where the right-hand edge was: the odds chips ran past it, the blurb
		-- ran into the token cost, and the cost and button sat flush on the border with the scrollbar over
		-- them. Four numbers now define the whole card and every element is derived from one of them.
		-- ===== THE CARD'S INTERNAL GRID, REVISED =====
		-- The odds row runs the FULL WIDTH of the card now instead of living inside the text column. Six chips
		-- crammed into a 332px column are 54px each, which is where "Legendary 0.9%" turns into an unreadable
		-- smear; across the whole 622px they get 98px each and can carry the band name and the number at a
		-- size worth reading. It also gives the row an identity -- it is the odds, stated once, along the
		-- bottom -- rather than being a fourth thing competing inside the text column.
		local CARD_INSET = 16
		local ICON_BOX   = 92                              -- the lit disc + glyph
		local RIGHT_COL  = 168                             -- the ticket cost + OPEN button column
		local TEXT_X     = CARD_INSET + ICON_BOX + 14      -- 122
		local TEXT_W     = CARD_W - TEXT_X - RIGHT_COL - CARD_INSET * 2   -- 332
		local sk = CRATE_SKIN[crate.id] or {
			-- The generic fallback: this panel's usual card blue, outlined and lit in the crate's own colour.
			fill = CARD, edge = crate.color or WHITE, glow = crate.color or WHITE,
			disc = Color3.fromRGB(20, 70, 158),
			descA = Color3.fromRGB(205, 224, 255), descB = Color3.fromRGB(205, 224, 255),
			muted = Color3.fromRGB(58, 74, 104), mutedEdge = Color3.fromRGB(96, 116, 152),
		}

		-- Full width: the body reserves the scrollbar's lane, so the card no longer has to dodge it.
		local card = mkFrame(body, { Size = UDim2.new(1, 0, 0, 168), BackgroundColor3 = sk.fill, LayoutOrder = i })
		mkCorner(card, 16); mkStroke(card, sk.edge, 2.5)
		do
			-- Depth down the card. UIGradient MULTIPLIES the fill, so white at the top leaves the authored
			-- colour untouched and the grey at the bottom darkens it -- there is no multiplier above 1, and a
			-- gradient can only ever take light away. On the Pet Crate's brown this is the "warm gradient";
			-- on the others it is a shadow that stops the card reading as a flat rectangle.
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(176, 176, 176))
			g.Rotation = 90; g.Parent = card
		end

		-- ---- the lit icon ------------------------------------------------------------------
		-- Three concentric discs for the glow (UIGradient is linear-only, so a real radial would mean shipping
		-- a texture), the crate's own glyph on top, and three sparkles scattered around it.
		do
			local cx, cy = CARD_INSET + ICON_BOX / 2, 14 + ICON_BOX / 2
			-- FIVE RINGS, NOT THREE, and they now run PAST the icon box (up to +16) rather than stopping at
			-- its edge. Three hard steps read as three concentric plates; five with a gentle transparency
			-- ramp that fades out beyond the disc is what actually reads as a glow, and spilling over the box
			-- edge is what stops it looking like a rounded square with a light in it.
			for _, d in ipairs({
				{ ICON_BOX + 16, 0.93 }, { ICON_BOX + 2, 0.86 }, { ICON_BOX - 14, 0.74 },
				{ ICON_BOX - 30, 0.56 }, { ICON_BOX - 46, 0.34 },
			}) do
				local disc = mkFrame(card, {
					Size = UDim2.fromOffset(d[1], d[1]), Position = UDim2.new(0, cx, 0, cy),
					AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = sk.glow,
					BackgroundTransparency = d[2], ZIndex = 2,
				})
				mkCorner(disc, math.floor(d[1] / 2))
			end
			-- The lit disc the glyph stands on. 66 of the 92 box, and a true circle -- half the side length as
			-- the corner radius is what makes UICorner produce a circle rather than a rounded square.
			local CORE = 66
			local core = mkFrame(card, {
				Size = UDim2.fromOffset(CORE, CORE), Position = UDim2.new(0, cx, 0, cy),
				AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = sk.disc, ZIndex = 3,
			})
			mkCorner(core, CORE // 2); mkStroke(core, sk.glow, 2)
			-- A PLINTH, for a crate whose icon is an object that should be standing on something (the egg).
			-- Drawn before the glyph so the glyph sits on it.
			if sk.pedestal then
				local ped = mkFrame(card, {
					Size = UDim2.fromOffset(ICON_BOX - 26, 12), Position = UDim2.new(0, cx, 0, cy + 28),
					AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = GOLD, ZIndex = 4,
				})
				mkCorner(ped, 6); mkStroke(ped, Color3.fromRGB(180, 122, 20), 1.5)
			end
			-- ~75% OF THE BOX (69 of 92), up from 50. It was a 50px frame holding a TextScaled glyph, and an
			-- emoji does not fill its own line box -- so the drawn star was nearer 34px inside a 92px disc and
			-- read as a small mark floating in a large empty circle.
			mkLabel(card, {
				Text = crate.icon or "\xF0\x9F\x93\xA6", Font = Enum.Font.FredokaOne, TextSize = 62,
				TextScaled = true, Size = UDim2.fromOffset(69, 69),
				Position = UDim2.new(0, cx, 0, cy - (sk.pedestal and 6 or 0)),
				AnchorPoint = Vector2.new(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5,
			}):SetAttribute("BTS_Skip", true)
			for _, sp in ipairs({ { -6, -8, 15, 0.2 }, { 74, 4, 11, 0.4 }, { 66, 68, 13, 0.3 } }) do
				mkLabel(card, {
					Text = "\xE2\x9C\xA6", Font = Enum.Font.FredokaOne, TextSize = sp[3], TextScaled = true,
					TextColor3 = sk.glow, TextTransparency = sp[4],
					Size = UDim2.fromOffset(sp[3], sp[3]),
					Position = UDim2.new(0, CARD_INSET + sp[1], 0, 14 + sp[2]), ZIndex = 6,
				}):SetAttribute("BTS_Skip", true)
			end
		end

		-- WHITE, not gold. Gold is what "tickets" means on this panel (the balance pill, the price on this very
		-- card), and painting the crate's NAME the same colour made the two read as one object.
		local nameLbl = mkLabel(card, {
			Text = crate.displayName:upper(), Font = Enum.Font.FredokaOne, TextSize = 24, TextScaled = true,
			TextColor3 = WHITE,
			Size = UDim2.fromOffset(TEXT_W - (crate.limited and 82 or 0), 30),
			Position = UDim2.new(0, TEXT_X, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
		})
		mkStroke(nameLbl, Color3.new(0, 0, 0), 2)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 24; c.Parent = nameLbl end
		-- LIMITED crates (events / Season Pass / Robux bundles) are called out so nobody assumes the pool is
		-- permanent. They're still openable with tokens here -- the tag is about the COLLECTION rotating, not
		-- about the button being disabled.
		if crate.limited then
			local tag = mkFrame(card, {
				Size = UDim2.fromOffset(74, 18),
				Position = UDim2.new(0, TEXT_X + TEXT_W - 74, 0, 21),
				BackgroundColor3 = Color3.fromRGB(240, 96, 180), ZIndex = 3,
			})
			mkCorner(tag, 9); mkStroke(tag, Color3.fromRGB(160, 50, 120), 1.5)
			mkLabel(tag, {
				Text = "LIMITED", Font = Enum.Font.GothamBold, TextSize = 11, TextScaled = true, TextColor3 = WHITE,
				Size = UDim2.new(1, -6, 1, 0), Position = UDim2.new(0, 3, 0, 0), ZIndex = 4,
			})
		end

		-- ---- the description, split at its first full stop -----------------------------------
		-- Two labels rather than one wrapped block, because a TextLabel has ONE TextColor3 and the Pet Crate
		-- wants its opening claim ("A pet at a rolled rarity.") in its accent colour with the consequence
		-- ("Duplicates stack -- fuse them to climb the ladder.") in white underneath. Splitting on the first
		-- sentence is generic: a crate whose two colours are the same -- which is every other crate -- simply
		-- renders as one paragraph across two lines, exactly as it did before.
		do
			local blurb = crate.blurb or ""
			local a, b = blurb:match("^(.-%.)%s+(.+)$")
			if not a then a, b = blurb, nil end
			mkLabel(card, {
				Text = a, Font = Enum.Font.GothamBold, TextSize = 14, TextScaled = true, TextColor3 = sk.descA,
				Size = UDim2.fromOffset(TEXT_W, 20), Position = UDim2.new(0, TEXT_X, 0, 52),
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
			})
			if b then
				mkLabel(card, {
					Text = b, Font = Enum.Font.Gotham, TextSize = 13, TextScaled = true, TextColor3 = sk.descB,
					Size = UDim2.fromOffset(TEXT_W, 20), Position = UDim2.new(0, TEXT_X, 0, 74),
					TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
				})
			end
		end

		-- contents summary: how many items in each rarity band
		local counts = {}
		for _, e in ipairs(SkinCrates.flatContents(crate.id)) do counts[e.rarity] = (counts[e.rarity] or 0) + 1 end
		-- At half size all six pills fit ONE row again (6*58 + 5*4 = 368) inside the 418px this row has before
		-- the OPEN button's column starts -- so nothing wraps and nothing runs underneath the button, which is
		-- what used to hide the Legendary and Gold chances.
		-- The chips are sized to DIVIDE the row rather than to a fixed 58 that happened to fit six of them.
		-- A crate with a different number of bands now fills the row instead of overflowing it or leaving a
		-- gap, and the row itself is exactly the text column, so the last chip can never cross the card edge.
		local BAND_GAP = 6
		local shownBands = 0
		for _, r in ipairs(SkinCrates.RARITY_ORDER) do
			if (counts[r] or 0) > 0 then shownBands = shownBands + 1 end
		end
		-- FULL CARD WIDTH, not the text column: see the grid note at the top of this loop. Six chips get 98px
		-- each here instead of 54, which is the difference between reading "Legendary 0.9%" and guessing at it.
		local BAND_W = CARD_W - CARD_INSET * 2
		local pillW = 98
		if shownBands > 0 then
			pillW = math.floor((BAND_W - BAND_GAP * (shownBands - 1)) / shownBands)
		end
		local bandRow = mkFrame(card, { Size = UDim2.fromOffset(BAND_W, 32), Position = UDim2.new(0, CARD_INSET, 0, 120), BackgroundTransparency = 1, ZIndex = 3 })
		do
			local ll = Instance.new("UIListLayout"); ll.FillDirection = Enum.FillDirection.Horizontal
			ll.Padding = UDim.new(0, BAND_GAP); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = bandRow
		end
		-- THE PILLS SHOW *YOUR* ODDS, not the base table. luckFor() folds in rebirth luck (from the replicated
		-- Rebirths leaderstat) and the Lucky Pass, so a player who has paid for better odds is shown the better
		-- odds -- and a player who has not sees exactly the numbers this panel always showed, because luckFor
		-- returns 1.0 for them and 1.0 leaves the weights bit-for-bit untouched.
		--
		-- The server re-derives luck itself at roll time, so this is display only and cannot influence a roll.
		local odds = SkinCrates.effectiveOdds(crate.id, Gamepasses.luckFor(player))
		for oi, rarity in ipairs(SkinCrates.RARITY_ORDER) do
			if (counts[rarity] or 0) > 0 then
				-- EACH CHIP IS OUTLINED IN ITS OWN COLOUR, DARKENED, rather than all six sharing one navy edge.
				-- A single dark outline on six different fills reads as a grid of boxes; a darker shade of the
				-- fill reads as the edge of that chip, which is what makes the row scan as six separate
				-- rarities. 55% of each channel is a shade down without going muddy or shifting hue.
				local bc = PetSkins.tierColor(rarity)
				local pill = mkFrame(bandRow, {
					Size = UDim2.fromOffset(pillW, 32), LayoutOrder = oi,
					BackgroundColor3 = bc, ZIndex = 4,
				})
				mkCorner(pill, 10)
				mkStroke(pill, Color3.new(bc.R * 0.55, bc.G * 0.55, bc.B * 0.55), 2)
				-- TWO LINES: the band name over its percentage. On one line the name and the number competed
				-- for the same 98px and TextScaled shrank both to fit; stacked, each gets the full width and
				-- the number -- the thing you are actually comparing between crates -- can be the bigger of
				-- the two. Dark ink on every chip: all six band colours are light enough to carry it, which
				-- is what keeps the row legible without a per-colour contrast rule.
				mkLabel(pill, {
					Text = rarity:upper(), Font = Enum.Font.GothamBold, TextSize = 10, TextScaled = true,
					TextColor3 = Color3.fromRGB(28, 32, 44), Size = UDim2.new(1, -8, 0, 11),
					Position = UDim2.new(0, 4, 0, 4), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5,
				})
				-- one decimal, not two: "79.92%" is more precision than the chip has room to mean
				mkLabel(pill, {
					Text = string.format("%.1f%%", odds[rarity] or 0), Font = Enum.Font.FredokaOne,
					TextSize = 14, TextScaled = true, TextColor3 = Color3.fromRGB(20, 24, 34),
					Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 0, 15),
					TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5,
				})
			end
		end

		-- ---- price + OPEN --------------------------------------------------------------------
		-- THE PRICE IS THE TICKET ICON IN RED plus the number in gold, as two labels. One label has one
		-- TextColor3, and red-for-tickets is the rule the whole panel follows now (the balance pill, every
		-- pack row's tile, the footer banner).
		local canAfford = state.tokens >= crate.price
		mkLabel(card, {
			Text = CrateTokens.ICON, Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
			TextColor3 = RED, Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(1, -CARD_INSET - 72, 0, 18), AnchorPoint = Vector2.new(1, 0), ZIndex = 3,
		}):SetAttribute("BTS_Skip", true)
		local priceLbl = mkLabel(card, {
			Text = CrateTokens.format(crate.price), Font = Enum.Font.FredokaOne,
			TextSize = 22, TextScaled = true, TextColor3 = canAfford and GOLD or Color3.fromRGB(255, 150, 150),
			Size = UDim2.fromOffset(68, 26),
			Position = UDim2.new(1, -CARD_INSET, 0, 17), AnchorPoint = Vector2.new(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
		})
		mkStroke(priceLbl, Color3.new(0, 0, 0), 2)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.Parent = priceLbl end

		-- THE UNAFFORDABLE STATE IS TINTED TO THE CARD, not the same grey slab on every crate. A neutral grey
		-- button on a warm brown card reads as broken UI; a muted version of the card's own colour reads as
		-- "not yet". It is still obviously inert next to the green -- that is what the saturation drop does --
		-- and it still leads somewhere: the click sends you to the ticket packs rather than doing nothing.
		local openBtn = mkButton(card, {
			Size = UDim2.fromOffset(RIGHT_COL, 52),
			Position = UDim2.new(1, -CARD_INSET, 0, 56), AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = canAfford and LIME or sk.muted,
			Text = "", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = WHITE,
			AutoButtonColor = canAfford, ZIndex = 3, ClipsDescendants = true,
		})
		mkCorner(openBtn, 14); mkStroke(openBtn, canAfford and LIME_DARK or sk.mutedEdge, 2)
		if not canAfford then
			-- A big faint ticket bleeding off the button's right edge -- it says what the button is short of
			-- without spending any of the 168px the words need. Clipped by the button itself.
			mkLabel(openBtn, {
				Text = CrateTokens.ICON, Font = Enum.Font.FredokaOne, TextSize = 54, TextScaled = true,
				TextColor3 = WHITE, TextTransparency = 0.87,
				Size = UDim2.fromOffset(54, 54), Position = UDim2.new(1, -6, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5), Rotation = -12, ZIndex = 4,
			}):SetAttribute("BTS_Skip", true)
		else
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(188, 188, 188))
			g.Rotation = 90; g.Parent = openBtn
		end
		-- The word is a CHILD label: a UIStroke on a FILLED text object outlines the object's border, not its
		-- glyphs, so the black edge that keeps white text readable can only come from a transparent label.
		local openLbl = mkLabel(openBtn, {
			Name = "Label", Text = canAfford and "OPEN" or "NEED TICKETS",
			Font = Enum.Font.FredokaOne, TextSize = canAfford and 24 or 15, TextScaled = true,
			TextColor3 = WHITE, Size = UDim2.new(1, -14, 1, -12), Position = UDim2.new(0, 7, 0, 6), ZIndex = 5,
		})
		mkStroke(openLbl, Color3.new(0, 0, 0), 2)
		do
			local c = Instance.new("UITextSizeConstraint")
			c.MaxTextSize = canAfford and 26 or 16; c.Parent = openLbl
		end
		openBtn:SetAttribute("BTS_Skip", true); openLbl:SetAttribute("BTS_Skip", true)
		openBtn.MouseButton1Click:Connect(function()
			playUIClick()
			if not canAfford then
				-- Not enough tokens: send them to the tab that fixes it rather than a dead-end error.
				activeTab = "tokens"; refreshTabs()
				return
			end
			doOpenCrate(crate)
		end)
	end

	-- Honest-odds footer. Same promise as before, but as a heading + one plain sentence instead of two disclosure
	-- lines run together and stretched by TextScaled.
	--
	-- Every label here needs TextScaled + a UITextSizeConstraint rather than a plain TextSize: CoreClient's
	-- repositionGUIs sweep force-sets TextScaled = true on every TextLabel under PlayerGui, so an authored
	-- TextSize gets blown up to fill its frame. The constraint is the only thing that actually holds a size.
	local note = mkFrame(body, { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = HEADER, LayoutOrder = 999 })
	mkCorner(note, 12); mkStroke(note, GOLD, 1.5)
	local noteTitle = mkLabel(note, {
		Text = "\xE2\xAD\x90 THESE ARE THE REAL DROP CHANCES",
		Font = Enum.Font.FredokaOne, TextSize = 15, TextScaled = true, TextColor3 = GOLD,
		Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 9),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = noteTitle end
	local noteBody = mkLabel(note, {
		Text = "Rarity rolls first, then a random item from it, then the trait.",
		Font = Enum.Font.Gotham, TextSize = 12, TextScaled = true, TextColor3 = Color3.fromRGB(196, 214, 250),
		Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 33),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 12; c.Parent = noteBody end
end

-- ============================================================================================================
-- TAB: TICKETS  --  the buy ladder, and nothing else.
-- ============================================================================================================
-- ONE ROW PER PACK, IN THE PAGE'S OWN SCROLL.
--
-- This page used to be a card (`column("BUY TICKETS")`) holding a ScrollingFrame of its own, sitting inside
-- `body`, which is itself a ScrollingFrame. Two nested scrolls over the same axis is the worst thing a
-- touch UI can do: a drag that starts on the inner list scrolls the inner list, the same drag two pixels
-- higher scrolls the outer one, and neither ever reaches the end of the other's content. It also meant two
-- scrollbars on screen at once, two sets of padding to keep in step, and a card height computed from the
-- panel's height by hand (`BODY_RUN = 388`) that had to be re-derived every time anything above it moved.
--
-- The rows go straight into `body` now. It already scrolls, already reserves its own scrollbar lane on the
-- right (BODY_PAD + BODY_BAR), already has the UIListLayout, and already knows how tall it is -- so the
-- ladder inherits all of that and this function stops owning any geometry it does not need to.
--
-- ---- EVERY NUMBER ON A ROW IS COMPUTED FROM SkinCrates.TOKEN_PACKS ------------------------------------------
-- The amount, the price, the tickets-per-R$ and the +% VALUE chip are all derived from the same table the
-- SERVER charges against, so this shelf physically cannot advertise a rate or a price the purchase does not
-- honour. Nothing here is a typed-in figure that can drift out of step with the products.
local function buildTokensTab()
	local ROW_H     = 82
	local ROW_INSET = 12
	local TILE      = 56    -- the ticket-icon square
	local BUY_W     = 156   -- the green button on the right
	local TEXT_X    = ROW_INSET + TILE + 14

	-- ROW COLOURS. Deliberately NOT the CARD blue the crate cards use: this is a shop shelf rather than a
	-- collection, and the darker navy is what lets the white amount and the green button carry the row.
	local ROW_BG    = Color3.fromRGB( 17,  58, 130)
	local TILE_BG   = Color3.fromRGB(  9,  34,  86)
	local SUBTEXT   = Color3.fromRGB(158, 180, 214)
	local POPULAR   = Color3.fromRGB( 48, 132, 255)
	local VALUE_INK = Color3.fromRGB(126, 206, 255)

	-- The Robux glyph. U+E002 is Roblox's own private-use character for it and renders in the client's
	-- built-in fonts, which is why the price can be an icon plus a number instead of the string "R$".
	-- IF IT EVER SHOWS AS AN EMPTY BOX (a font that does not carry the private-use range), set this to ""
	-- and the button falls back to reading "25 R$" -- the " R$" suffix below is kept for exactly that reason.
	local ROBUX = "\xEE\x80\x82"

	-- CHEAPEST FIRST, sorted here rather than trusting the authored order, so adding a pack to
	-- SkinCrates.TOKEN_PACKS can never drop it into the middle of the ladder.
	local packs = {}
	for _, pk in ipairs(SkinCrates.TOKEN_PACKS) do packs[#packs + 1] = pk end
	table.sort(packs, function(a, b) return (a.robux or 0) < (b.robux or 0) end)

	-- THE BASELINE THE VALUE CHIPS ARE MEASURED AGAINST is the cheapest pack, because that is a price a
	-- player can actually pay. The usual way to get a percentage onto every row is to invent a
	-- "single ticket" price nobody sells and discount everything off that -- but a saving against a price
	-- that does not exist is a made-up saving. This one is real, and the tickets-per-R$ sits right beside it
	-- so anyone can check the arithmetic. The entry pack therefore carries no chip: it is the thing the
	-- others are better THAN, and stamping it with a discount against itself would be the one dishonest
	-- label on the shelf.
	local basePack = packs[1]
	local baseRate = basePack and (basePack.tokens / math.max(1, basePack.robux)) or 0

	for i, pack in ipairs(packs) do
		local row = mkFrame(body, {
			Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = ROW_BG, LayoutOrder = i,
		})
		mkCorner(row, 14); mkStroke(row, Color3.fromRGB(70, 120, 200), 1.5)
		-- GLOSS -- A SEPARATE WHITE OVERLAY, NOT A GRADIENT ON THE ROW ITSELF.
		-- UIGradient MULTIPLIES its parent's BackgroundColor3, so a gradient parented to the row can only ever
		-- make the navy darker; there is no multiplier above 1 and therefore no way to add a highlight that
		-- way. A faint white child with its own top-to-bottom transparency ramp is the only thing that adds
		-- light. It is created FIRST so every sibling built after it draws on top (equal ZIndex resolves by
		-- creation order), and it fades to fully clear well above the text, so the navy that the amount and
		-- the subtext were contrast-checked against is untouched where they actually sit.
		do
			local gloss = mkFrame(row, {
				Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = WHITE, BackgroundTransparency = 0.88,
				ZIndex = 1,
			})
			mkCorner(gloss, 14)
			local g = Instance.new("UIGradient")
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			g.Rotation = 90
			g.Parent = gloss
		end

		-- ---- the ticket tile ----------------------------------------------------------------
		local tile = mkFrame(row, {
			Size = UDim2.new(0, TILE, 0, TILE), Position = UDim2.new(0, ROW_INSET, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = TILE_BG,
		})
		mkCorner(tile, 14); mkStroke(tile, Color3.fromRGB(52, 96, 172), 1.5)
		mkLabel(tile, {
			Text = CrateTokens.ICON, Font = Enum.Font.FredokaOne, TextSize = 28, TextScaled = true,
			TextColor3 = RED, Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6), ZIndex = 2,
		})
		-- SPARKLES. Three four-point stars tucked into the tile's corners, gold and half-faded, at three
		-- different sizes so they read as a scatter rather than as a pattern. They say "this is the treat you
		-- are buying" on a tile that is otherwise a dark square with an icon in it.
		for _, sp in ipairs({ { 4, 3, 13, 0.25 }, { 42, 8, 9, 0.45 }, { 8, 39, 10, 0.4 } }) do
			mkLabel(tile, {
				Text = "\xE2\x9C\xA6", Font = Enum.Font.FredokaOne, TextSize = sp[3], TextScaled = true,
				TextColor3 = GOLD, TextTransparency = sp[4],
				Size = UDim2.new(0, sp[3], 0, sp[3]), Position = UDim2.new(0, sp[1], 0, sp[2]), ZIndex = 3,
			}):SetAttribute("BTS_Skip", true)
		end

		-- ---- line 1: the amount, then the value chip ----------------------------------------
		-- The amount is measured, not stretched: a TextScaled label given the whole remaining width would
		-- blow "100" up to the height of the row and leave the chip beside it looking like a footnote.
		local amountW = 96
		local amt = mkLabel(row, {
			Text = CrateTokens.format(pack.tokens), Font = Enum.Font.FredokaOne, TextSize = 30,
			TextScaled = true, TextColor3 = WHITE,
			Size = UDim2.new(0, amountW, 0, 32), Position = UDim2.new(0, TEXT_X, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(amt, Color3.new(0, 0, 0), 2)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 30; c.Parent = amt end

		local thisRate = pack.tokens / math.max(1, pack.robux)
		local bonus = (baseRate > 0) and math.floor((thisRate / baseRate - 1) * 100 + 0.5) or 0
		if bonus >= 1 then
			-- OUTLINED, not filled. The row already carries a filled green button and (on one row) a filled
			-- blue chip; a third filled colour is where a shelf starts looking like a warning label. An
			-- outline reads as a note ON the amount rather than as another thing competing with it.
			-- 116, not 104: the star costs about a character of width, and TextScaled would otherwise pay for
			-- it by shrinking "+57% VALUE" -- the number is the point of the chip and must not get smaller.
			local vchip = mkFrame(row, {
				Size = UDim2.new(0, 116, 0, 24), Position = UDim2.new(0, TEXT_X + amountW + 4, 0, 18),
				BackgroundColor3 = VALUE_INK, BackgroundTransparency = 0.86,
			})
			-- 10, not 8. Every other corner on this row is 12-14, and a chip two steps sharper than the
			-- card it sits on is what makes a row look like it has square corners even when it does not.
			-- Not the full 12: on a 24px-tall chip that is halfway to a lozenge.
			mkCorner(vchip, 10); mkStroke(vchip, VALUE_INK, 1.5)
			mkLabel(vchip, {
				-- The star is part of the chip's own text rather than a second label: at 24px tall there is no
				-- room for two boxes, and TextScaled shrinks the whole phrase together so the star can never
				-- end up a different size from the words beside it.
				Text = "\xE2\xAD\x90 +" .. bonus .. "% VALUE", Font = Enum.Font.GothamBold, TextSize = 12,
				TextScaled = true, TextColor3 = VALUE_INK,
				Size = UDim2.new(1, -10, 1, -8), Position = UDim2.new(0, 5, 0, 4),
			})
		end

		-- ---- line 2: the POPULAR chip, then the rate ----------------------------------------
		-- rateX walks right as things are placed before it, so the chip and the sentence can never overlap
		-- and the sentence sits flush against the amount above it when there is no chip at all.
		local rateX = TEXT_X
		if pack.tag then
			local chip = mkFrame(row, {
				Size = UDim2.new(0, 84, 0, 22), Position = UDim2.new(0, TEXT_X, 0, 50),
				BackgroundColor3 = POPULAR,
			})
			mkCorner(chip, 10); mkStroke(chip, Color3.fromRGB(18, 62, 140), 2)
			local cl = mkLabel(chip, {
				Text = pack.tag:upper(), Font = Enum.Font.GothamBold, TextSize = 12, TextScaled = true,
				TextColor3 = WHITE, Size = UDim2.new(1, -8, 1, -6), Position = UDim2.new(0, 4, 0, 3),
			})
			mkStroke(cl, Color3.new(0, 0, 0), 1.5)
			rateX = TEXT_X + 84 + 8
		end
		-- One decimal, with a bare "4" rather than "4.0" -- a trailing zero on a rate reads as more
		-- precision than the number has.
		local rate = math.floor(thisRate * 10 + 0.5) / 10
		local rateText = (rate % 1 == 0) and tostring(math.floor(rate)) or tostring(rate)
		local rateLbl = mkLabel(row, {
			Text = rateText .. " tickets per R$", Font = Enum.Font.Gotham, TextSize = 13, TextScaled = true,
			TextColor3 = SUBTEXT,
			Size = UDim2.new(1, -(rateX + BUY_W + ROW_INSET + 12), 0, 20),
			Position = UDim2.new(0, rateX, 0, 51),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 13; c.Parent = rateLbl end

		-- ---- the buy button ------------------------------------------------------------------
		-- THE DARKER BOTTOM EDGE is a separate slab sitting 4px lower than the button, not a gradient on it:
		-- that is what makes it read as a physical key with a lip you press down onto, which is the button
		-- language this whole game uses (the Pet Hut's DROP OFF and WAKE UP are built the same way). A
		-- gradient would only make the button look shaded.
		local buyBase = mkFrame(row, {
			Size = UDim2.new(0, BUY_W, 0, 48), Position = UDim2.new(1, -ROW_INSET, 0.5, 4),
			AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = LIME_DARK,
		})
		mkCorner(buyBase, 14)
		local buy = mkButton(row, {
			Size = UDim2.new(0, BUY_W, 0, 48), Position = UDim2.new(1, -ROW_INSET, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = LIME, Text = "",
			Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = WHITE, ZIndex = 2,
		})
		mkCorner(buy, 14); mkStroke(buy, LIME_DARK, 2.5)
		do
			-- A gentle top-to-bottom shade on the key face, so the lip below it has something to be the shadow
			-- of. WHITE at the top and grey at the bottom because UIGradient MULTIPLIES the fill: white is 1.0
			-- (the button's own green, unchanged) and the grey darkens the bottom toward the lip. Starting
			-- from a lighter green instead would not work -- there is no multiplier above 1, so a gradient can
			-- only ever take light away.
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(188, 188, 188))
			g.Rotation = 90; g.Parent = buy
		end
		-- The word is a CHILD label, same rule the tab bar and the bottom nav follow: a UIStroke on a FILLED
		-- text object outlines the object's BORDER, not its glyphs, so the black edge that keeps white text
		-- readable on this green can only come from a transparent label sitting on top of the button.
		local buyLbl = mkLabel(buy, {
			Name = "Label", Text = ROBUX .. " " .. pack.robux .. " R$",
			Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true, TextColor3 = WHITE,
			Size = UDim2.new(1, -14, 1, -12), Position = UDim2.new(0, 7, 0, 6), ZIndex = buy.ZIndex + 1,
		})
		mkStroke(buyLbl, Color3.new(0, 0, 0), 2)
		do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 20; c.Parent = buyLbl end
		-- HANDS OFF: ButtonTextStyle's legibility sweep repaints button text from whatever contrast it
		-- computes, which would undo the white-on-green the outline is built around.
		buy:SetAttribute("BTS_Skip", true); buyLbl:SetAttribute("BTS_Skip", true)

		-- UNCHANGED PURCHASE PATH. Same remote, same pack id, same server handler as before the rebuild --
		-- this is a visual change and the money must not move an inch.
		buy.MouseButton1Click:Connect(function()
			playUIClick()
			BuyTokens:FireServer(pack.id)
		end)
	end

	if SkinCrates.TEST_MODE then
		local warn = mkFrame(body, { Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Color3.fromRGB(255, 160, 20), LayoutOrder = #packs + 1 })
		mkCorner(warn, 10)
		mkLabel(warn, {
			Text = "TEST MODE: packs credit tickets with no Robux charge. Set SkinCrates.TEST_MODE = false at launch.",
			Font = Enum.Font.GothamBold, TextSize = 12, TextScaled = true, TextColor3 = Color3.fromRGB(70, 40, 0),
			Size = UDim2.new(1, -12, 1, -6), Position = UDim2.new(0, 6, 0, 3),
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		})
	end
end

-- ============================================================================================================
-- TAB: TRADE UP
-- ============================================================================================================
-- Hand in 10 skins of one rarity for 1 random skin of the next rarity up.
--
-- WHICH 10 GET BURNED is the part that needs care. Auto-picking the first ten the loop happens to see could
-- destroy the only copy of something the player likes, and "I lost my Cosmic to a trade-up I didn't read" is the
-- kind of thing that makes people stop trading up entirely. So:
--   * spares first -- a key with 4 copies contributes 3 before anything unique is touched;
--   * then, only if still short, unique items, rarest-looking last;
--   * and nothing is sent until the player has seen the exact list on a confirm screen.
local tradeUpInFlight = false
local showTradeUpResult -- forward (defined with the reveal helpers below)

-- Build the list of keys a contract at `tier` would consume, spares first. Returns the key list (may be short)
-- and the total number of that tier the player holds.
local function planTradeUp(tier)
	local need = SkinCrates.TRADE_UP.COST
	local entries, total = {}, 0
	for key, count in pairs(state.skins) do
		local petId, skinId = PetSkins.parseKey(key)
		if petId and skinId and PetSkins.tierOf(skinId) == tier then
			local n = math.max(0, math.floor(tonumber(count) or 0))
			if n > 0 then
				entries[#entries + 1] = { key = key, pet = petId, skin = skinId, count = n }
				total = total + n
			end
		end
	end
	-- most-duplicated first, so the deepest stacks are spent before the thin ones
	table.sort(entries, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		if a.pet ~= b.pet then return a.pet < b.pet end
		return a.skin < b.skin
	end)

	local picked = {}
	-- PASS 1: spares only (leave one of each behind)
	for _, e in ipairs(entries) do
		local spare = e.count - 1
		while spare > 0 and #picked < need do picked[#picked + 1] = e.key; spare = spare - 1 end
		if #picked >= need then break end
	end
	-- PASS 2: still short -> start taking last copies
	if #picked < need then
		for _, e in ipairs(entries) do
			local used = 0
			for _, k in ipairs(picked) do if k == e.key then used = used + 1 end end
			if used < e.count and #picked < need then picked[#picked + 1] = e.key end
			if #picked >= need then break end
		end
	end
	return picked, total
end

-- Confirmation overlay: shows exactly what is about to be destroyed and what tier comes back.
local function confirmTradeUp(tier, target, keys, onYes)
	local shade = mkFrame(panel, {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35, ZIndex = 60, Active = true,
	})
	local box = mkFrame(shade, {
		Size = UDim2.new(0, 460, 0, 370), Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, ZIndex = 61,
	})
	mkCorner(box, 16); mkStroke(box, PetSkins.tierColor(target), 3)

	local h = mkLabel(box, {
		Text = "TRADE UP: " .. tier .. " \xE2\x86\x92 " .. target, Font = Enum.Font.FredokaOne, TextSize = 24,
		TextScaled = true, TextColor3 = PetSkins.tierColor(target), Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.new(0, 10, 0, 10), ZIndex = 62,
	})
	mkStroke(h, Color3.new(0, 0, 0), 2)
	mkLabel(box, {
		Text = "These " .. #keys .. " will be DESTROYED for 1 random " .. target .. ". The pet, the skin and the "
			.. "trait are all rolled fresh.",
		Font = Enum.Font.GothamBold, TextSize = 13, TextScaled = true, TextColor3 = Color3.fromRGB(215, 228, 255),
		Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 46), TextWrapped = true, ZIndex = 62,
	})

	-- the exact list, collapsed to "Skin Pet xN"
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 84); list.Size = UDim2.new(1, -24, 0, 210)
	list.BackgroundColor3 = CARD; list.BackgroundTransparency = 0.25; list.BorderSizePixel = 0
	list.ScrollBarThickness = 5; list.ScrollBarImageColor3 = GOLD; list.ZIndex = 62
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = box
	mkCorner(list, 10)
	do
		local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 3)
		ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = list
		local pd = Instance.new("UIPadding"); pd.PaddingTop = UDim.new(0, 5); pd.PaddingLeft = UDim.new(0, 8)
		pd.Parent = list
	end
	local tally, order = {}, {}
	for _, k in ipairs(keys) do
		if not tally[k] then tally[k] = 0; order[#order + 1] = k end
		tally[k] = tally[k] + 1
	end
	for i, k in ipairs(order) do
		local petId, skinId, traitId = PetSkins.parseKey(k)
		local txt = PetSkins.displayName(skinId, PetSkins.prettyPet(petId))
		if not PetTraits.isNone(traitId) then txt = txt .. " (" .. PetTraits.displayName(traitId) .. ")" end
		mkLabel(list, {
			Text = "\xE2\x80\xA2  " .. txt .. "   x" .. tally[k], Font = Enum.Font.GothamBold, TextSize = 14,
			TextScaled = true, TextColor3 = WHITE, Size = UDim2.new(1, -16, 0, 20), LayoutOrder = i,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 63,
		})
	end

	local function close() shade:Destroy() end
	local no = mkButton(box, {
		Size = UDim2.new(0, 200, 0, 46), Position = UDim2.new(0, 14, 1, -56), BackgroundColor3 = CARD,
		Text = "CANCEL", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true, TextColor3 = WHITE, ZIndex = 62,
	})
	mkCorner(no, 12); mkStroke(no, WHITE, 2)
	no.MouseButton1Click:Connect(function() playUIClick(); close() end)

	local yes = mkButton(box, {
		Size = UDim2.new(0, 200, 0, 46), Position = UDim2.new(1, -214, 1, -56), BackgroundColor3 = LIME,
		Text = "TRADE UP", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true, TextColor3 = WHITE, ZIndex = 62,
	})
	mkCorner(yes, 12); mkStroke(yes, LIME_DARK, 2)
	yes.MouseButton1Click:Connect(function() playUIClick(); close(); onYes() end)
end

local function buildTradeUpTab()
	local intro = mkFrame(body, { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = HEADER, LayoutOrder = 1 })
	mkCorner(intro, 12); mkStroke(intro, GOLD, 1.5)
	mkLabel(intro, {
		Text = "TRADE UP MACHINE\nGive " .. SkinCrates.TRADE_UP.COST .. " skins of one rarity, get 1 random skin "
			.. "of the next rarity up. Duplicates are perfect for this.",
		Font = Enum.Font.GothamBold, TextSize = 13, TextScaled = true, TextColor3 = Color3.fromRGB(215, 228, 255),
		Size = UDim2.new(1, -16, 1, -8), Position = UDim2.new(0, 8, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
	})

	local need = SkinCrates.TRADE_UP.COST
	for i, tier in ipairs(SkinCrates.RARITY_ORDER) do
		-- Gold is a pet/crate band, not a skin tier -- no skin can ever sit in it, so a Gold contract row
		-- would be a permanent dead line. Skip it entirely; Legendary is the ladder's visible top.
		if tier == SkinCrates.GOLD_TIER then continue end
		local target = SkinCrates.tradeUpTarget(tier)
		local keys, total = planTradeUp(tier)
		local canDo = target ~= nil and #keys >= need
		local tierCol = PetSkins.tierColor(tier)

		local row = mkFrame(body, { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = CARD, LayoutOrder = i + 1 })
		mkCorner(row, 12); mkStroke(row, tierCol, canDo and 3 or 2)
		if canDo then applyRarityFlair(row, tier) end -- only draw the eye to a contract that's actually ready

		local stripe = mkFrame(row, { Size = UDim2.new(0, 8, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = tierCol })
		mkCorner(stripe, 4)

		local title = target
			and (tier .. "  \xE2\x86\x92  " .. target)
			or (tier .. "  \xE2\x80\xA2  top rarity")
		local nameLbl = mkLabel(row, {
			Text = title, Font = Enum.Font.FredokaOne, TextSize = 19, TextScaled = true,
			TextColor3 = target and WHITE or Color3.fromRGB(170, 182, 200),
			Size = UDim2.new(1, -290, 0, 24), Position = UDim2.new(0, 22, 0, 8),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkStroke(nameLbl, Color3.new(0, 0, 0), 2)

		local sub
		if not target then
			sub = "Nothing to trade up into -- " .. tier .. " is the top of the ladder."
		else
			sub = "You have " .. total .. " " .. tier .. "   \xE2\x80\xA2   need " .. need
		end
		mkLabel(row, {
			Text = sub, Font = Enum.Font.GothamBold, TextSize = 13, TextScaled = true,
			TextColor3 = canDo and Color3.fromRGB(180, 255, 190) or Color3.fromRGB(205, 224, 255),
			Size = UDim2.new(1, -290, 0, 18), Position = UDim2.new(0, 22, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		if target then
			local btn = mkButton(row, {
				Size = UDim2.new(0, 150, 0, 42), Position = UDim2.new(1, -162, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = canDo and LIME or Color3.fromRGB(120, 130, 145),
				Text = canDo and "TRADE UP" or (math.min(total, need) .. " / " .. need),
				Font = Enum.Font.FredokaOne, TextSize = 16, TextScaled = true, TextColor3 = WHITE,
			})
			mkCorner(btn, 10); mkStroke(btn, canDo and LIME_DARK or Color3.fromRGB(90, 98, 112), 2)
			if canDo then
				btn.MouseButton1Click:Connect(function()
					playUIClick()
					if tradeUpInFlight then return end
					-- Re-plan at click time rather than trusting the list built when the tab was drawn: a crate
					-- opened, or a trade completed, in between would otherwise submit stale keys the server rejects.
					local liveKeys, liveTotal = planTradeUp(tier)
					if #liveKeys < need then
						refreshTabs() -- the tab is stale; redraw it so the count tells the truth
						return
					end
					local _ = liveTotal
					confirmTradeUp(tier, target, liveKeys, function()
						if tradeUpInFlight then return end
						tradeUpInFlight = true
						task.spawn(function()
							local ok, result = pcall(function() return TradeUpRF:InvokeServer(tier, liveKeys) end)
							tradeUpInFlight = false
							if ok and type(result) == "table" and result.ok then
								if showTradeUpResult then showTradeUpResult(result) end
							else
								local why = (type(result) == "table" and result.reason) or "error"
								warn("[SkinCrate] trade-up refused: " .. tostring(why))
								refreshTabs()
							end
						end)
					end)
				end)
			end
		end
	end
end

-- ============================================================================================================
-- TAB SWITCHING
-- ============================================================================================================
refreshTabs = function()
	-- The icon is its own red label inside the pill now (see the pill build), so this carries only the number.
	tokenLbl.Text = CrateTokens.format(state.tokens)
	-- A sub-page keeps its PARENT tab lit: a page with no tab highlighted reads as being lost.
	--
	-- They light DIFFERENT parents, because they belong to different ones. TOKENS is the crate shop, so it
	-- lights CRATES. TRADE UP burns duplicate skins and is entered from the hub's PETS page, so it lights
	-- PETS -- it used to light CRATES, which made pressing TRADE UP look like it had dumped you in the crate
	-- list, on a page that has nothing to do with crates.
	local litTab = activeTab
	if litTab == "tokens" then litTab = "crates"
	elseif litTab == "tradeup" then litTab = "pets" end
	for id, b in pairs(tabButtons) do
		local on = (id == litTab)
		-- Selected = yellow, unselected = TAB_IDLE -- the hub bar's exact blue, see the constant.
		b.BackgroundColor3 = on and GOLD or TAB_IDLE
		-- Selected = dark-on-gold (max contrast, unmistakably the active tab); unselected = gold-on-blue,
		-- matching the panel title rather than shouting in pure white.
		-- The word lives in a child label now (see the tab build): paint that, or the selected tab keeps
		-- the unselected tab's gold text. b.TextColor3 is kept in step so nothing reading it goes stale.
		b.TextColor3 = on and Color3.fromRGB(92, 58, 8) or TAB_INK
		local lbl = b:FindFirstChild("Label")
		if lbl then lbl.TextColor3 = b.TextColor3 end
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then st.Color = on and Color3.fromRGB(180, 122, 20) or TAB_EDGE; st.Thickness = on and 2.5 or 1.5 end
	end
	-- BOTTOM NAV: lit on the page you are actually on. activeTab is the real page id here (the top bar
	-- collapses all four crate pages to "crates" via litTab above -- that is what makes the two bars say
	-- different, complementary things: Crates, and then which part of Crates).
	-- THE BANNER BUTTON IS NOT A PAGE INDICATOR ANY MORE, so it is no longer repainted here. It used to be one
	-- of a row of nav pills that lit gold on the page they led to; now it is the single call to action on the
	-- GET TICKETS plinth, and it is gold on every page by design. Dimming it to navy whenever you were not
	-- already on the packs would grey out the one button the banner exists to sell.
	--
	-- The loop stays (over an unchanged bottomNavButtons) so a second nav pill can be added back without
	-- re-plumbing, and so the label lookup below keeps working.
	for _, b in pairs(bottomNavButtons) do
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then st.Thickness = (activeTab == "tokens") and 3 or 2 end
	end
	if not gui.Enabled then return end -- don't rebuild a hidden panel
	clearBody()
	-- CRATES is the page this panel exists for; TOKENS is its shop and TRADE UP is an action on the skins you
	-- already own, opened from the Pet Hub. A hub page id can never reach here (the click handler hands those
	-- off before touching activeTab).
	--
	-- MY SKINS and the COLLECTION BOOK used to be two more pages here and are gone on purpose. Every skin you
	-- own is already on the pet it belongs to, reached by tapping that pet -- a second, flat list of the same
	-- skins was a second place to look for one thing, and the collection book was a third.
	if activeTab == "tradeup" then buildTradeUpTab()
	elseif activeTab == "tokens" then buildTokensTab()
	else buildCratesTab() end
end

for id, b in pairs(tabButtons) do
	b.MouseButton1Click:Connect(function()
		playUIClick()
		-- PETS / TRADE / QUESTS belong to the Pet Hub: close this panel and open it on that page. Firing
		-- PetInvToggle alone would only re-open the hub on whatever page it was last left on.
		local hubPage = TAB_TO_HUB[id]
		if hubPage then
			setOpen(false)
			local ev = PlayerGui:FindFirstChild("PetInvToggle")
			if ev and ev:IsA("BindableEvent") then ev:Fire() end
			-- one frame for the hub to build/open before routing it
			task.defer(function() if _G.PetHub and _G.PetHub.showPage then _G.PetHub.showPage(hubPage) end end)
		return
		end
		activeTab = id; refreshTabs()
	end)
end

-- ============================================================================================================
-- THE CS:GO REEL
-- ============================================================================================================
-- Geometry: cells of CELL_W scroll right-to-left behind a fixed centre marker. We build a strip long enough that
-- the eye never sees the ends, place the WINNING item at WIN_INDEX, and tween the strip so that cell lands dead
-- centre. Because the stop position is computed FROM the server's result, the reel physically cannot end on
-- anything else.
-- THE CAROUSEL IS THE INTERFACE. It takes 408 of the panel's 520px (78% of the whole panel, 82% of what
-- is left after margins), and the cards scale WITH it -- 224x344 instead of 108x156. At that width ~3
-- cells span the 676px window, which is exactly the Pet-Simulator read: one big centred pet with its
-- neighbours half-visible either side.
local CELL_W, CELL_H = 228, 348
local WINDOW_Y   = 34
local WINDOW_H   = 474           -- 91% of the 520-tall panel: the carousel IS the interface now
local MARKER_Y   = 26
local MARKER_H   = WINDOW_H + 16 -- overhangs top and bottom so the selector reads as a fixed rail
local EDGE_FADE  = 110           -- soft cut-off at each end, scaled up with the window
-- THERE IS NO INFO PANEL. The reward reads off the winning CARD -- already centred under the marker, already
-- showing the pet, its skin and its name -- so a second blue box restating it was pure duplication. What is
-- left of the reveal (rarity, trait, note, CLAIM) floats over the lower strip of the carousel with no
-- container of its own, so the cards keep the full height.
--
-- CARD_TOP: cards are TOP-anchored in the window rather than centred, which reserves REVEAL_BAND at the
-- bottom for that floating text without shrinking the window.
local CARD_TOP    = 8
local REVEAL_Y    = WINDOW_Y + CARD_TOP + CELL_H + 10  -- first line of floating reveal text
local REVEAL_BAND = (WINDOW_Y + WINDOW_H) - REVEAL_Y   -- what is left under the cards
local WIN_CELL_NAME = "WinningCell" -- lets the payoff find the landed card without repeating index maths
local STRIP_LEN  = 56 -- cells built
local WIN_INDEX  = 48 -- which cell holds the winner (leaves 8 cells of runout so the stop isn't at the very end)

-- ONE CONTINUOUS DECELERATION -- position = start + distance * (1 - (1-t)^SPIN_EASE), stepped every frame.
--
-- This replaced a three-stage version (fast tween -> linear crawl -> settle tween) that had a visible hitch:
-- an ease-out finishes at near-zero speed, so when the linear crawl took over at a CONSTANT speed the reel
-- appeared to stop and then set off again. Chaining tweens can't avoid that -- the velocity at a stage boundary
-- is whatever each curve happens to end and begin at, and those don't match. Driving one curve by hand means
-- speed falls monotonically from full to zero with nothing to bump against.
--
-- SPIN_EASE is the whole feel, and it's a real trade-off:
--   5+ (Quint/Expo)  the reel is within ~20px of the answer with 2s still to run -- the last third is motionless
--                    and it reads as "it already landed, now it's just waiting".
--   3.2             ~1.5 cells still to travel at that same point, so those seconds are spent visibly creeping
--                    past a near-miss and easing down to nothing. This is the number to tune.
--   2 or lower      still moving quickly at the end, so it snaps to a halt instead of settling.
local SPIN_TIME = 6.0
local SPIN_EASE = 3.2
-- Authored reel geometry. The landing maths uses these LOCAL units rather than AbsoluteSize so the stop stays
-- centred under any UIScale -- see the comment in openReveal.
-- The reveal uses the SAME footprint as the crate panel it opened from (700x520 at 0.5,-45), so the two
-- never jump size or position when one replaces the other. REEL_WINDOW_INSET is unchanged -- the landing
-- maths in openReveal derives the window width from these two constants.
local REEL_PANEL_W      = 700
local REEL_PANEL_H      = 520
local REEL_WINDOW_INSET = 24

local revealGui = Instance.new("ScreenGui")
revealGui.Name = "SkinCrateRevealGui"; revealGui.ResetOnSpawn = false; revealGui.Enabled = false
revealGui.DisplayOrder = 200 -- above EVERY menu panel: shop/hub (100), codes/group (130), banner (140), wormhole (160)
revealGui.IgnoreGuiInset = true
revealGui.Parent = PlayerGui

-- click-catcher only, no dim: the reveal panel draws with no darkening of the world behind it
local dim = mkFrame(revealGui, {
	Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Active = true,
})

local reelPanel = mkFrame(revealGui, {
	Size = UDim2.new(0, REEL_PANEL_W, 0, REEL_PANEL_H), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL, ClipsDescendants = true,
})
mkCorner(reelPanel, 18); mkStroke(reelPanel, PANEL_DARK, 4)

local reelTitle = mkLabel(reelPanel, {
	Text = "OPENING...", Font = Enum.Font.FredokaOne, TextSize = 22, TextScaled = true, TextColor3 = GOLD,
	Size = UDim2.new(1, -24, 0, 22), Position = UDim2.new(0, 12, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Center,
})
mkStroke(reelTitle, Color3.new(0, 0, 0), 2)

-- the window the strip scrolls through
local reelWindow = mkFrame(reelPanel, {
	Size = UDim2.new(1, -REEL_WINDOW_INSET, 0, WINDOW_H), Position = UDim2.new(0, REEL_WINDOW_INSET / 2, 0, WINDOW_Y),
	BackgroundColor3 = HEADER, ClipsDescendants = true,
})
mkCorner(reelWindow, 12); mkStroke(reelWindow, PANEL_DARK, 2)

local strip = mkFrame(reelWindow, { Size = UDim2.new(0, STRIP_LEN * CELL_W, 1, 0), BackgroundTransparency = 1 })

-- EDGE FADE -- cards dissolve into the panel at each end instead of being sliced off mid-cell. Two gradient
-- overlays in the window's own colour rather than a CanvasGroup: a CanvasGroup would fade the real thing,
-- but ViewportFrames (every pet thumbnail) are unreliable inside one, so this stays overlay-based.
for _, side in ipairs({ -1, 1 }) do
	local fade = mkFrame(reelWindow, {
		Size = UDim2.new(0, EDGE_FADE, 1, 0),
		Position = (side < 0) and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -EDGE_FADE, 0, 0),
		BackgroundColor3 = HEADER, ZIndex = 20,
	})
	local fg = Instance.new("UIGradient"); fg.Parent = fade
	-- opaque at the outer edge, clear by the inner edge
	fg.Transparency = (side < 0)
		and NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		or NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
end

-- centre marker: a gold line with arrows above and below, so the landing point is unmistakable
local marker = mkFrame(reelPanel, {
	Size = UDim2.new(0, 5, 0, MARKER_H), Position = UDim2.new(0.5, 0, 0, MARKER_Y), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = GOLD, ZIndex = 6,
})
mkCorner(marker, 2)
local markerArrow = mkLabel(reelPanel, {
	Text = "\xE2\x96\xBC", Font = Enum.Font.GothamBold, TextSize = 20, TextScaled = true, TextColor3 = GOLD,
	Size = UDim2.new(0, 30, 0, 24), Position = UDim2.new(0.5, 0, 0, WINDOW_Y + 6), AnchorPoint = Vector2.new(0.5, 0),
	-- inside the window and above the edge fades (ZIndex 20), pointing down at the centre cell
	ZIndex = 22, TextXAlignment = Enum.TextXAlignment.Center,
})

-- ============================================================================================================
-- REVEAL CELEBRATION (contained)
-- ============================================================================================================
-- Everything here is parented to reelPanel, which has ClipsDescendants = true -- so the effect physically
-- CANNOT leave the crate-opening UI. The previous version flashed a full-screen sheet parented to revealGui,
-- which washed the whole game out for the better part of a second and had nothing to do with the panel you
-- were actually looking at.
--
-- Scaled by tier, so the effect tells you how good the pull was before you've read anything:
--   Rare 6 sparks -> Uncommon/Common nothing -> Gold 30 sparks + a gold wash across the panel.
local BURST = {
	Rare      = { sparks =  6 },
	Epic      = { sparks = 12 },
	Legendary = { sparks = 20, wash = 0.55 },
	Gold      = { sparks = 30, wash = 0.25, ring = true },
}

-- The reel half of the panel. A trade-up has no strip to scroll, so it hides these and keeps the SAME
-- 700x520 frame -- the old code shrank the panel to 90px, which would now clip the result card away.
local function setReelVisible(on)
	reelWindow.Visible = on
	marker.Visible = on
	markerArrow.Visible = on
end

local function celebrate(tier)
	local cfg = BURST[tier]
	if not cfg or not reelPanel.Visible then return end
	local col = PetSkins.tierColor(tier)

	-- (1) WASH -- a tint over the PANEL only, gone in well under a second.
	if cfg.wash then
		local wash = mkFrame(reelPanel, {
			Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = col,
			BackgroundTransparency = cfg.wash, ZIndex = 40,
		})
		TweenService:Create(wash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
		Debris:AddItem(wash, 0.8)
	end

	-- (2) SHOCK RING -- one expanding circle from the marker. Top tier only; it's the loudest thing here.
	if cfg.ring then
		local ring = mkFrame(reelPanel, {
			Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 41,
		})
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
		local rs = Instance.new("UIStroke"); rs.Color = col; rs.Thickness = 5; rs.Parent = ring
		TweenService:Create(ring, TweenInfo.new(0.75, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(640, 640) }):Play()
		TweenService:Create(rs, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1, Thickness = 0.5 }):Play()
		Debris:AddItem(ring, 0.9)
	end

	-- (3) SPARKS -- thrown out from the marker, arcing and fading. Spawned from the CENTRE (where the winning
	-- cell just landed) so the eye is already there.
	for i = 1, cfg.sparks do
		local spark = mkLabel(reelPanel, {
			Text = "\xE2\x9C\xA6", Font = Enum.Font.GothamBold, TextColor3 = col,
			TextSize = math.random(11, 22), TextScaled = true,
			Size = UDim2.fromOffset(math.random(11, 22), math.random(11, 22)),
			AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 42,
			Rotation = math.random(0, 359),
		})
		local ox, oy = math.random(-34, 34), math.random(-14, 14)
		spark.Position = UDim2.new(0.5, ox, 0.5, oy)
		-- Elliptical spread: wider than tall, because the panel is wider than it is tall. A circular spread
		-- would bunch everything against the top and bottom edges and get clipped away immediately.
		local ang = math.rad(math.random(0, 359))
		local reach = math.random(70, 300)
		local dx = math.cos(ang) * reach
		local dy = math.sin(ang) * reach * 0.42
		local dur = 0.55 + math.random() * 0.55
		TweenService:Create(spark, TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, ox + dx, 0.5, oy + dy),
			TextTransparency = 1,
			Rotation = spark.Rotation + math.random(-200, 200),
		}):Play()
		Debris:AddItem(spark, dur + 0.15)
	end
end

-- result card, shown after the reel stops
-- The reveal layer: NOT a panel. An invisible group holding the floating text and the CLAIM button over the
-- bottom strip of the carousel. Grouping them keeps ONE Visible flag driving the whole reveal, exactly as the
-- old card did, without putting a box back on screen.
-- ZIndex 50 keeps it above the celebration layers (wash 40, ring 41, sparks 42) -- those are brief, but that
-- brief moment is precisely when CLAIM gets pressed.
local resultCard = mkFrame(reelPanel, {
	Size = UDim2.new(0, 676, 0, REVEAL_BAND), Position = UDim2.new(0.5, 0, 0, REVEAL_Y),
	AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 50,
})
-- THE PAYOFF PICTURE: the pet you actually won, wearing the skin you actually won. Sits on the left with the
-- text to its right, so the card keeps its 460x190 footprint and nothing else in the reveal has to move.
-- A TRADE-UP has no reel to scroll, so nothing else would show the item. This holder sits in the middle of
-- the (hidden) carousel for that case only; on a crate open the winning CARD is the picture, so it stays off.
local resultPetHolder = mkFrame(reelPanel, {
	Size = UDim2.new(0, 260, 0, 260), Position = UDim2.new(0.5, 0, 0, WINDOW_Y + 40),
	AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 30,
})
-- Rebuilt per reveal -- the pet and skin change every open. static=false: this is the ONE model that earns
-- the full look (particles, light, and its trait).
local function showResultPet(petId, skinId, traitId)
	for _, ch in ipairs(resultPetHolder:GetChildren()) do ch:Destroy() end
	resultPetHolder.Visible = true
	makePetPreview(resultPetHolder, petId, skinId, traitId, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), false)
end
local resultName = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.FredokaOne, TextSize = 30, TextScaled = true, TextColor3 = WHITE,
	-- The text block is centred in the 462px LEFT of the button, not across the whole band -- centring it
	-- across the full width would read as off-centre, because the button occupies only the right side.
	Size = UDim2.new(0, 462, 0, 38), Position = UDim2.new(0, 8, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
mkStroke(resultName, Color3.new(0, 0, 0), 2)
-- TextScaled shrinks a long name to fit instead of clipping it; the constraint stops a SHORT name from
-- ballooning to fill 40px of height and swamping the lines beneath it.
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 30; c.Parent = resultName end
local resultTier = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true, TextColor3 = GOLD,
	Size = UDim2.new(0, 462, 0, 20), Position = UDim2.new(0, 8, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
local resultTrait = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.GothamBold, TextSize = 15, TextScaled = true, TextColor3 = WHITE,
	Size = UDim2.new(0, 462, 0, 18), Position = UDim2.new(0, 8, 0, 62),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
local resultNote = mkLabel(resultCard, {
	Text = "", Font = Enum.Font.Gotham, TextSize = 13, TextScaled = true, TextColor3 = Color3.fromRGB(205, 224, 255),
	Size = UDim2.new(0, 462, 0, 20), Position = UDim2.new(0, 8, 0, 82),
	TextXAlignment = Enum.TextXAlignment.Center, TextXAlignment = Enum.TextXAlignment.Center,
})
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 18; c.Parent = resultTier end
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 16; c.Parent = resultTrait end
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = resultNote end
local resultBtn = mkButton(resultCard, {
	Size = UDim2.new(0, 190, 0, 60), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
	BackgroundColor3 = LIME, Text = "NICE!", Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true, TextColor3 = WHITE,
})
mkCorner(resultBtn, 12); mkStroke(resultBtn, LIME_DARK, 2)

-- SKIP -- jump straight to the reward. The reel is ~6s and you will open a lot of these; forcing the full
-- animation every time turns a good moment into a chore. It only ever snaps the strip to the position the
-- server already chose, so skipping cannot change (or reveal early) anything the roll didn't already decide.
local skipBtn = mkButton(reelPanel, {
	Size = UDim2.new(0, 160, 0, 40), Position = UDim2.new(0.5, 0, 0, REVEAL_Y + 20), AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = CARD, Text = "SKIP \xE2\x9D\xAF\xE2\x9D\xAF", Font = Enum.Font.FredokaOne,
	TextSize = 16, TextScaled = true, TextColor3 = WHITE, Visible = false, ZIndex = 8,
})
mkCorner(skipBtn, 10); mkStroke(skipBtn, WHITE, 1.5)
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 16; c.Parent = skipBtn end

-- Build one reel cell. Cells are plain coloured tiles with the skin name, the pet name and a rarity stripe --
-- readable at speed, which matters more here than detail nobody can see while it's moving.
local function buildCell(parent, x, item)
	local tierCol = PetSkins.tierColor(item.rarity)
	local cell = mkFrame(parent, {
		-- TOP-anchored vertically so the band underneath stays free for the floating reveal text; CENTRE-
		-- anchored horizontally so the focus scaling below grows and shrinks the card about its own middle
		-- instead of dragging it sideways off the marker.
		Size = UDim2.new(0, CELL_W - 8, 0, CELL_H),
		Position = UDim2.new(0, x + math.floor(CELL_W / 2), 0, CARD_TOP),
		AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = CARD,
	})
	mkCorner(cell, 14); mkStroke(cell, tierCol, 3)
	-- Driven per frame by the focus pass in openReveal. A UIScale rather than a Size tween because it
	-- scales the card's CONTENTS too -- the pet, the band, the captions all shrink together.
	do local sc = Instance.new("UIScale"); sc.Name = "Focus"; sc.Scale = 1; sc.Parent = cell end
	-- rarity band across the top
	local band = mkFrame(cell, { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = tierCol })
	mkCorner(band, 7)
	local skin = PetSkins.get(item.skin)
	-- a big colour swatch standing in for the skin, tinted with the skin's own colour
	-- THE TOP TIER IS MASKED IN THE REEL. A Gold cell shows a prize rosette and nothing else -- no pet, no
	-- skin name -- so scrolling past one tells you a jackpot is IN this crate without spoiling which one you
	-- are about to win. That reveal belongs to the result card, and giving it away here would throw away the
	-- best moment the system has. It is the same reason CS:GO never shows the knife in the reel.
	--
	-- This is presentation only. The server has ALREADY chosen the reward, the reel still lands on that exact
	-- cell, and the odds panel still publishes every item in the crate -- so nothing here hides information
	-- the player is owed.
	local isTop = (item.rarity == SkinCrates.GOLD_TIER)

	-- A PET LEVEL CRATE cell. There is no pet and no skin to draw -- the reward IS the number -- so the cell
	-- shows it at the size the pet preview would have taken. The top tier keeps its struck-medal treatment but
	-- does NOT hide the number: masking exists to protect WHICH pet/skin you are about to win, and a level crate
	-- has no such secret. Hiding '+10' would only make the best pull in the crate unreadable.
	if item.levels then
		local plate = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = isTop and Color3.fromRGB(46, 34, 8) or Color3.fromRGB(18, 34, 66),
		})
		mkCorner(plate, 12); mkStroke(plate, tierCol, 3)
		local disc = mkFrame(plate, {
			Size = UDim2.fromOffset(132, 132), Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = tierCol,
		})
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = disc end
		mkStroke(disc, Color3.fromRGB(12, 24, 48), 2)
		do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Parent = disc
			g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), tierCol) end
		mkLabel(disc, {
			Text = "+" .. item.levels, Font = Enum.Font.FredokaOne, TextSize = 56, TextScaled = true,
			TextColor3 = Color3.fromRGB(18, 34, 66), Size = UDim2.new(1, -22, 1, -22),
			Position = UDim2.new(0, 11, 0, 11),
		})
		mkLabel(cell, {
			Text = item.levels == 1 and "1 Pet Level" or (item.levels .. " Pet Levels"),
			Font = Enum.Font.FredokaOne, TextSize = 15, TextScaled = true, TextColor3 = isTop and GOLD or WHITE,
			Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 250),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		mkLabel(cell, {
			Text = "PET LEVELS", Font = Enum.Font.Gotham, TextSize = 20, TextScaled = true,
			TextColor3 = Color3.fromRGB(205, 224, 255), Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.new(0, 8, 0, 292), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		})
		applyRarityFlair(cell, item.rarity, true)
		return cell
	end

	-- A TRAIT CRATE cell shows THE GOODS the same way a skin cell does: a real 3D pet actually WEARING the
	-- trait (accessories and all), against a backdrop tinted the trait's own colour. Every cell uses the
	-- same DEMO MODEL -- a Classic Butter Duck -- because the actual ride-along pet+skin is rolled at open
	-- time and cannot be known while the reel spins; the payoff flips the winning card to the real grant.
	-- Not masked at Gold: the crate holds exactly one trait per band, so there is no which-item secret.
	if item.trait then
		local swatch = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = PetTraits.color(item.trait) or tierCol, BackgroundTransparency = 0.35,
		})
		mkCorner(swatch, 12); mkStroke(swatch, Color3.new(0, 0, 0), 1)
		makePetPreview(cell, TRAIT_DEMO_PET, "Classic", item.trait,
			UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
		local traitLbl = mkLabel(cell, {
			Text = PetTraits.displayName(item.trait), Font = Enum.Font.FredokaOne, TextSize = 15, TextScaled = true,
			TextColor3 = PetTraits.color(item.trait) or (isTop and GOLD or WHITE),
			Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 250),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		traitLbl.Name = "SkinName" -- same caption names as a skin cell, so the payoff can rewrite them in place
		local subLbl2 = mkLabel(cell, {
			Text = "TRAIT", Font = Enum.Font.Gotham, TextSize = 20, TextScaled = true,
			TextColor3 = Color3.fromRGB(205, 224, 255), Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.new(0, 8, 0, 292), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		})
		subLbl2.Name = "PetName"
		applyRarityFlair(cell, item.rarity, true)
		return cell
	end

	if isTop then
		local plate = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = Color3.fromRGB(46, 34, 8),
		})
		plate.Name = "MysteryPlate" -- the payoff finds it by name to tear the mask off (see unmaskWinner)
		mkCorner(plate, 12); mkStroke(plate, tierCol, 3)
		-- one big struck medal, centred, filling the space the pet would have used
		local medal = mkFrame(plate, {
			Size = UDim2.fromOffset(112, 112), Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = tierCol,
		})
		do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = medal end
		mkStroke(medal, Color3.fromRGB(92, 58, 8), 2)
		do local g = Instance.new("UIGradient"); g.Rotation = 90; g.Parent = medal
			g.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), tierCol) end
		mkLabel(medal, {
			Text = "\xE2\x98\x85", Font = Enum.Font.FredokaOne, TextSize = 52, TextScaled = true,
			TextColor3 = Color3.fromRGB(92, 58, 8), Size = UDim2.new(1, -16, 1, -16),
			Position = UDim2.new(0, 8, 0, 8),
		})
	else
		-- Every other tier shows the goods. The skin-coloured panel stays as a BACKDROP: it reads the tier
		-- colour even while the reel is a blur, and gives the 3D pet something to sit against.
		local swatch = mkFrame(cell, {
			Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
			BackgroundColor3 = (skin and skin.color) or Color3.fromRGB(120, 130, 145),
		})
		mkCorner(swatch, 12); mkStroke(swatch, Color3.new(0, 0, 0), 1)
		-- THE ACTUAL ITEM: this pet, wearing this skin.
		makePetPreview(cell, item.pet, item.skin, nil, UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
	end
	-- Both captions are NAMED so the payoff can rewrite them in place when a masked Gold card lands.
	local skinLbl = mkLabel(cell, {
		-- masked for the top tier: printing 'Cosmic' here would undo everything the rosette just did
		-- A PET CRATE cell has no skin, so the old `(skin and skin.displayName) or item.skin` resolved to nil --
		-- and assigning nil to .Text is a hard error in Roblox, which would have killed the reel build mid-strip.
		-- The species name is the right label there anyway: on that crate the PET is the prize and the cell's
		-- tier colour already carries the rarity.
		Text = isTop and "???" or ((skin and skin.displayName) or item.skin or PetSkins.prettyPet(item.pet)),
		Font = Enum.Font.FredokaOne, TextSize = 15,
		TextScaled = true, TextColor3 = isTop and GOLD or WHITE, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 250),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	skinLbl.Name = "SkinName"
	local petLbl = mkLabel(cell, {
		Text = isTop and "MYSTERY PRIZE" or PetSkins.prettyPet(item.pet), Font = Enum.Font.Gotham, TextSize = 20, TextScaled = true,
		TextColor3 = Color3.fromRGB(205, 224, 255), Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.new(0, 8, 0, 292), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
	})
	petLbl.Name = "PetName"
	-- lite=true: pulse + shimmer only. A Rare+ cell flashing past the marker is what builds the "wait, was that
	-- a good one?" tension during the slowdown -- sparkles/glow would just be noise at reel speed.
	applyRarityFlair(cell, item.rarity, true)
	return cell
end

-- UNMASK THE JACKPOT. A Gold cell rides the reel as a rosette so scrolling past one never gives away which
-- item is in the crate -- that reveal is the best moment the system has, and spending it on a blurred cell
-- mid-spin wastes it. But once the reel has STOPPED on it the secret has done its job, and leaving the card
-- as a rosette means the one thing the player actually wants to look at is the only card not showing its
-- prize. So the mask comes off and the card becomes what every other winning card already is: this pet, in
-- this skin, wearing this trait.
--
-- Self-guarding: no MysteryPlate means the cell was never masked (every tier below Gold, and every cell in a
-- level crate, which has no pet to hide), so this is a no-op and safe to call on any winner.
local function unmaskWinner(cell, petId, skinId, traitId)
	local plate = cell:FindFirstChild("MysteryPlate")
	if not (plate and petId and skinId) then return false end
	plate:Destroy()
	local skin = PetSkins.get(skinId)
	-- same backdrop + preview pair the unmasked tiers build, so the flipped card is indistinguishable from
	-- one that was never masked -- no second code path to keep in step.
	local swatch = mkFrame(cell, {
		Size = UDim2.new(1, -24, 0, 222), Position = UDim2.new(0, 12, 0, 20),
		BackgroundColor3 = (skin and skin.color) or Color3.fromRGB(120, 130, 145),
	})
	mkCorner(swatch, 12); mkStroke(swatch, Color3.new(0, 0, 0), 1)
	-- the real trait too, not nil: the reel passes nil while scrolling, but the winner should show what was
	-- actually granted, which is what the result card underneath is about to name.
	makePetPreview(cell, petId, skinId, traitId, UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
	local sn = cell:FindFirstChild("SkinName")
	if sn then sn.Text = (skin and skin.displayName) or skinId end
	-- the trait is half the prize, so the card says it out loud in the trait's own colour instead of leaving
	-- it to the small print on the result band below
	local pn = cell:FindFirstChild("PetName")
	if pn then
		if traitId and not PetTraits.isNone(traitId) then
			pn.Text = PetSkins.prettyPet(petId) .. "  \xE2\x80\xA2  " .. PetTraits.displayName(traitId) .. " Trait"
			pn.TextColor3 = PetTraits.color(traitId) or pn.TextColor3
		else
			pn.Text = PetSkins.prettyPet(petId)
		end
	end
	return true
end

local spinning = false
-- Separate flag from `spinning`: `spinning` is cleared at the PAYOFF, `building` the moment the strip has
-- finished being built. Two flags because the dangerous window is the BUILD -- a second entrant partway
-- through would leave the first pass's cells, and their queued previews, alive alongside the new ones.
local building = false
-- Guards the SETTLE step specifically. The spin can end two ways -- the drive loop reaching t >= 1, or SKIP
-- snapping it early -- and both fall through to the same payoff. One flag, set the instant the strip stops,
-- means the win visuals apply exactly once per spin no matter which path got there.
local settled = false

-- THE REVEAL. `result` is the server's already-granted payload; `crate` is the crate it came from.
local function openReveal(crate, result)
	-- BUILD DEBOUNCE. openReveal destroys and rebuilds all STRIP_LEN cells; a second entrant partway
	-- through would leave the first pass's cells (and their queued previews) alive alongside the new
	-- ones. `spinning` already gated this, but it was cleared on the payoff rather than at the end of
	-- the build, leaving a window where a fast second click could re-enter.
	if spinning or building then return end
	spinning = true
	building = true
	settled = false -- new spin: the settle step has not run yet

	-- rebuild the strip
	for _, ch in ipairs(strip:GetChildren()) do ch:Destroy() end
	resultCard.Visible = false
	resultPetHolder.Visible = false -- the winning CARD is the picture on a crate open
	-- Undo the title-only layout a trade-up reveal leaves behind (it shares this GUI).
	setReelVisible(true)
	reelTitle.Text = "OPENING " .. string.upper(crate.displayName)
	reelTitle.TextColor3 = GOLD

	local pool = SkinCrates.flatContents(crate.id)
	if #pool == 0 then spinning = false; return end
	local winner = pool[result.reelIndex] or { pet = result.pet, skin = result.skin, rarity = result.rarity }

	-- Fill every cell with a random item from the crate EXCEPT the winning slot, which gets the server's item.
	-- The filler is cosmetic only -- it exists to give the eye something to read while the reel decelerates.
	-- NO TWO IDENTICAL CARDS ON SCREEN AT ONCE. Only ~3 cells are visible at this card size, so a plain
	-- random fill showed the same skin twice side by side often enough to look broken -- and it makes the
	-- reel read as a short loop rather than a deep crate.
	--
	-- Deduped on the PET, not on pet+skin. A card is dominated by its 3D pet model, so a Stone Bean Buddy
	-- beside an Emerald Bean Buddy reads as the same card printed twice even though they are different
	-- rewards -- which is exactly what looked broken. Two cards may share a SKIN; they may not share a PET.
	--
	-- `recent` holds the last visible-window's worth of picks plus a margin, so a pet can't reappear the
	-- moment its twin slides out of frame. A colliding pick is re-rolled up to 24 times, then accepted: if a
	-- crate has fewer distinct pets than fit on screen, repeats are unavoidable and a bounded loop is the
	-- only honest answer -- an unbounded one would hang forever on a two-pet crate.
	local windowCells = math.ceil((REEL_PANEL_W - REEL_WINDOW_INSET) / CELL_W) + 2
	local recent = {}
	local cells = {} -- by strip index, for the per-frame focus pass
	-- Identity for the no-two-alike pass. A level crate has no pet, so keying on e.pet alone would make every
	-- cell look identical, empty the eligible set, and drop the reel back to a blind random pick.
	local function keyOf(e)
		if e.levels then return "lvl" .. tostring(e.levels) end
		if e.trait  then return "trt" .. tostring(e.trait)  end
		return tostring(e.pet)
	end
	local function remember(e)
		recent[#recent + 1] = keyOf(e)
		if #recent > windowCells then table.remove(recent, 1) end
	end
	for i = 1, STRIP_LEN do
		local item
		if i == WIN_INDEX then
			item = winner -- never re-rolled: this is the cell the server's roll has to land on
		else
			-- The winner is FORCED, so the cells landing just BEFORE it cannot discover it through `recent` the
			-- way later cells do -- and those are exactly the cells sharing the screen with it when the reel
			-- stops. That hole is what kept the winning pet appearing twice at the payoff moment. Look ahead
			-- instead: inside the run-up, treat the winner's pet as already taken.
			local nearWinner = (i < WIN_INDEX) and (WIN_INDEX - i <= windowCells)
			-- Gather what IS allowed and pick from that, rather than re-rolling and hoping. Blind retries have a
			-- failure tail that scales with how few pets a crate has -- the Mythic pool (8 pets) still doubled on
			-- ~5% of reels at 24 attempts. Building the set costs #pool * windowCells checks per cell (about six
			-- thousand for a whole strip -- nothing) and CANNOT fail while any legal choice exists.
			local eligible = {}
			for _, e in ipairs(pool) do
				local k = keyOf(e)
				local ok = not (nearWinner and k == keyOf(winner))
				if ok then
					for _, r in ipairs(recent) do if r == k then ok = false; break end end
				end
				if ok then eligible[#eligible + 1] = e end
			end
			-- Empty only when the crate has fewer distinct pets than fit on screen, where a repeat is unavoidable.
			item = (#eligible > 0) and eligible[math.random(1, #eligible)] or pool[math.random(1, #pool)]
		end
		remember(item)
		local built = buildCell(strip, (i - 1) * CELL_W, item)
		cells[i] = built
		if i == WIN_INDEX then built.Name = WIN_CELL_NAME end
	end

	building = false -- every cell exists now; re-entry is safe again
	-- Hide the crate panel underneath. Its ScreenGui uses CoreUISafeInsets while this one ignores the inset,
	-- so the two 700x520 panels don't share a footprint on screen -- the crate list's bottom row was poking
	-- out below the reveal. The CLAIM button brings it back.
	gui.Enabled = false
	revealGui.Enabled = true

	-- Where the strip must end up: the winning cell's centre sits under the window's centre.
	--
	-- windowW is the window's LOCAL width, derived from the authored geometry (reelPanel 700 wide, reelWindow
	-- inset 24) -- deliberately NOT reelWindow.AbsoluteSize.X. AbsoluteSize is in post-UIScale screen pixels,
	-- while strip.Position offsets are pre-scale local units, so mixing them would land the reel off-centre on
	-- any device where the HUD scaling pass has applied a UIScale (i.e. every phone and iPad).
	local windowW = REEL_PANEL_W - REEL_WINDOW_INSET
	local targetX = -((WIN_INDEX - 1) * CELL_W + CELL_W / 2) + windowW / 2
	-- a few pixels of jitter so repeat pulls don't stop pixel-identically
	targetX = targetX + math.random(-14, 14)

	strip.Position = UDim2.new(0, windowW, 0, 0) -- start off to the right, so the first cells fly in
	local startX = windowW
	local dist   = targetX - startX -- negative: the strip travels leftward

	-- TICKS: watch which cell is under the marker and click whenever it changes. Because the strip decelerates,
	-- the ticks naturally slow with it -- that audible ramp is most of what makes a case opening feel tense.
	-- PITCH TRACKS SPEED. A flat tick made every part of the spin sound the same; sliding the pitch down as
	-- the reel slows means you HEAR the deceleration, which is most of the tension. Measured from the
	-- strip's actual per-frame travel rather than from the curve, so it stays honest if SPIN_EASE changes.
	local lastCell, lastX = nil, strip.Position.X.Offset
	local tickConn = RunService.RenderStepped:Connect(function()
		local x = strip.Position.X.Offset
		local travel = math.abs(x - lastX)
		lastX = x
		local centreIdx = math.floor((-x + windowW / 2) / CELL_W) + 1
		if centreIdx ~= lastCell then
			lastCell = centreIdx
			-- a whole cell of travel in ONE frame is flat out; the last few ticks crawl in near zero
			local v = math.clamp(travel / CELL_W, 0, 1)
			playSound(TICK_SOUND, 0.20 + v * 0.12, 1.02 + v * 0.68)
			-- ONE TAP PER CELL. The reel already slows into the stop, so the taps space out with it -- the
			-- payoff is felt building, not just watched. Haptics throttles `tick`, so the fast opening blur
			-- cannot turn into a solid hum.
			if _G.hapticPulse then pcall(_G.hapticPulse, "tick") end
		end
	end)

	-- CENTRE FOCUS. Cards shrink with distance from the marker, so the one under it is always visibly the
	-- subject and its neighbours read as context. Without this, three identically sized cards give the eye
	-- nothing to lock onto until the reel has already stopped.
	--
	-- Neighbours SHRINK rather than the centre growing: at scale 1 a card is exactly its authored size, so
	-- nothing can ever overflow the window or collide with the reveal band below.
	--
	-- Only the ~5 cells that can be on screen are touched, found by arithmetic rather than by walking all
	-- STRIP_LEN of them -- this runs every frame of the spin.
	local FOCUS_MIN = 0.80

	-- ---- OFFSCREEN VIEWPORTS ARE PARKED --------------------------------------------------------------
	-- A ViewportFrame renders its 3D contents every frame whenever it is Visible. Being scrolled outside a
	-- ClipsDescendants parent does NOT stop that -- the cost is paid for all STRIP_LEN cells even though only
	-- about five can be seen. With 56 cells of 11-53 parts each that is the whole reel re-rendered every
	-- frame, and it is what makes the spin stutter.
	--
	-- So each frame only the cells in the focus window stay live; the rest have their ViewportFrame hidden.
	-- Visible=false is the cheap switch here: it stops the render but keeps the model, so a cell coming back
	-- into view costs nothing to restore -- no rebuild, no re-queue, no flicker.
	--
	-- Toggling is done on the DELTA (cells entering/leaving the window), not by sweeping all 56 -- this runs
	-- every frame of a 6-second spin.
	local vpCache = {}   -- [index] = the cell's ViewportFrame, resolved once
	local liveFirst, liveLast = nil, nil
	local function viewportOf(i)
		local hit = vpCache[i]
		if hit ~= nil then return hit or nil end
		local c = cells[i]
		local vp = c and c:FindFirstChildWhichIsA("ViewportFrame", true)
		vpCache[i] = vp or false -- cache the miss too: a level cell has no viewport at all
		return vp
	end
	local function setLive(i, live)
		local vp = viewportOf(i)
		if vp then vp.Visible = live end
	end

	local function applyFocus()
		local x = strip.Position.X.Offset
		local centre = -x + windowW / 2 -- strip-space X currently under the marker
		local first = math.max(1, math.floor((centre - windowW / 2) / CELL_W))
		local last  = math.min(STRIP_LEN, math.ceil((centre + windowW / 2) / CELL_W) + 1)

		if first ~= liveFirst or last ~= liveLast then
			if liveFirst then -- retire the cells that just left the window
				for i = liveFirst, liveLast do
					if i < first or i > last then setLive(i, false) end
				end
			else              -- first pass: nothing has been shown yet, so park everything off-window
				for i = 1, STRIP_LEN do
					if i < first or i > last then setLive(i, false) end
				end
			end
			for i = first, last do setLive(i, true) end
			liveFirst, liveLast = first, last
		end

		for i = first, last do
			local c = cells[i]
			if c then
				local sc = c:FindFirstChild("Focus")
				if sc then
					-- distance from the marker, measured in CARDS: 0 dead centre, 1 a full card away
					local d = math.abs(((i - 1) * CELL_W + CELL_W / 2) - centre) / CELL_W
					local near = math.clamp(1 - d, 0, 1)
					-- eased, so the centre card holds its size through the middle of the slot instead of
					-- pulsing sharply as the boundary crosses
					sc.Scale = FOCUS_MIN + (1 - FOCUS_MIN) * (near * near * (3 - 2 * near))
				end
			end
		end
	end
	applyFocus() -- correct on the very first frame, before the reel has moved

	-- SKIP wiring: a flag the drive loop polls, so a click drops straight through to the payoff. The strip is
	-- snapped to targetX afterwards either way, so a skipped reveal and a watched one end on the exact same cell.
	local skipped = false
	skipBtn.Visible = true
	local skipConn = skipBtn.MouseButton1Click:Connect(function()
		if skipped then return end
		skipped = true
		playUIClick()
	end)

	-- THE DRIVE LOOP: one curve, stepped per frame, no tween hand-offs. Speed only ever decreases, so the reel
	-- cannot stall and re-accelerate the way the old staged version did at its boundaries.
	local markerPulse
	local t0 = os.clock()
	while not skipped do
		local t = math.clamp((os.clock() - t0) / SPIN_TIME, 0, 1)
		local travelled = 1 - (1 - t) ^ SPIN_EASE
		strip.Position = UDim2.new(0, startX + dist * travelled, 0, 0)
		applyFocus()

		-- Once the winner is within ~2 cells the marker starts breathing -- the UI signalling "this is the
		-- moment", not just the reel. Triggered off the distance remaining rather than a timestamp, so it stays
		-- in sync with the curve if SPIN_EASE is retuned.
		if not markerPulse and math.abs(dist) * (1 - travelled) <= CELL_W * 2 then
			markerPulse = TweenService:Create(marker,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundColor3 = Color3.fromRGB(255, 255, 220), Size = UDim2.new(0, 8, 0, MARKER_H + 8) })
			markerPulse:Play()
		end

		if t >= 1 then break end
		RunService.RenderStepped:Wait()
	end

	if markerPulse then
		markerPulse:Cancel()
		marker.BackgroundColor3 = GOLD; marker.Size = UDim2.new(0, 5, 0, MARKER_H) -- back to its authored look
	end

	strip.Position = UDim2.new(0, targetX, 0, 0) -- exact landing, skipped or not
	applyFocus() -- settle the scales on the final position (a SKIP jumps straight here)
	skipConn:Disconnect()
	skipBtn.Visible = false
	tickConn:Disconnect()
	-- The selector has done its job once the reel lands; left up, it painted a gold stripe straight down the
	-- winning card. setReelVisible(true) at the top of the next spin brings both back.
	marker.Visible = false
	markerArrow.Visible = false

	-- ===== the payoff =====
	if settled then return end -- a second entrant would re-apply the win visuals on top of the first
	settled = true
	local isGold = result.isGold == true
	-- THE PAYOFF. Gold gets the five-tap `rare` rhythm; every other pull gets `unlock`. Both outrank
	-- the reel's ticks, so the strip of taps stops dead and the result lands as its own thing.
	if _G.hapticPulse then pcall(_G.hapticPulse, isGold and "rare" or "unlock") end
	local tierCol = PetSkins.tierColor(result.rarity)

	if isGold then
		-- GOLD is the knife pull: its own layered sound and a gold-framed card. The celebration itself is
		-- fired below for EVERY tier, scaled to how good the pull was.
		playSound(GOLD_SOUND or REVEAL_SOUND, 0.9, GOLD_SOUND and 1 or 0.72)
		playSound(REVEAL_SOUND, 0.6, 1.25) -- layered, so it's clearly not a normal reveal
		reelTitle.Text = "\xE2\xAD\x90 GOLD \xE2\xAD\x90"
		-- (no marker pulse here any more: the selector is hidden at the payoff, and that infinite tween
		-- also used to bleed a pale-gold marker colour into the NEXT spin because nothing cancelled it)
	else
		playSound(REVEAL_SOUND, 0.7, 1)
		reelTitle.Text = string.upper(result.rarity) .. "!"
	end
	-- Highlight the card ALREADY holding the winner: a short pop and a heavier tier-coloured border. Purely
	-- visual, and it never touches the ViewportFrame's contents, so it cannot duplicate geometry.
	do
		local won = strip:FindFirstChild(WIN_CELL_NAME)
		if won then
			local st = won:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = tierCol
				TweenService:Create(st, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
					{ Thickness = isGold and 8 or 6 }):Play()
			end
			-- MAKE THE WINNER DOMINANT BY PULLING ITS NEIGHBOURS BACK, not by growing it. Cards are already at
			-- their authored size at scale 1, so any pop would push the winner's bottom edge into the reveal text
			-- (1.08 overshoots it by 17px). Receding the crowd reads stronger anyway -- the winner is left alone
			-- on the strip -- and it cannot overflow anything, because every scale involved only ever goes DOWN.
			-- Hold the rosette for a beat so "...is that the GOLD?" lands, THEN flip the card to the real prize.
			-- Delayed rather than immediate because unmasking on the same frame the reel stops reads as the card
			-- having been the pet all along, and throws away the pause the whole mask exists to create.
			-- checked BEFORE the delays fire: unmaskWinner destroys the plate, so asking again inside the
			-- skin-flip's own delay would see "not masked" and paint a second preview over the unmasked one
			local wasMasked = won:FindFirstChild("MysteryPlate") ~= nil
			task.delay(0.42, function()
				if won.Parent and unmaskWinner(won, result.pet, result.skin, result.trait) then
					playSound(REVEAL_SOUND, 0.55, 1.25)
				end
			end)
			-- SKIN pull: the reel scrolled with bare pet+skin cells (the trait belongs to the PULL, not the
			-- cell -- painting it on every cell would spoil the roll mid-spin). Once the winner is parked,
			-- flip its preview to the full prize -- skin AND trait rendered together -- and name the trait on
			-- the card, same 0.42s beat as the Gold unmask so both flips read as the same reveal.
			if not result.kind and not wasMasked and result.pet and result.skin
				and result.trait and not PetTraits.isNone(result.trait) then
				task.delay(0.42, function()
					if not won.Parent then return end
					local vp = won:FindFirstChildWhichIsA("ViewportFrame", true)
					if vp then vp:Destroy() end
					makePetPreview(won, result.pet, result.skin, result.trait,
						UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
					local pn = won:FindFirstChild("PetName")
					if pn then
						pn.Text = PetSkins.prettyPet(result.pet) .. "  \xE2\x80\xA2  "
							.. PetTraits.displayName(result.trait) .. " Trait"
						pn.TextColor3 = PetTraits.color(result.trait) or pn.TextColor3
					end
					playSound(REVEAL_SOUND, 0.45, 1.35)
				end)
			end
			-- TRAIT pull: the reel's cells all wore the trait on the demo duck; once the reel has landed,
			-- the winning card flips to the ACTUAL ride-along the server granted -- same beat, same 0.42s
			-- pause as the Gold unmask, so the flip reads as a reveal rather than a glitch.
			if result.kind == "trait" and result.pet and result.skin then
				task.delay(0.42, function()
					if not won.Parent then return end
					local vp = won:FindFirstChildWhichIsA("ViewportFrame", true)
					if vp then vp:Destroy() end
					makePetPreview(won, result.pet, result.skin, result.trait,
						UDim2.new(1, -24, 0, 222), UDim2.new(0, 12, 0, 20), true)
					local sn = won:FindFirstChild("SkinName")
					if sn then sn.Text = PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet)) end
					local pn = won:FindFirstChild("PetName")
					if pn then pn.Text = PetTraits.displayName(result.trait) .. " TRAIT" end
					playSound(REVEAL_SOUND, 0.55, 1.25)
				end)
			end
			local wonScale = won:FindFirstChild("Focus")
			if wonScale then
				TweenService:Create(wonScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = 1 }):Play() -- snap out any residual focus easing so it lands exactly full size
			end
			for _, other in ipairs(strip:GetChildren()) do
				if other ~= won then
					local osc = other:FindFirstChild("Focus")
					-- only the ones actually on screen are worth tweening
					if osc and osc.Scale > 0.01 and math.abs(other.AbsolutePosition.X - won.AbsolutePosition.X) < windowW then
						TweenService:Create(osc, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ Scale = 0.66 }):Play()
					end
				end
			end
		end
	end
	celebrate(result.rarity) -- contained inside reelPanel; see the BURST table
	reelTitle.TextColor3 = tierCol

	-- NO showResultPet HERE. The winning CARD is already parked under the marker showing this exact pet in
	-- this exact skin; rendering it again into the 260x260 holder painted a duplicate directly on top of it.
	-- That holder exists ONLY for trade-ups, which have no reel to show the item. Win visuals go on the card
	-- that is already there -- see the highlight block above.
	-- A LEVEL pull says what it gave and WHERE it went. `grants` is the server's list of which pets actually
	-- took the levels (it spills across pets so none are wasted at the cap), so the player never has to guess.
	if result.kind == "levels" then
		resultName.Text = "+" .. tostring(result.levels) .. (result.levels == 1 and " Pet Level" or " Pet Levels")
	elseif result.kind == "pets" then
		-- The PET is the prize and the band above it is its permanent rarity, so the name is just the species.
		-- Routed before the skin branch because a pet pull carries no skin at all, and displayName(nil, ...)
		-- would have rendered the reveal as a blank.
		resultName.Text = PetSkins.prettyPet(result.pet)
	elseif result.kind == "trait" then
		resultName.Text = PetTraits.displayName(result.trait) .. " Trait"
	else
		resultName.Text = PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet))
	end
	if result.skin and not result.kind then
		-- A skin pull's tier line is the OVERALL TIER -- the one label the pet will wear overhead, computed
		-- from the hidden skin+trait values. The skin's own band already spoke through the reel colour.
		local overall = result.overallTier or PetTier.overall(result.skin, result.trait) or result.rarity
		resultTier.Text = "Tier: " .. tostring(overall)
		resultTier.TextColor3 = PetSkins.tierColor(overall)
	else
		resultTier.Text = result.rarity
		resultTier.TextColor3 = tierCol
	end

	-- One clean line, always the same shape ("Trait: Smoky"), so the eye knows where to look whether or not
	-- the pull had a trait. The old SHOUTED, sparkle-wrapped version changed width on every reveal.
	if result.kind == "levels" then
		-- Nothing has been levelled YET -- these are pending until the picker places them, so this line can no
		-- longer name a pet (the server used to send `grants`; it does not decide any more).
		resultTrait.Text = "Choose which pet gets them"
		resultTrait.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "pets" then
		-- Say the quiet part out loud on the very first pull: the band you just rolled is the ONLY thing about
		-- this pet that will never change. Its size is a separate axis you grow by flying.
		resultTrait.Text = "Rarity is permanent \xE2\x80\x94 it grows from Baby as you play"
		resultTrait.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "trait" then
		-- the trait is the prize; this line names the ride-along it arrived on
		resultTrait.Text = "Comes on: " .. PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet))
		resultTrait.TextColor3 = PetTraits.color(result.trait) or Color3.fromRGB(150, 255, 170)
	elseif PetTraits.isNone(result.trait) then
		resultTrait.Text = "Trait: None"
		resultTrait.TextColor3 = Color3.fromRGB(180, 190, 205)
	else
		-- The trait NEVER joins the pet's name -- this line is where it lives, styled as the second prize it
		-- is ("Wizard Trait  \xE2\x80\xA2  Epic"), not as metadata small print.
		local tTier = PetTraits.tierOf(result.trait)
		resultTrait.Text = PetTraits.displayName(result.trait) .. " Trait"
			.. (tTier and ("  \xE2\x80\xA2  " .. tTier) or "")
		resultTrait.TextColor3 = PetTraits.color(result.trait)
	end

	if result.kind == "levels" then
		resultNote.Text = "Tap CONTINUE to pick a pet"
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "pets" then
		-- A duplicate is progress, not a miss. Naming the stack size is what teaches that, so the second
		-- Broccoli Bunny reads as "2 of 5 toward an Uncommon" instead of "I already had this".
		local n = tonumber(result.count) or 1
		resultNote.Text = (n > 1)
			and string.format("You now have x%d \xE2\x80\x94 fuse duplicates in the Pet Hub", n)
			or "Added to your pets"
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	elseif result.kind == "trait" then
		if result.locked then
			resultNote.Text = "Unlock " .. PetSkins.prettyPet(result.pet) .. " to wear it"
			resultNote.TextColor3 = Color3.fromRGB(255, 200, 120)
		else
			local ov = result.overallTier or PetTier.overall(result.skin, result.trait)
			resultNote.Text = "Ready to Equip!" .. (ov and ("   Tier: " .. tostring(ov)) or "")
			resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
		end
	elseif result.locked then
		-- prettyPet, not the raw id: "Unlock Burrito Armadillo", never "Unlock BurritoArmadillo".
		resultNote.Text = "Unlock " .. PetSkins.prettyPet(result.pet) .. " to equip this skin"
		resultNote.TextColor3 = Color3.fromRGB(255, 200, 120)
	else
		-- They own the pet, so the useful thing to say is that they can wear it RIGHT NOW. The duplicate
		-- count rides along on the same line instead of taking one of its own.
		resultNote.Text = "Ready to Equip!"
		if (result.newCount or 1) > 1 then
			resultNote.Text = "Ready to Equip!   (you own x" .. result.newCount .. ")"
		end
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	end

	resultCard.Visible = true
	resultCard.Position = UDim2.new(0.5, 0, 0, REVEAL_Y + 14)
	TweenService:Create(resultCard, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, REVEAL_Y) }):Play()

	spinning = false
end


--======================================================================
-- WHERE DO THE LEVELS GO?  (shown AFTER a Pet Level Crate opens)
--======================================================================
-- The crate reveals "+7 Pet Levels", you close it, and THIS comes up: every pet you own, with its current
-- level, and you tap the one you want fed. You are choosing with the number already on screen -- which is the
-- whole reason it moved here from the crate card, where you had to guess before opening.
--
-- IT REOPENS UNTIL THE POOL IS EMPTY. Pick a pet that caps after 3 of your 7 and the other 4 stay pending,
-- so the panel stays up for the next choice -- that is the "select the ones you want it to go to" case.
--
-- NOTHING CAN BE STRANDED. The pool is the server's and it is session-scoped: walk away, close the game, or
-- ignore this panel entirely and the server spills whatever is left across your pets on the way out (equipped
-- first, then lowest level). Skipping is a real choice, not a way to lose levels. That is what makes it safe
-- to hold levels back at all -- the old pet wheel's pending bucket had no such guarantee.
local levelPickGui = Instance.new("ScreenGui")
levelPickGui.Name = "PetLevelPickerGui"; levelPickGui.ResetOnSpawn = false
levelPickGui.DisplayOrder = 210; levelPickGui.Enabled = false; levelPickGui.Parent = PlayerGui

local lpPanel = mkFrame(levelPickGui, {
	Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = PANEL,
})
mkCorner(lpPanel, 22); mkStroke(lpPanel, WHITE, 4)

local lpHead = mkFrame(lpPanel, { Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = CARD })
mkCorner(lpHead, 22)
local lpTitle = mkLabel(lpHead, {
	Text = "WHERE DO THE LEVELS GO?", Font = Enum.Font.FredokaOne, TextSize = 28, TextScaled = true,
	TextColor3 = GOLD, Size = UDim2.new(1, -40, 1, -16), Position = UDim2.new(0, 20, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Left,
})
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 28; c.MinTextSize = 14; c.Parent = lpTitle end

local lpCount = mkLabel(lpPanel, {
	Text = "", Font = Enum.Font.FredokaOne, TextSize = 22, TextScaled = true, TextColor3 = WHITE,
	Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0, 20, 0, 74),
	TextXAlignment = Enum.TextXAlignment.Left,
})
do local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 22; c.MinTextSize = 12; c.Parent = lpCount end

local lpList = Instance.new("ScrollingFrame")
lpList.Size = UDim2.new(1, -40, 0, 340); lpList.Position = UDim2.new(0, 20, 0, 110)
lpList.BackgroundTransparency = 1; lpList.BorderSizePixel = 0; lpList.ScrollBarThickness = 6
lpList.ScrollBarImageColor3 = GOLD; lpList.CanvasSize = UDim2.new(0, 0, 0, 0); lpList.Parent = lpPanel
do
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 8); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = lpList
end

-- SKIP is deliberately present and deliberately safe. A player who does not want to decide should not be
-- trapped in a modal -- the server spills the remainder for them, exactly as it did before this panel existed.
local lpSkip = mkButton(lpPanel, {
	Size = UDim2.new(1, -40, 0, 46), Position = UDim2.new(0, 20, 1, -58),
	BackgroundColor3 = CARD, Text = "", AutoButtonColor = false,
})
mkCorner(lpSkip, 12); mkStroke(lpSkip, WHITE, 2)
mkLabel(lpSkip, {
	Text = "Decide for me", Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
	TextColor3 = WHITE, Size = UDim2.fromScale(1, 1),
})

local function lpClose()
	levelPickGui.Enabled = false
	if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyClosed, "PetLevelPicker") end
end

local function lpBuild()
	for _, ch in ipairs(lpList:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
	local pending = tonumber(state.pendingLevels) or 0
	lpCount.Text = ("%d level%s to place"):format(pending, pending == 1 and "" or "s")

	local pets = state.levelPets or {}
	local n = 0
	for _, pt in ipairs(pets) do
		n += 1
		local maxed = pt.maxed and true or false
		local row = mkButton(lpList, {
			Size = UDim2.new(1, -10, 0, 56), BackgroundColor3 = maxed and Color3.fromRGB(48, 52, 64) or CARD,
			Text = "", AutoButtonColor = not maxed, LayoutOrder = n,
		})
		mkCorner(row, 12); mkStroke(row, maxed and Color3.fromRGB(80, 86, 102) or GOLD, 2)

		mkLabel(row, {
			Text = tostring(pt.name or pt.petId), Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
			TextColor3 = maxed and Color3.fromRGB(150, 156, 172) or WHITE,
			Size = UDim2.new(0.6, -20, 1, -14), Position = UDim2.new(0, 16, 0, 7),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		mkLabel(row, {
			-- A maxed pet still LISTS -- greyed and unpickable. Hiding it would read as "that pet is gone";
			-- showing it greyed reads as "that one is finished", which is the true and more useful statement.
			Text = maxed and "MAX" or ("Lv " .. tostring(pt.level or 1)),
			Font = Enum.Font.FredokaOne, TextSize = 18, TextScaled = true,
			TextColor3 = maxed and Color3.fromRGB(150, 156, 172) or GOLD,
			Size = UDim2.new(0.4, -20, 1, -14), Position = UDim2.new(0.6, 4, 0, 7),
			TextXAlignment = Enum.TextXAlignment.Right,
		})

		if not maxed then
			row.MouseButton1Click:Connect(function()
				playUIClick()
				row.AutoButtonColor = false      -- one tap per row; the state push re-enables it
				task.spawn(function()
					local ok, res = pcall(function() return AssignPetLevels:InvokeServer(pt.petId) end)
					if not (ok and type(res) == "table" and res.ok) then
						lpBuild()                 -- refused (raced to max, etc): redraw off the truth
						return
					end
					if _G.showHudBanner then
						pcall(_G.showHudBanner,
							("%s  Lv %d -> %d"):format(tostring(pt.name or pt.petId), res.from, res.to),
							Color3.fromRGB(150, 255, 170), 3)
					end
					-- Levels left over (the pet capped mid-pour) -> stay open for the next pick.
					if (tonumber(res.remaining) or 0) > 0 then lpBuild() else lpClose() end
				end)
			end)
		end
	end

	if n == 0 then
		mkLabel(lpList, {
			Text = "You don't own any pets yet!", Font = Enum.Font.FredokaOne, TextSize = 20, TextScaled = true,
			TextColor3 = WHITE, Size = UDim2.new(1, -10, 0, 56), LayoutOrder = 1,
		})
	end
	lpList.CanvasSize = UDim2.new(0, 0, 0, math.max(1, n) * 64 + 8)
end

-- Republished so applyState refreshes the open panel when levels land, a pet hatches, or a trade completes.
levelPickerRefresh = function()
	if levelPickGui.Enabled then lpBuild() end
end

local function lpOpen()
	if (tonumber(state.pendingLevels) or 0) <= 0 then return end
	if _G.MainMenuManager and _G.MainMenuManager.closeAll then pcall(_G.MainMenuManager.closeAll) end
	lpBuild()
	levelPickGui.Enabled = true
	if _G.MainMenuManager then pcall(_G.MainMenuManager.notifyOpened, "PetLevelPicker") end
end
_G.openPetLevelPicker = lpOpen

lpSkip.MouseButton1Click:Connect(function() playUIClick(); lpClose() end)
if _G.MainMenuManager then
	pcall(_G.MainMenuManager.register, "PetLevelPicker", function() levelPickGui.Enabled = false end)
end

resultBtn.MouseButton1Click:Connect(function()
	playUIClick()
	revealGui.Enabled = false
	resultCard.Visible = false
	resultPetHolder.Visible = false

	-- A LEVEL PULL HANDS OFF TO THE PICKER instead of dropping you back on the crate list. The levels are
	-- sitting in the server's pending pool at this point and the only thing left to do is say where they go,
	-- so putting the crate panel back up first would be a step the player has to click past.
	if (tonumber(state.pendingLevels) or 0) > 0 then
		lpOpen()
		return
	end

	gui.Enabled = true -- the crate panel was hidden while the reveal covered it; this reveal always starts there
	refreshTabs()
end)

-- ===== PLAY THE REVEAL FOR A CRATE SOMEONE ELSE HANDED OUT =====
-- The Daily Rewards crate is opened SERVER-side (it is free, so there is no client invoke to carry the
-- result back) and then pushed here. Publishing openReveal is what lets that crate use this exact reel,
-- result card and Gold flair instead of growing a second reveal that would have to be kept in step.
-- Takes the crate ID rather than the crate table so the caller needs nothing from SkinCrates.
_G.skinCrateShowReveal = function(crateId, result)
	local crate = SkinCrates.getCrate(crateId)
	if not (crate and type(result) == "table" and result.ok) then return false end
	-- openReveal refuses while a reel is already running, and it does so silently. Report that refusal
	-- rather than returning true for a reveal that never happened -- the caller shows its own fallback
	-- message on false, so the player is told the crate is waiting in the Collection Book.
	if spinning or building then return false end
	-- The reel expects the crate panel to be the thing it is covering; opening from outside means that panel
	-- was never up, so `gui` is closed here and openReveal's own teardown puts it back exactly as a normal
	-- open would -- which is also why the player lands on the crate list afterwards.
	openReveal(crate, result)
	return true
end

-- ===== TRADE-UP RESULT =====
-- A trade-up is a pull too, so it lands on the SAME result card a crate does -- same rarity colour, same trait
-- line, same flair escalation. No second reveal UI to keep in sync, and no risk of the two drifting apart.
-- It skips the reel: there was no crate to scroll through, and the ten items were already reviewed on the
-- confirm screen, so the payoff is the only thing left to show.
showTradeUpResult = function(result)
	if not result or not result.skin then return end
	local tierCol = PetSkins.tierColor(result.rarity)
	local isGold = result.isGold == true
	-- THE PAYOFF. Gold gets the five-tap `rare` rhythm; every other pull gets `unlock`. Both outrank
	-- the reel's ticks, so the strip of taps stops dead and the result lands as its own thing.
	if _G.hapticPulse then pcall(_G.hapticPulse, isGold and "rare" or "unlock") end

	-- reelTitle lives INSIDE reelPanel, so the panel stays up; only the scrolling window is hidden and the
	-- panel collapses to a title-only banner above the card.
	reelPanel.Visible = true
	setReelVisible(false)
	gui.Enabled = false -- same footprint mismatch as the crate reveal: nothing may show around the edges
	revealGui.Enabled = true

	reelTitle.Text = "TRADE UP: " .. string.upper(tostring(result.rarity)) .. "!"
	reelTitle.TextColor3 = tierCol

	showResultPet(result.pet, result.skin, result.trait)
	resultName.Text = PetSkins.displayName(result.skin, PetSkins.prettyPet(result.pet))
	do
		local overall = result.overallTier or PetTier.overall(result.skin, result.trait) or result.rarity
		resultTier.Text = "Tier: " .. tostring(overall)
		resultTier.TextColor3 = PetSkins.tierColor(overall)
	end

	-- One clean line, always the same shape ("Trait: King  \xE2\x80\xA2  Epic"), so the eye knows where to
	-- look whether or not the pull had a trait.
	if PetTraits.isNone(result.trait) then
		resultTrait.Text = "Trait: None"
		resultTrait.TextColor3 = Color3.fromRGB(180, 190, 205)
	else
		local tTier = PetTraits.tierOf(result.trait)
		resultTrait.Text = "Trait: " .. PetTraits.displayName(result.trait)
			.. (tTier and ("  \xE2\x80\xA2  " .. tTier) or "")
		resultTrait.TextColor3 = PetTraits.color(result.trait)
	end

	if result.locked then
		resultNote.Text = "Unlock " .. PetSkins.prettyPet(result.pet) .. " to equip this skin"
		resultNote.TextColor3 = Color3.fromRGB(255, 200, 120)
	else
		resultNote.Text = "Ready to Equip!   (" .. (result.consumed or SkinCrates.TRADE_UP.COST)
			.. " " .. tostring(result.from) .. " traded in)"
		resultNote.TextColor3 = Color3.fromRGB(150, 255, 170)
	end

	if isGold then
		playSound(GOLD_SOUND or REVEAL_SOUND, 0.9, GOLD_SOUND and 1 or 0.72)
		playSound(REVEAL_SOUND, 0.6, 1.25)
	else
		playSound(REVEAL_SOUND, 0.7, 1)
	end
	-- A contract is a pull too, so it gets the same contained celebration. The panel is collapsed to a
	-- title-only banner here, and reelPanel clips -- so the burst simply plays in the smaller space.
	celebrate(result.rarity)

	resultCard.Visible = true
	resultCard.Position = UDim2.new(0.5, 0, 0, REVEAL_Y + 14)
	TweenService:Create(resultCard, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, REVEAL_Y) }):Play()
end

-- ===== the open request =====
doOpenCrate = function(crate)
	if openRequestInFlight or spinning then return end
	openRequestInFlight = true
	task.spawn(function()
		local ok, result = pcall(function() return OpenCrate:InvokeServer(crate.id) end)
		openRequestInFlight = false
		if not ok or type(result) ~= "table" then
			warn("[SkinCrateClient] open failed: " .. tostring(result))
			return
		end
		if not result.ok then
			-- Every refusal is a real server-side reason; surface it rather than failing silently.
			local msg = ({
				not_enough_tokens = "Not enough Crate Tickets!",
				unknown_crate     = "That crate doesn't exist.",
				empty_crate       = "That crate has no items yet.",
				cooldown          = "Slow down a second!",
				-- The Pet Level Crate refuses BEFORE charging when there is nothing left to level, so say why --
				-- otherwise a maxed-out player just sees the button do nothing and assumes it's broken.
				all_pets_maxed    = "All your pets are max level! Nothing to level up.",
			})[result.reason] or "Couldn't open that crate."
			if _G.showHudBanner then _G.showHudBanner(msg, Color3.fromRGB(255, 150, 90), 3) end
			refreshTabs()
			return
		end
		openReveal(crate, result)
	end)
end

-- A CRATE SOMEBODY GAVE US. The server has already rolled it and banked the prize by the time this arrives, so
-- there is nothing to validate and nothing to charge -- this is purely "show them what they got", through the
-- exact same reveal a bought crate uses. Deliberately reusing openReveal rather than writing a gift-shaped
-- variant: a free Mythic should feel identical to a paid one, and one reveal path means one thing to maintain.
--
-- It does NOT open the crates panel first. The reveal is its own full-screen ScreenGui, and the player is
-- somewhere else when this fires (the Rewards hub, on day 7), so pulling up the shop behind it would leave
-- them staring at the token store when the reel finishes.
FreeCrateReveal.OnClientEvent:Connect(function(crateId, result)
	if type(result) ~= "table" or not result.ok then return end
	local crate = SkinCrates.getCrate(crateId)
	if not crate then return end
	if spinning then return end   -- already mid-reel: dropping it beats stacking two reveals on each other
	openReveal(crate, result)
end)

-- ============================================================================================================
-- TRADE BRIDGE
-- ============================================================================================================
-- The trade window lives in PetFollow (it owns the Pet Hub panel), but the SKIN inventory lives here. Rather
-- than give PetFollow a second copy of the skin state to keep in sync, it asks for a snapshot at the moment it
-- draws its "things you can offer" list.
--
-- Keys come back already prefixed with "SKIN:" -- the exact string PetSystem's PetTradeOfferEvent expects -- so
-- the trade window can pass one straight through without knowing anything about how skins are stored.
-- Equip a skin from OUTSIDE this script. The Pet Hub's VIEW MORE card lists a pet's skins and needs to be able
-- to put one on without owning a copy of the remote or re-implementing the rules -- the server still validates
-- ownership and whether the pet is unlocked, exactly as it does for the button in this panel.
-- Pass skinId = false to clear back to the pet's natural look.
_G.skinEquip = function(petId, skinId, traitId)
	if type(petId) ~= "string" then return end
	pcall(function() EquipSkin:FireServer(petId, skinId or false, traitId or false) end)
end

_G.skinTradeList = function()
	local out = {}
	for key, count in pairs(state.skins) do
		local petId, skinId, traitId = PetSkins.parseKey(key)
		local n = math.max(0, math.floor(tonumber(count) or 0))
		if petId and skinId and n > 0 then
			local label = PetSkins.displayName(skinId, PetSkins.prettyPet(petId))
			if not PetTraits.isNone(traitId) then label = label .. " (" .. PetTraits.displayName(traitId) .. ")" end
			out[#out + 1] = {
				key   = PetSkins.TRADE_PREFIX .. key, -- "SKIN:Pet|Skin|Trait"
				name  = label,
				count = n,
				tier  = PetSkins.tierOf(skinId),
				color = PetSkins.tierColor(skinId),
				pet   = petId,
				skin  = skinId,
			}
		end
	end
	-- rarest first, so the valuable things are at the top of the offer list where they're easy to find
	table.sort(out, function(a, b)
		local ra, rb = PetSkins.TierRank[a.tier] or 0, PetSkins.TierRank[b.tier] or 0
		if ra ~= rb then return ra > rb end
		return a.name < b.name
	end)
	return out
end

-- ============================================================================================================
-- COLLECTION REWARDS
-- ============================================================================================================
-- Two kinds of message arrive here:
--   kind = "earned" -> just for you: one or more collections you completed, with what they paid out.
--   kind = "full"   -> server-wide: somebody finished EVERY skin on EVERY pet.
-- Banners are staggered so completing two pets at once (which a trade can do) doesn't overwrite itself.
-- ============================================================================================================
-- COLLECTION REWARD BANNERS
-- ============================================================================================================
-- Completing a collection is how you earn a TITLE ("Bee Keeper" and friends), an aura and an exclusive skin.
-- These used to go out through _G.showHudBanner at REWARD priority, which is the tier meant for NUDGES --
-- "Daily Reward Ready", "Stomach Upgrade Available". At 40 a finished collection queued behind literally
-- every other kind of news and never triggered the milestone haptic, which starts at TUTORIAL.
--
-- Three things this fixes:
--   1. PRIORITY. Your own completion is a TUTORIAL-tier milestone -- exclusive, nothing plays beside it, and
--      it buzzes. Somebody ELSE's completion stays low: it is news about a stranger, not about you.
--   2. THE SILENT FALLBACK. The old code was `if _G.showHudBanner then ... else print(text) end`. CoreClient
--      publishes that global, and if a collection ever completed before CoreClient finished loading the
--      reward went to the OUTPUT WINDOW instead of the screen. This waits for NotifyCenter instead.
--   3. PILE-UP. Multiple notices were fired 3.2s apart while each asked to be shown for 6s, so the queue
--      grew faster than it drained and the last title in a batch arrived long after the crate was closed.
--      Spacing is now taken from the duration, so they play back to back with a clean gap.
local function collectionBanner(text, seconds, mine)
	local NC = _G.NotifyCenter
	if not NC or not NC.push then
		-- NotifyCenter genuinely absent (stale-duplicate eviction mid-boot): retry briefly rather than
		-- dropping a reward the player has earned. Never print-and-forget.
		task.spawn(function()
			for _ = 1, 40 do
				task.wait(0.25)
				if _G.NotifyCenter and _G.NotifyCenter.push then
					pcall(_G.NotifyCenter.push, {
						text = text, color = Color3.fromRGB(255, 214, 90),
						priority = mine and _G.NotifyCenter.PRIORITY.TUTORIAL or _G.NotifyCenter.PRIORITY.REWARD,
						duration = seconds,
					})
					return
				end
			end
			warn("[SkinCrate] NotifyCenter never arrived -- collection banner lost: " .. tostring(text))
		end)
		return
	end
	pcall(NC.push, {
		text     = text,
		color    = Color3.fromRGB(255, 214, 90),
		priority = mine and NC.PRIORITY.TUTORIAL or NC.PRIORITY.REWARD,
		duration = seconds,
	})
end

CollectAnnounce.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end

	if info.kind == "full" then
		local mine = (info.playerName == player.Name)
		local text = mine
			and "\xF0\x9F\x8F\x86 YOU COMPLETED THE ENTIRE COLLECTION! Title unlocked: " .. tostring(info.title)
			or string.format("\xF0\x9F\x8F\x86 %s completed the ENTIRE collection!", tostring(info.playerName))
		collectionBanner(text, 10, mine)
		return
	end

	if info.kind == "earned" and type(info.notices) == "table" then
		for i, n in ipairs(info.notices) do
			-- 7s apart for a 6s banner: one clean gap between titles instead of a queue that outgrows itself.
			task.delay((i - 1) * 7, function()
				local text
				-- FOUR WORDS EITHER WAY. Both of these used to carry the payout after the headline -- the title
				-- on one, a "Title: X * Gold Aura * Sunset skin" list on the other -- and that tail was both the
				-- part the five-word cap takes first and the part the player is already looking at: the crate
				-- reveal panel is open in front of them, listing exactly those rewards, at exactly this moment.
				if n.kind == "full" then
					text = "\xF0\x9F\x8F\x86 FULL COLLECTION COMPLETE!"
				else
					text = "\xE2\x9C\x94 " .. tostring(n.petName or n.pet) .. " COLLECTION COMPLETE!"
				end
				collectionBanner(text, 6, true)   -- always the player's own reward -> milestone tier
				playSound(REVEAL_SOUND, 0.6, 1.1)
			end)
		end
		refreshTabs()
	end
end)

-- ============================================================================================================
-- GOLD ANNOUNCEMENT (server-wide)
-- ============================================================================================================
-- Server-wide pull news: GOLD (the knife pull) and any LEGENDARY unlock -- a Legendary skin, trait or pet.
-- `tier` on the payload picks the fanfare; the banner names the legendary THING the way a player would say
-- it out loud, because this line is read off the screen mid-flight, not parsed.
GoldAnnounce.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	local mine = (info.playerName == player.Name)
	local isLeg = (info.tier == "Legendary")

	local what
	if info.petRarity then
		-- a Pet Crate pull: the band IS the pet's permanent rarity
		what = "a " .. string.upper(tostring(info.petRarity)) .. " " .. PetSkins.prettyPet(info.pet)
	elseif info.skin then
		-- name only the legendary half (or both) of a skin+trait pull, so the banner says what earned it
		local bits = {}
		if not isLeg or PetSkins.tierOf(info.skin) == "Legendary" then
			bits[#bits + 1] = PetSkins.displayName(info.skin, PetSkins.prettyPet(info.pet))
		end
		if info.trait and (not isLeg or PetTraits.tierOf(info.trait) == "Legendary") and not PetTraits.isNone(info.trait) then
			bits[#bits + 1] = "the " .. PetTraits.displayName(info.trait) .. " Trait"
		end
		if #bits == 0 then bits[1] = PetSkins.displayName(info.skin, PetSkins.prettyPet(info.pet)) end
		what = table.concat(bits, " + ")
	elseif info.trait then
		what = "the " .. PetTraits.displayName(info.trait) .. " Trait"
	else
		what = isLeg and "a LEGENDARY pull" or "a Gold pull"
	end

	local text
	if isLeg then
		text = string.format("\xF0\x9F\x94\xA5 %s unlocked %s from the %s!",
			tostring(info.playerName), what, tostring(info.crateName or "crate"))
	else
		text = string.format("\xE2\xAD\x90 %s pulled %s from the %s!",
			tostring(info.playerName), what, tostring(info.crateName or "crate"))
	end
	if _G.showHudBanner then
		-- Legendary rides its own tier colour so the two kinds of news read apart at a glance
		_G.showHudBanner(text, isLeg and PetSkins.tierColor("Legendary") or Color3.fromRGB(255, 214, 90), 6)
	else
		print("[SkinCrate] " .. text)
	end
	-- The puller already hears their own jackpot sound in the reveal; don't double it up for them.
	if not mine then playSound(REVEAL_SOUND, isLeg and 0.3 or 0.35, 0.8) end
end)

-- ============================================================================================================
-- OPEN / CLOSE
-- ============================================================================================================
_G.MainMenuManager.register("SkinCrates", function() gui.Enabled = false end)

setOpen = function(open, fromHub, wantTab)
	if open then
		-- The hub's nav sends which page it wants (CRATES or TOKENS). Without this the panel always
		-- opened on whatever tab was last used, so pressing TOKENS could land you on Crates.
		if wantTab and tabButtons[wantTab] then activeTab = wantTab end
		_G.MainMenuManager.notifyOpened("SkinCrates")
		gui.Enabled = true
		refreshTabs()
		if _G.applyHudScaling then _G.applyHudScaling() end -- match the Shop's on-screen size exactly
		-- Log the RESOLVED on-screen box, the same [UIFix] diagnostic the Shop and Pet Hub print. If the panel
		-- ever appears not to open, this line says whether it was enabled and where it actually landed.
		task.defer(function()
			print(string.format("[SkinCrate] panel OPEN -- tab=%s tokens=%d AbsoluteSize=%s AbsolutePosition=%s",
				activeTab, state.tokens, tostring(panel.AbsoluteSize), tostring(panel.AbsolutePosition)))
		end)
	else
		gui.Enabled = false
		_G.MainMenuManager.notifyClosed("SkinCrates")
		print("[SkinCrate] panel CLOSED")
	end
end

-- The X is the ONLY way to close this panel. The full-screen frame is Active=false on purpose so a click
-- outside falls through to the HUD menu buttons instead of dismissing the menu.
closeBtn.MouseButton1Click:Connect(function() playUIClick(); setOpen(false) end)

-- `wantTab` lets the Pet Hub nav open this panel straight onto CRATES or TOKENS. Omitted elsewhere, which
-- keeps the plain toggle behaviour every other caller already relies on.
--
-- `fromHub` is now IGNORED -- it only ever drove the BACK button's visibility, and there is no BACK button.
-- The parameter stays so the existing callers (the hub's nav, _G.openSkinTradeUp) need no edit, and so a
-- future opened-from-X behaviour has the signal already plumbed through.
_G.toggleSkinCrates = function(fromHub, wantTab) setOpen(not gui.Enabled, fromHub, wantTab) end

-- ===== TRADE UP, ENTERED FROM THE PET HUB =====
-- Trading up burns DUPLICATE SKINS YOU ALREADY OWN and hands back one of the next rarity. It opens no crate
-- and costs no token, so its door belongs beside the pets whose duplicates it eats, not on the crate list.
-- The PAGE is unchanged and still lives in this file -- only the entrance moved, the same way Wormhole moved
-- into MORE+ without its panel changing.
--
-- activeTab is set directly rather than handed to setOpen as `wantTab`: that argument is validated against
-- the four TOP-BAR tabs and "tradeup" is a sub-page, so it would be ignored. The second argument is the
-- now-vestigial fromHub (see above): getting back to the hub is the PETS tab, here as on every other page.
_G.openSkinTradeUp = function()
	activeTab = "tradeup"
	setOpen(true, true)
end

-- ===== SKIN METADATA, for the Pet Hub's Pet Skins page =====
-- PetFollow draws that page but cannot require PetSkins: it sits at Luau's 200-locals-per-scope ceiling and
-- one more top-level local stops the whole script compiling. Rather than copy the rarity table over there
-- (two copies that can disagree the first time a skin is retuned), this panel -- which already requires the
-- module -- publishes a reader. One source of truth, no extra local on the other side.
_G.petSkinMeta = function(skinId)
	if not skinId or skinId == "" then
		return { name = "Default", tier = "Common", tierColor = Color3.fromRGB(190,198,214), color = Color3.fromRGB(190,198,214) }
	end
	local ok, sk = pcall(function() return PetSkins.get(skinId) end)
	return {
		name      = (ok and sk and sk.displayName) or tostring(skinId),
		tier      = PetSkins.tierOf(skinId) or "Common",
		tierColor = PetSkins.tierColor(skinId) or WHITE,
		color     = (ok and sk and sk.color) or Color3.fromRGB(120,130,145),
	}
end
-- How many skins exist in total, for the page's 'Skins Owned: X / N' readout. +1 for the Default look, which
-- every pet owns from the start and which the page lists as a real card.
_G.petSkinTotal = function() return #PetSkins.Order + 1 end

-- Trait metadata for the same page (name, rarity, a ready-made "King  \xC2\xB7  Epic" label, and the accent
-- colour). Published for the same 200-locals reason as petSkinMeta: PetFollow draws the row but cannot
-- require PetTraits.
_G.petTraitMeta = function(traitId)
	if PetTraits.isNone(traitId) then
		return { name = "None", label = "None", tier = nil, color = Color3.fromRGB(180, 200, 230) }
	end
	local tier = PetTraits.tierOf(traitId)
	local name = PetTraits.displayName(traitId)
	return {
		name  = name,
		tier  = tier,
		label = name .. (tier and ("  \xC2\xB7  " .. tier) or ""),
		color = PetTraits.color(traitId),
	}
end

-- Chat shortcut so the panel can be opened without going through the Pet Hub or the MORE+ list. Type /crates.
-- [REMOVE BEFORE LAUNCH] along with the other dev conveniences.
--
-- TWO paths on purpose: this place uses TextChatService, which does NOT fire Player.Chatted -- that's why the
-- first version of this shortcut did nothing at all. TextChatCommand is the one that actually works here;
-- Player.Chatted is kept for places still on the legacy chat.
local function toggleFromChat()
	print("[SkinCrate] /crates -> toggling panel")
	setOpen(not gui.Enabled)
end

player.Chatted:Connect(function(msg) -- legacy chat path
	local cmd = string.lower((string.gsub(msg, "^%s*(.-)%s*$", "%1")))
	if cmd == "/crates" or cmd == "/skins" then toggleFromChat() end
end)

do -- modern chat path (TextChatService) -- registered client-side so it needs no remote
	local ok, err = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "SkinCratesCommand"
		cmd.PrimaryAlias = "/crates"
		cmd.SecondaryAlias = "/skins"
		cmd.Parent = TextChatService
		cmd.Triggered:Connect(toggleFromChat)
	end)
	if not ok then warn("[SkinCrate] TextChatService command registration failed: " .. tostring(err)) end
end

-- ============================================================================================================
-- STATE WIRING
-- ============================================================================================================
SkinStateEvent.OnClientEvent:Connect(applyState)
task.spawn(function()
	local ok, s = pcall(function() return GetSkinState:InvokeServer() end)
	if ok then applyState(s) end
end)

print("[SkinCrateClient] ready -- " .. #SkinCrates.CRATES .. " crates, " ..
	#SkinCrates.TOKEN_PACKS .. " ticket packs. Open with _G.toggleSkinCrates()")
