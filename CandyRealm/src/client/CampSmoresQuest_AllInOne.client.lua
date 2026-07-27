--======================================================================
-- CampSmoresQuest_AllInOne.client.lua  (LocalScript, per-player)
--======================================================================
-- "CAMP S'MORES" -- ISLAND 14. Build the campsite in stages; every step shows.
--
--   1  CHOP      4 PineTrees. Each one topples and hands you a Pine Log.
--   2  MILL      Carry the logs to the block named "mill". A cutting station is built
--                there; the logs run through the saw, the blade spins, chips fly, and
--                they come out as giant roasting sticks -- which then fly to the
--                campfire and plant themselves one at a time.
--   3  GATHER    6 MallowMushrooms. Only the CAP comes away; the stem stays and regrows.
--   4  DELIVER   Take them to the Candy Npc. Each pair loads one roasting stick.
--   *  IGNITE    Fire, smoke, embers, ambience -- and the marshmallows slowly toast.
--
-- WHAT THE WORLD PROVIDES (names ignore case/spaces/underscores):
--   PineTree        x4+  your tree models. They topple where they stand.
--   mill            x1   a plain block. The cutting station is BUILT on it; it's hidden.
--   campfire        x1   the woodpile that lights at the end.
--   MallowMushroom  x6+  your mushrooms. The cap is taken, the stem is left behind.
--   Marshmallowbig  x3   the giant marshmallows. HIDDEN until each stick is loaded.
--   Candy Npc       x1   quest giver, on island14.
--
-- Everything is client-side and per-player, like the island's other quests.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")
local TextChatService   = game:GetService("TextChatService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

print("[Smores] >>> VERSION camp-v1 loaded <<<")

-- ============================================================================
-- CONFIG
-- ============================================================================
local ISLAND_PREFIX = "island14"
local TREE_NAME     = "pinetree"
local MILL_NAME     = "mill"
local FIRE_NAME     = "campfire"
local SHROOM_NAME   = "mallowmushroom"
local AXE_NAME      = "axe"
local MARSH_NAME    = "marshmallowbig"
local STICK_NAME    = "stickthatgoesup"   -- your 3 roasting sticks by the fire
local STAND_NAME    = "stand"             -- the operator's deck at the mill
local NPC_NAMES     = { "candynpc", "questnpc" }
local NPC_MAX_DIST  = 700

local LOGS_NEEDED   = 3      -- logs to mill -- one per roasting stick
local SHROOMS_NEEDED = 6     -- mushroom caps to gather
local CARRY_MAX     = 8      -- backpack capacity -- must clear SHROOMS_NEEDED
-- ONE DIAL FOR THE HAT. Sizes AND offsets are both multiplied by it, so it never ends up a
-- bigger dome sitting at the old height with its brim through your eyebrows.
local HAT_SCALE     = 0.95
local MILL_STROKES  = 8      -- saw strokes to get through ONE log (~12s played well)
local SHROOM_PULL   = 4.2    -- seconds of holding to free one mushroom cap
local FIRE_DROP     = 10     -- studs to sink the fire below the top of the campfire model
local FLAME_SCALE   = 4.0    -- flame HEIGHT (not the coals or the glow)
local FLAME_WIDTH   = 0.62   -- flame SPREAD, on top of the scale -- narrower without shrinking
local REGROW_TIME   = 22     -- seconds before a picked mushroom caps over again
local SWINGS_PER_TREE = 6    -- axe hits to fell one pine
-- how the axe sits in your hand. Tweak these if it reads wrong for your model:
local AXE_PITCH     = -110   -- degrees the shaft tips at rest (70 flipped 180 at the grip)
local AXE_ROLL      = -10    -- degrees the blade rolls
local AXE_GRIP      = 0.44   -- how far down the shaft the hand sits (0.5 = the very end)
local AXE_FLIP      = false  -- true if it grabs the head instead of the handle
local CHOP_REACH    = 15     -- studs the swing reaches

local COIN_REWARD   = 1500

-- Audio: your OWN asset ids. "" = silent, and nothing is created for an empty id --
-- given how many ids in this place fail auth, silence is the safe default.
local SOUND_CHOP  = ""
local SOUND_SAW   = ""
local SOUND_POP   = ""
local SOUND_FIRE  = ""       -- LOOPING campfire ambience
local FIRE_VOLUME = 0.45
local FIRE_RANGE  = 110

-- Palette in ONE table: Luau caps a function at 200 local registers and a file like this
-- sits close to it. Forty colours as forty locals cost forty registers; as a table, one.
local PAL = {
	BARK    = Color3.fromRGB(104, 74, 50),
	BARK_D  = Color3.fromRGB(74, 52, 36),
	WOOD    = Color3.fromRGB(178, 126, 78),
	WOOD_D  = Color3.fromRGB(134, 92, 56),
	WOOD_L  = Color3.fromRGB(210, 160, 108),
	PINE    = Color3.fromRGB(58, 120, 74),
	PINE_D  = Color3.fromRGB(40, 92, 58),
	IRON    = Color3.fromRGB(98, 102, 110),
	IRON_D  = Color3.fromRGB(62, 66, 72),
	STONE   = Color3.fromRGB(150, 146, 138),
	STONE_D = Color3.fromRGB(108, 104, 98),
	MALLOW  = Color3.fromRGB(250, 246, 238),
	TOAST   = Color3.fromRGB(198, 132, 66),
	FLAME   = Color3.fromRGB(255, 156, 56),
	FLAME_H = Color3.fromRGB(255, 232, 156),
	EMBER   = Color3.fromRGB(255, 96, 40),
	SMOKE   = Color3.fromRGB(90, 84, 78),
	CHIP    = Color3.fromRGB(226, 196, 144),
	CANVAS  = Color3.fromRGB(168, 142, 96),
	CANVAS_D = Color3.fromRGB(130, 108, 72),
	PANEL   = Color3.fromRGB(34, 30, 24),
	BUB_F   = Color3.fromRGB(255, 240, 248),
	BUB_S   = Color3.fromRGB(214, 92, 158),
	BUB_T   = Color3.fromRGB(74, 30, 58),
	BUB_H   = Color3.fromRGB(170, 130, 150),
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

local function tween(inst, t, goal, style)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad), goal)
	tw:Play(); return tw
end

local function playSound(id, vol)
	if not id or id == "" then return end
	local s = Instance.new("Sound"); s.SoundId = id; s.Volume = vol or 0.6
	s.Parent = SoundService; s:Play(); Debris:AddItem(s, 6)
end

local function pollFor(fn, timeout)
	local t0 = os.clock()
	repeat
		local r = fn()
		if r then return r end
		task.wait(0.5)
	until os.clock() - t0 > (timeout or 60)
	return fn()
end

local function findIsland()
	for _, m in ipairs(Workspace:GetChildren()) do
		if m:IsA("Model") and string.sub(norm(m.Name), 1, #ISLAND_PREFIX) == ISLAND_PREFIX then
			return m
		end
	end
	return nil
end

-- every instance whose normalised name matches, inside the island if we have it
local function findAll(key, island)
	local out = {}
	for _, d in ipairs((island or Workspace):GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Model")) and norm(d.Name) == key then
			table.insert(out, d)
		end
	end
	return out
end

local function findOne(key, island)
	local a = findAll(key, island)
	return a[1]
end

local function frameOf(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	return inst:GetBoundingBox()
end

local function topPartOf(model)     -- the highest BasePart -- a mushroom's cap
	local best
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (not best or d.Position.Y > best.Position.Y) then best = d end
	end
	return best
end

-- Transparency alone does not hide a part: a Decal/Texture keeps drawing on it and a
-- SurfaceAppearance overrides it outright. Both have to go.
local function hidePart(d, on)
	d.Transparency = on and 1 or (d:GetAttribute("SmoresT") or 0)
	d.CanCollide   = not on and (d:GetAttribute("SmoresC") ~= false)
	d.CanQuery     = not on
	for _, c in ipairs(d:GetChildren()) do
		if c:IsA("Decal") or c:IsA("Texture") then c.Transparency = on and 1 or 0
		elseif on and c:IsA("SurfaceAppearance") then c:Destroy() end
	end
end

local function hideThing(inst, on)
	if inst:IsA("BasePart") then
		if inst:GetAttribute("SmoresT") == nil then
			inst:SetAttribute("SmoresT", inst.Transparency)
			inst:SetAttribute("SmoresC", inst.CanCollide)
		end
		hidePart(inst, on)
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				if d:GetAttribute("SmoresT") == nil then
					d:SetAttribute("SmoresT", d.Transparency)
					d:SetAttribute("SmoresC", d.CanCollide)
				end
				hidePart(d, on)
			end
		end
	end
end

-- ============================================================================
-- STATE
-- ============================================================================
local camp                  -- Folder for everything we build
local island, millPart, firePart, npcHead, fireModel
local step        = 0       -- 0 talk, 1 chop, 2 mill, 3 gather, 4 deliver, 5 done
local questAccepted = false
local logsHeld    = 0       -- logs carried right now
local logsMilled  = 0
local shroomsHeld = 0
local loaded      = 0       -- roasting sticks with a marshmallow on
local carried     = {}      -- { kind = "log" | "cap" } -- lives in the backpack
local millLeft    = 0       -- saw strokes left on the cut in progress
local sticks      = {}      -- { part =, home =, marsh =, up =, done = }
local marshParts  = {}
local refreshBanner
local showBubble
local milling     = false
local axeTemplate, axeHeld, axeHold, axeSwingUntil

-- ---- THE AXE -------------------------------------------------------------
-- Your 'axe' model is copied ONCE at startup and the original is hidden, so there is never a
-- spare axe lying around and taking it back is just destroying the copy.
--
-- IT IS WELDED TO THE HAND, not anchored and re-positioned every frame. Anchoring it and
-- driving its CFrame each frame fights the character's own animation -- the arm swings, the
-- axe does not, and it reads as floating near the hand rather than held in it. A weld makes
-- the hand carry it, and the swing is then just an animation of the weld's C0.
--
-- HELD BY THE HANDLE: a model's pivot is its centre, so welding that to the hand puts the fist
-- halfway up the shaft. The grip is derived from the model instead -- the longest axis is the
-- shaft, and the HEAD is whichever end holds most of the volume, so the handle butt is the far
-- end from that.
local function gripFor(model)
	local bcf, bsz = frameOf(model)
	local axes = { { Vector3.new(1, 0, 0), bsz.X }, { Vector3.new(0, 1, 0), bsz.Y },
	               { Vector3.new(0, 0, 1), bsz.Z } }
	table.sort(axes, function(a, b) return a[2] > b[2] end)
	local ax, len = axes[1][1], axes[1][2]

	local sum, tot = 0, 0
	local parts = model:IsA("BasePart") and { model } or model:GetDescendants()
	for _, d in ipairs(parts) do
		if d:IsA("BasePart") then
			local v = math.max(0.001, d.Size.X * d.Size.Y * d.Size.Z)
			sum += bcf:PointToObjectSpace(d.Position):Dot(ax) * v
			tot += v
		end
	end
	local headSide = ((tot > 0 and sum / tot or 0) >= 0) and 1 or -1
	if AXE_FLIP then headSide = -headSide end
	local gripPos = (bcf * CFrame.new(ax * (-headSide * len * AXE_GRIP))).Position
	local headDir = (bcf - bcf.Position) * (ax * headSide)
	if headDir.Magnitude < 0.01 then headDir = Vector3.new(0, 1, 0) end
	print(("[Smores] axe grip: shaft %.1f studs, head toward %s"):format(len, tostring(headDir)))
	-- -Z of this frame runs up the shaft toward the head
	return CFrame.lookAt(gripPos, gripPos + headDir)
end

local function biggestPart(inst)
	if inst:IsA("BasePart") then return inst end
	local best, bv
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if not bv or v > bv then best, bv = d, v end
		end
	end
	return best
end

local function takeAxe()
	if axeHeld then axeHeld:Destroy(); axeHeld = nil; axeHold = nil; print("[Smores] axe taken back") end
end

local function giveAxe()
	if axeHeld or not axeTemplate then return end
	local char = player.Character
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not hand then return end                       -- retried by the watcher below

	local c = axeTemplate:Clone()
	c.Name = "AxeHeld"
	local root = biggestPart(c)
	if not root then c:Destroy(); return end
	if c:IsA("Model") then c.PrimaryPart = root end

	local grip = gripFor(c)
	local C1   = root.CFrame:ToObjectSpace(grip)      -- the grip, in the root part's own space

	for _, d in ipairs(c:IsA("BasePart") and { c } or c:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false; d.CanCollide = false; d.CanQuery = false
			d.Massless = true
			if d ~= root then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = root; wc.Part1 = d; wc.Parent = root
			end
		end
	end

	c.Parent = char
	axeHold = Instance.new("Weld")
	axeHold.Name = "AxeHold"
	axeHold.Part0 = hand
	axeHold.Part1 = root
	axeHold.C1 = C1
	axeHold.C0 = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(AXE_PITCH), 0, math.rad(AXE_ROLL))
	axeHold.Parent = root
	axeHeld = c
	print("[Smores] axe handed over -- welded into the hand by the handle")
end

-- the swing is an animation of the weld, so the arm and the axe move together
RunService.RenderStepped:Connect(function()
	if not (axeHold and axeHold.Parent) then return end
	local sw = 0
	if axeSwingUntil and os.clock() < axeSwingUntil then
		sw = math.sin((1 - (axeSwingUntil - os.clock()) / 0.55) * math.pi)
	end
	axeHold.C0 = CFrame.new(0, -0.35, 0)
		* CFrame.Angles(math.rad(AXE_PITCH - 120 * sw), 0, math.rad(AXE_ROLL))
end)

-- a respawn drops the weld with the old character, so hand it back
player.CharacterAdded:Connect(function()
	axeHeld, axeHold = nil, nil
	task.delay(1.5, function() if step == 1 then giveAxe() end end)
end)

-- ============================================================================
-- THE BACKPACK -- everything you gather goes in it
-- ============================================================================
-- The NPC hands this over with the axe. Carrying things in your arms capped you at what you
-- could physically hold, which is why six mushrooms would not fit; the pack is the inventory,
-- and what is in it shows as items poking out of the top.
--
-- It is WELDED to the torso rather than positioned each frame, for the same reason as the axe:
-- an anchored prop driven by CFrame fights the character's animation and reads as floating.
-- FIT THE HAT TO THE HEAD THAT IS WEARING IT.
--
-- A fixed-size hat is wrong on almost everybody: hair, horns and hoods are accessories with
-- their own sizes, so the same dome that sits neatly on a bald head has a fringe growing
-- through it on the next player. This measures the head AND every accessory attached to it, in
-- the head's own frame, and returns how wide and how tall the hat has to be to swallow them.
--
-- Distance-gated to 6 studs so it measures headwear and not a back accessory or a tool.
local function headExtent(char, head)
	local rad = math.max(head.Size.X, head.Size.Z) * 0.5
	local top = head.Size.Y * 0.5
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local h = a:FindFirstChild("Handle")
			if h and h:IsA("BasePart") and (h.Position - head.Position).Magnitude < 6 then
				local o, s = head.CFrame:PointToObjectSpace(h.Position), h.Size * 0.5
				rad = math.max(rad, math.abs(o.X) + s.X, math.abs(o.Z) + s.Z)
				top = math.max(top, o.Y + s.Y)
			end
		end
	end
	return rad, top
end

-- Grow the hat until it covers that, then RAISE it until its crown clears the tallest thing on
-- the head -- growing alone would leave a tall hairstyle poking straight out of the top.
--
-- FIT ON THE BRIM, NOT THE DOME. The brim is 1.66 wide at scale 1 against the dome's 1.30, so
-- it is the brim that does the covering -- and sizing off the narrower dome grew the whole hat
-- about a quarter larger than it needed to be to cover the same hair. Radii at scale 1: brim
-- 0.83, dome 0.65, dome half-height 0.54.
local function fitHat(char, head, base)
	local rad, top = headExtent(char, head)
	local H    = math.clamp(math.max(base, (rad + 0.03) / 0.83), base, 1.55)
	local seat = math.max(0.52 * H, top + 0.05 - 0.54 * H)
	return H, seat
end

-- Anything still standing proud of the crown after all that is taller than a hat can sensibly
-- be -- some hair pieces are half a metre of spikes. Those get hidden while the hat is on
-- rather than growing the hat into something comical, and put back when it comes off.
local function tuckHair(char, head, seat, H, store)
	local crown = seat + 0.54 * H
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local h = a:FindFirstChild("Handle")
			if h and h:IsA("BasePart") and (h.Position - head.Position).Magnitude < 6 then
				local o, s = head.CFrame:PointToObjectSpace(h.Position), h.Size * 0.5
				if o.Y + s.Y > crown then
					store[h] = h.Transparency
					h.Transparency = 1
				end
			end
		end
	end
end

local pack, packSlots = nil, {}
local hidHair = {}

local function refreshPack()
	for i, sl in ipairs(packSlots) do
		local item  = carried[i]
		local isLog = item and item.kind == "log"
		sl.log.Transparency  = isLog and 0 or 1
		sl.face.Transparency = isLog and 0 or 1
		sl.cap.Transparency  = (item and not isLog) and 0 or 1
		sl.stem.Transparency = (item and not isLog) and 0 or 1
	end
end

-- A wood-framed canvas packboard, and deliberately little else: two uprights, a tapered sack,
-- a rolled top under a buckled flap, a bedroll underneath, straps over the shoulders. Every
-- extra thing hung off it -- lantern, hatchet, canteen, pouches -- competed with the one part
-- that has to be legible from behind, which is what you are carrying in the top.
local function buildBackpack()
	if pack then return end
	local char  = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not torso then return end

	pack = Instance.new("Model"); pack.Name = "CampPack"; pack.Parent = char
	local function bit(props, cf)
		props.Anchored = false; props.CanCollide = false; props.CanQuery = false
		props.Massless = true; props.Parent = pack
		local p = mk(props); p.CFrame = torso.CFrame * cf; return p
	end

	local BODY_CF = CFrame.new(0, 0.25, 0.92)
	local body = bit({ Color = PAL.CANVAS, Size = Vector3.new(1.85, 1.75, 0.95) }, BODY_CF)

	-- ---- the frame: two uprights and two crossbars, standing proud of the canvas.
	-- THEY END AT THE PACK. At 3.0 studs from a low centre they ran out under the sack and past
	-- the bedroll, reading as two poles growing out of your back rather than as a frame.
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Color = PAL.WOOD_D, Size = Vector3.new(0.2, 2.4, 0.2) }, CFrame.new(sx * 0.88, 0.34, 1.46))
	end
	for _, hy in ipairs({ 1.4, -0.78 }) do
		bit({ Color = PAL.WOOD, Size = Vector3.new(2.0, 0.18, 0.18) }, CFrame.new(0, hy, 1.46))
	end
	-- rounded pads where the straps cross your shoulders: the one place a pack touches you
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK, Size = Vector3.new(0.92, 0.44, 0.44) },
			CFrame.new(sx * 0.6, 1.02, 0.16) * CFrame.Angles(0, 0, math.rad(90)))
	end

	-- ---- the sack: tapers in toward the bottom in two steps rather than one, with a rolled
	-- closure on top, compression straps round it and a pad on the base it stands on
	bit({ Color = PAL.CANVAS,   Size = Vector3.new(1.68, 0.5, 0.88) }, CFrame.new(0, -0.66, 0.90))
	bit({ Color = PAL.CANVAS_D, Size = Vector3.new(1.46, 0.6, 0.78) }, CFrame.new(0, -1.02, 0.88))
	bit({ Color = PAL.CANVAS_D, Size = Vector3.new(1.9, 0.16, 0.99) }, CFrame.new(0, -0.16, 0.92))
	bit({ Color = PAL.BARK_D,   Size = Vector3.new(1.9, 0.13, 0.99) }, CFrame.new(0, 0.62, 0.92))
	bit({ Color = PAL.BARK_D,   Size = Vector3.new(1.9, 0.13, 0.99) }, CFrame.new(0, -0.44, 0.92))
	bit({ Color = PAL.WOOD_D,   Size = Vector3.new(1.6, 0.18, 0.86) }, CFrame.new(0, -1.34, 0.88))
	bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CANVAS_D, Size = Vector3.new(1.86, 0.5, 0.5) },
		CFrame.new(0, 1.26, 0.9) * CFrame.Angles(0, 0, math.rad(90)))

	-- ---- the flap, two leather straps and their buckles
	bit({ Color = PAL.CANVAS, Size = Vector3.new(1.92, 0.66, 1.02) },
		CFrame.new(0, 1.0, 0.94) * CFrame.Angles(math.rad(6), 0, 0))
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.3, 1.5, 0.1) }, CFrame.new(sx * 0.48, 0.72, 1.44))
		bit({ Color = PAL.IRON,   Size = Vector3.new(0.36, 0.3, 0.16) }, CFrame.new(sx * 0.48, 0.2, 1.46))
		bit({ Color = PAL.IRON_D, Size = Vector3.new(0.2, 0.14, 0.2) },  CFrame.new(sx * 0.48, 0.2, 1.5))
	end

	-- ---- a haul loop on top, and lash loops down the side. Both are what your eye reads as
	-- "pack" before it reads any of the panels: it is the bits you would grab hold of that make
	-- a bag look carried rather than modelled.
	bit({ Color = PAL.BARK_D, Size = Vector3.new(0.5, 0.16, 0.16) }, CFrame.new(0, 1.62, 0.60))
	bit({ Color = PAL.BARK_D, Size = Vector3.new(0.16, 0.30, 0.16) }, CFrame.new(-0.22, 1.50, 0.60))
	bit({ Color = PAL.BARK_D, Size = Vector3.new(0.16, 0.30, 0.16) }, CFrame.new(0.22, 1.50, 0.60))
	for _, sy in ipairs({ 0.26, -0.34 }) do
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.14, 0.26, 0.30) }, CFrame.new(-0.96, sy, 1.30))
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.14, 0.26, 0.30) }, CFrame.new(0.96, sy, 1.30))
	end
	-- the buckle tongue, hanging below its keeper so the strap reads as done up
	bit({ Color = PAL.WOOD_L, Size = Vector3.new(0.22, 0.34, 0.1) }, CFrame.new(0, 0.02, 1.46))

	-- ---- bedroll slung under the frame, lashed on
	bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CHIP, Size = Vector3.new(2.05, 0.66, 0.66) },
		CFrame.new(0, -1.3, 0.98) * CFrame.Angles(0, 0, math.rad(90)))
	for _, sx in ipairs({ -0.62, 0.62 }) do
		bit({ Color = PAL.BARK_D, Size = Vector3.new(0.14, 0.72, 0.72) }, CFrame.new(sx, -1.3, 0.98))
	end
	-- end caps: a bare cylinder reads as pipe, capped it reads as a rolled blanket
	for _, sx in ipairs({ -1.02, 1.02 }) do
		bit({ Shape = Enum.PartType.Cylinder, Color = PAL.CANVAS_D, Size = Vector3.new(0.1, 0.7, 0.7) },
			CFrame.new(sx, -1.3, 0.98) * CFrame.Angles(0, 0, math.rad(90)))
	end

	-- ---- shoulder straps: over the shoulder and down the chest, not flat on the back
	for _, sx in ipairs({ -1, 1 }) do
		bit({ Color = PAL.BARK, Size = Vector3.new(0.34, 0.26, 1.5) },
			CFrame.new(sx * 0.6, 0.98, 0.34) * CFrame.Angles(math.rad(18), 0, 0))
		bit({ Color = PAL.BARK, Size = Vector3.new(0.34, 1.5, 0.24) },
			CFrame.new(sx * 0.62, 0.16, -0.52) * CFrame.Angles(math.rad(-9), 0, 0))
		bit({ Color = PAL.IRON, Size = Vector3.new(0.38, 0.2, 0.18) }, CFrame.new(sx * 0.62, -0.5, -0.58))
	end
	bit({ Color = PAL.BARK_D, Size = Vector3.new(1.3, 0.2, 0.16) }, CFrame.new(0, 0.3, -0.62))

	-- ---- what you are carrying, poking out of the rolled top. Each slot holds a log and a
	-- mushroom pre-built and shows whichever one that slot is holding, so nothing has to move.
	packSlots = {}
	for i = 1, 6 do
		local x    = -0.72 + (i - 1) * 0.29
		local lean = CFrame.Angles(math.rad(14), 0, math.rad((i - 3.5) * 4))
		local at   = CFrame.new(x, 1.55, 0.94) * lean
		packSlots[i] = {
			log  = bit({ Color = PAL.BARK,   Size = Vector3.new(0.36, 1.4, 0.36), Transparency = 1 },
				at * CFrame.new(0, 0.55, 0)),
			face = bit({ Color = PAL.WOOD_L, Size = Vector3.new(0.38, 0.12, 0.38), Transparency = 1 },
				at * CFrame.new(0, 1.29, 0)),
			cap  = bit({ Color = PAL.MALLOW, Size = Vector3.new(0.6, 0.5, 0.6), Transparency = 1 },
				at * CFrame.new(0, 0.72, 0)),
			stem = bit({ Color = PAL.CHIP,   Size = Vector3.new(0.24, 0.5, 0.24), Transparency = 1 },
				at * CFrame.new(0, 0.35, 0)),
		}
	end

	for _, d in ipairs(pack:GetDescendants()) do
		if d:IsA("BasePart") and d ~= body then
			local wc = Instance.new("WeldConstraint"); wc.Part0 = body; wc.Part1 = d; wc.Parent = body
		end
	end
	local w = Instance.new("Weld")
	w.Part0 = torso; w.Part1 = body
	w.C0 = BODY_CF
	w.Parent = body
	pack.PrimaryPart = body

	-- ---- THE CAMP HAT, matching the miner's on island 11: same rounded build, soft wide brim
	-- instead of a shell. Round because a hat has no flat faces on it -- the dome is a ball
	-- squashed on Y with its lower half hidden inside the head, brim and band are cylinders.
	local head = char:FindFirstChild("Head")
	if head then
		local hat = Instance.new("Model"); hat.Name = "CampHat"; hat.Parent = char
		local H, seat = fitHat(char, head, HAT_SCALE)
		tuckHair(char, head, seat, H, hidHair)
		local HAT_CF, hroot = CFrame.new(0, seat, 0), nil
		for i, q in ipairs({
			{ { Shape = Enum.PartType.Ball, Color = PAL.WOOD_D,
				Size = Vector3.new(1.32, 1.00, 1.32) * H }, CFrame.new() },
			{ { Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D,
				Size = Vector3.new(0.10, 2.00, 2.00) * H },
				CFrame.new(0, -0.30 * H, 0) * CFrame.Angles(0, 0, math.rad(90)) },
			{ { Shape = Enum.PartType.Cylinder, Color = PAL.BARK_D,
				Size = Vector3.new(0.24, 1.36, 1.36) * H },
				CFrame.new(0, -0.18 * H, 0) * CFrame.Angles(0, 0, math.rad(90)) },
			{ { Color = PAL.CANVAS, Size = Vector3.new(0.28, 0.15, 0.15) * H },
				CFrame.new(0.60 * H, -0.16 * H, 0.12 * H) },
		}) do
			local props = q[1]
			props.Anchored = false; props.CanCollide = false; props.CanQuery = false
			props.Massless = true; props.Parent = hat
			local pt = mk(props)
			pt.CFrame = head.CFrame * HAT_CF * q[2]
			if i == 1 then hroot = pt end
		end
		for _, d in ipairs(hat:GetChildren()) do
			if d:IsA("BasePart") and d ~= hroot then
				local wc = Instance.new("WeldConstraint"); wc.Part0 = hroot; wc.Part1 = d; wc.Parent = hroot
			end
		end
		local hw = Instance.new("Weld")
		hw.Part0 = head; hw.Part1 = hroot; hw.C0 = HAT_CF; hw.Parent = hroot
		hat.PrimaryPart = hroot
	end

	refreshPack()
	print(("[Smores] backpack + camp hat on -- hat fitted at %.2f scale"):format(HAT_SCALE))
end

local function buildLogProp()
	local m = Instance.new("Model"); m.Name = "PineLog"; m.Parent = camp
	local body = mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK,
	                  Size = Vector3.new(3.0, 0.9, 0.9), CFrame = CFrame.new(), Parent = m })
	for _, e in ipairs({ -1, 1 }) do
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_L,
		     Size = Vector3.new(0.12, 0.92, 0.92),
		     CFrame = CFrame.new(e * 1.5, 0, 0), Parent = m })
	end
	m.PrimaryPart = body; m.WorldPivot = CFrame.new()
	return m
end

local function pickUp(kind)
	if #carried >= CARRY_MAX then return false end
	table.insert(carried, { kind = kind })
	if kind == "log" then logsHeld += 1 else shroomsHeld += 1 end
	refreshPack()
	if refreshBanner then refreshBanner() end
	return true
end

local function dropOne(kind)
	for i = 1, #carried do
		if carried[i].kind == kind then
			table.remove(carried, i)
			refreshPack()
			return true
		end
	end
	return false
end

local function dropAll(kind)
	for i = #carried, 1, -1 do
		if carried[i].kind == kind then table.remove(carried, i) end
	end
	refreshPack()
end

-- a respawn drops the weld with the old character, so put it back on
player.CharacterAdded:Connect(function()
	pack = nil; packSlots = {}
	task.delay(1.6, function() if step >= 1 then buildBackpack() end end)
end)

-- ============================================================================
-- OBJECTIVE BANNER
-- ============================================================================
local objGui = Instance.new("ScreenGui")
objGui.Name = "SmoresObjective"; objGui.ResetOnSpawn = false; objGui.DisplayOrder = 7
objGui.Parent = PlayerGui
local objFrame = Instance.new("Frame")
objFrame.AnchorPoint = Vector2.new(0.5, 0); objFrame.Position = UDim2.new(0.5, 0, 0, 12)
objFrame.Size = UDim2.new(0, 560, 0, 52); objFrame.BackgroundColor3 = PAL.PANEL
objFrame.Visible = false; objFrame.Parent = objGui
do
	Instance.new("UICorner", objFrame).CornerRadius = UDim.new(0, 14)
	local s = Instance.new("UIStroke"); s.Color = PAL.FLAME; s.Thickness = 3; s.Parent = objFrame
end
local objLabel = Instance.new("TextLabel")
objLabel.BackgroundTransparency = 1; objLabel.Size = UDim2.fromScale(1, 1)
objLabel.Font = Enum.Font.FredokaOne; objLabel.TextColor3 = Color3.fromRGB(255, 226, 180)
objLabel.TextScaled = true; objLabel.Parent = objFrame
do
	local sz = Instance.new("UITextSizeConstraint"); sz.MaxTextSize = 20; sz.Parent = objLabel
	local pd = Instance.new("UIPadding")
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = objLabel
end

refreshBanner = function()
	local txt
	if milling then
		objLabel.Text = ("\xF0\x9F\xAA\x9A Sawing a roasting stick...  %d strokes left"):format(millLeft)
		return
	end
	if step >= 5 then
		txt = "\xF0\x9F\x8F\x95 The campsite is complete. Enjoy the fire!"
	elseif step == 4 then
		txt = ("\xF0\x9F\x94\xA5 Take the mallows to the Candy Npc:  %d/%d sticks loaded")
			:format(loaded, #sticks)
	elseif step == 3 then
		txt = ("\xF0\x9F\x8D\x84 Gather Mallow Mushrooms:  %d/%d"):format(shroomsHeld, SHROOMS_NEEDED)
	elseif step == 2 then
		txt = ("\xF0\x9F\xAA\x93 Mill your logs, one at a time:  %d/%d"):format(logsMilled, LOGS_NEEDED)
	elseif step == 1 then
		txt = ("\xF0\x9F\x8C\xB2 Chop Pine Trees:  %d/%d"):format(logsMilled + logsHeld, LOGS_NEEDED)
	else
		txt = "\xF0\x9F\x8F\x95 Talk to the Candy Npc to start the campsite."
	end
	objLabel.Text = txt
end

task.spawn(function()
	while true do
		local vis = false
		if firePart then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			vis = hrp ~= nil and (hrp.Position - firePart.Position).Magnitude <= 420
		end
		objFrame.Visible = vis
		task.wait(0.4)
	end
end)

-- ============================================================================
-- THE CUTTING STATION -- built on the block named "mill"
-- ============================================================================
-- Kept deliberately plain: a bench, a blade, a cradle and an out-rack. A saw shed is a
-- handful of shapes doing an obvious job -- piling on detail is what makes a built prop
-- look generated rather than made.
local millBlade, millBladeCF, millAng, millCradle, millOut
local millCarriage, millCarryCF, millLever, millLeverCF, millDust
local millDrive, millDriveCF

-- Blade and flywheel sit on the SAME SHAFT, so one call turns both. They're Models rather than
-- bare parts because the teeth and spokes have to travel with them -- a smooth disc spinning
-- inside a static ring of teeth reads as broken.
local function spinMill(d)
	millAng = (millAng or 0) + d
	if millBlade and millBladeCF then millBlade:PivotTo(millBladeCF * CFrame.Angles(millAng, 0, 0)) end
	if millDrive and millDriveCF then millDrive:PivotTo(millDriveCF * CFrame.Angles(millAng * 0.28, 0, 0)) end
end

local function buildMill(part)
	local cf, sz = frameOf(part)
	local top = cf.Position.Y + sz.Y * 0.5
	local at  = CFrame.new(Vector3.new(cf.Position.X, top, cf.Position.Z))
		* (cf - cf.Position)                      -- keep the block's heading
	hideThing(part, true)
	local f = Instance.new("Folder"); f.Name = "Mill"; f.Parent = camp
	local function piece(props, where, parent)
		props.Parent = parent or f
		local p = mk(props); p.CFrame = where; return p
	end

	-- ---- BENCH: long enough for a log to ride the whole way through
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(17, 0.7, 4.6), CanCollide = true, CastShadow = true },
		at * CFrame.new(0, 2.55, 0))
	piece({ Color = PAL.WOOD, Size = Vector3.new(16.4, 0.14, 4.2) }, at * CFrame.new(0, 2.92, 0))
	for _, s in ipairs({ -1, 1 }) do
		for _, e in ipairs({ -1, 1 }) do
			piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.6, 2.2, 0.6), CanCollide = true },
				at * CFrame.new(s * 7.4, 1.1, e * 1.8))
		end
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.4, 0.4, 3.6) },   -- cross brace
			at * CFrame.new(s * 7.4, 0.6, 0))
	end
	piece({ Color = PAL.IRON, Size = Vector3.new(15.6, 0.2, 0.8) }, at * CFrame.new(0, 3.05, 0))

	-- ---- THE BLADE, on a shaft with a flywheel behind it
	millBlade   = Instance.new("Model"); millBlade.Name = "Blade"; millBlade.Parent = f
	millBladeCF = at * CFrame.new(0, 5.1, 0) * CFrame.Angles(0, math.rad(90), 0)
	local disc = piece({ Shape = Enum.PartType.Cylinder, Color = PAL.STONE,
		Size = Vector3.new(0.24, 6.4, 6.4), Reflectance = 0.2 }, millBladeCF, millBlade)
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D, Size = Vector3.new(0.34, 1.3, 1.3) },
		millBladeCF, millBlade)
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		piece({ Color = PAL.STONE_D, Size = Vector3.new(0.26, 0.62, 0.5) },
			millBladeCF * CFrame.new(0, math.cos(a) * 3.3, math.sin(a) * 3.3) * CFrame.Angles(a, 0, 0),
			millBlade)
	end
	millBlade.PrimaryPart = disc
	millBlade.WorldPivot  = millBladeCF

	-- shaft back from the blade to a pulley, and from there the belt runs to the drive wheel.
	-- Two wheels one behind the other, plus brackets and a motor box, was most of why this end
	-- looked cluttered -- and only one of them was ever visible from where you stand.
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D, Size = Vector3.new(3.4, 0.42, 0.42) },
		at * CFrame.new(0, 5.1, -1.15) * CFrame.Angles(0, math.rad(90), 0))
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.6, 1.9, 1.9) },
		at * CFrame.new(0, 5.1, -2.3) * CFrame.Angles(0, math.rad(90), 0))

	-- blade guard: one hood over the top, not an arc of plates
	piece({ Color = PAL.IRON, Size = Vector3.new(1.1, 0.5, 6.2) },
		millBladeCF * CFrame.new(0, 3.55, 0))

	-- ---- SHELTER. The roof is laid as PLANK COURSES rather than one slab per side -- a single
	-- flat pitch is the thing that makes a built shelter look like a placeholder.
	for _, s in ipairs({ -1, 1 }) do
		for _, e in ipairs({ -1, 1 }) do
			piece({ Color = PAL.STONE_D, Size = Vector3.new(1.4, 0.7, 1.4), CanCollide = true },
				at * CFrame.new(s * 8.2, 0.35, e * 3.4))                    -- stone footing
			piece({ Color = PAL.WOOD, Size = Vector3.new(0.7, 9.0, 0.7), CanCollide = true, CastShadow = true },
				at * CFrame.new(s * 8.2, 5.0, e * 3.4))
		end
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.5, 0.5, 7.4) }, at * CFrame.new(s * 8.2, 9.4, 0))

		for i = 1, 2 do                                                     -- two courses a side
			local t = 0.25 + (i - 1) * 0.5
			piece({ Color = (i % 2 == 0) and PAL.WOOD or PAL.WOOD_D,
				Size = Vector3.new(5.6, 0.32, 5.0), CastShadow = true },
				at * CFrame.new(s * 8.8 * t, 11.6 - 2.2 * t, 0) * CFrame.Angles(0, 0, math.rad(-s * 14)))
		end
	end
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(18.4, 0.55, 1.0) }, at * CFrame.new(0, 11.85, 0))

	-- a lantern on the ridge, so the shed reads at night
	piece({ Color = PAL.IRON_D, Size = Vector3.new(0.14, 0.9, 0.14) }, at * CFrame.new(4.6, 11.2, 0))
	local lamp = piece({ Color = PAL.FLAME, Material = Enum.Material.Neon,
		Size = Vector3.new(0.6, 0.8, 0.6) }, at * CFrame.new(4.6, 10.5, 0))
	local lp = Instance.new("PointLight")
	lp.Color = PAL.FLAME; lp.Brightness = 1.6; lp.Range = 22; lp.Parent = lamp

	-- The cradle and out-rack frames are worked out HERE, before anything uses them: the
	-- carriage below is built around millCradle, and defining it further down left it nil.
	millCradle = at * CFrame.new(6.6, 3.6, 0)
	millOut    = at * CFrame.new(-6.6, 3.6, 0)

	-- ---- THE CARRIAGE. A log riding a bare rail looks like it is floating; a wheeled carriage
	-- underneath it explains the motion and gives the cut something to travel on.
	millCarryCF  = millCradle
	millCarriage = Instance.new("Model"); millCarriage.Name = "Carriage"; millCarriage.Parent = f
	local cbed = piece({ Color = PAL.WOOD_D, Size = Vector3.new(4.6, 0.42, 3.0) },
		millCradle * CFrame.new(0, -0.6, 0), millCarriage)
	for _, e in ipairs({ -1, 1 }) do
		piece({ Color = PAL.IRON, Size = Vector3.new(4.8, 0.2, 0.32) },
			millCradle * CFrame.new(0, -0.36, e * 1.35), millCarriage)
		for _, sx in ipairs({ -1, 1 }) do
			piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D,
				Size = Vector3.new(0.26, 0.9, 0.9) },
				millCradle * CFrame.new(sx * 1.8, -0.95, e * 1.3) * CFrame.Angles(0, math.rad(90), 0),
				millCarriage)
		end
	end
	millCarriage.PrimaryPart = cbed
	millCarriage.WorldPivot  = millCradle

	-- ---- the start lever, by the in-feed where you would stand
	millLeverCF = at * CFrame.new(7.4, 3.3, -2.6)
	millLever   = Instance.new("Model"); millLever.Name = "Lever"; millLever.Parent = f
	local lshaft = piece({ Color = PAL.IRON, Size = Vector3.new(0.26, 2.4, 0.26) },
		millLeverCF * CFrame.new(0, 1.2, 0), millLever)
	piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.46, 0.55, 0.46) },
		millLeverCF * CFrame.new(0, 2.4, 0), millLever)
	millLever.PrimaryPart = lshaft
	millLever.WorldPivot  = millLeverCF
	millLever:PivotTo(millLeverCF * CFrame.Angles(0, 0, math.rad(16)))
	piece({ Color = PAL.IRON_D, Size = Vector3.new(0.8, 0.5, 0.8) }, millLeverCF)

	piece({ Color = PAL.WOOD, Size = Vector3.new(3.0, 1.6, 2.4), CanCollide = true },
		at * CFrame.new(0, 0.8, 3.9))
	piece({ Color = PAL.CHIP, Size = Vector3.new(2.6, 0.4, 2.0) }, at * CFrame.new(0, 1.65, 3.9))
	do
		local dh = piece({ Transparency = 1, Size = Vector3.new(1, 1, 1) }, at * CFrame.new(0, 3.4, 1.4))
		millDust = Instance.new("ParticleEmitter")
		millDust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		millDust.Color = ColorSequence.new(PAL.CHIP)
		millDust.Lifetime = NumberRange.new(0.5, 1.0); millDust.Rate = 0
		millDust.Speed = NumberRange.new(2, 6); millDust.SpreadAngle = Vector2.new(30, 30)
		millDust.Size = NumberSequence.new(0.3); millDust.Acceleration = Vector3.new(0, -26, 0)
		millDust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1) })
		millDust.Parent = dh
	end

	-- ---- the in-cradle, the out-rack, a stack of logs and a heap of sawdust
	for _, s in ipairs({ -1, 1 }) do
		piece({ Color = PAL.WOOD, Size = Vector3.new(0.5, 1.3, 0.5) },
			at * CFrame.new(6.6, 3.4, s * 1.5) * CFrame.Angles(math.rad(s * 20), 0, 0))
	end
	piece({ Color = PAL.WOOD, Size = Vector3.new(3.6, 0.4, 4.0) }, at * CFrame.new(-6.6, 3.2, 0))
	for i = 1, 2 do
		piece({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK, Size = Vector3.new(4.4, 1.2, 1.2) },
			at * CFrame.new(9.6, 0.65 + (i - 1) * 1.05, ((i % 2) - 0.5) * 1.1)
				* CFrame.Angles(0, math.rad(90), 0))
	end
	piece({ Color = PAL.CHIP, Size = Vector3.new(3.4, 0.5, 3.0) },
		at * CFrame.new(-7.4, 0.25, 1.6) * CFrame.Angles(0, 0.5, 0))

	-- ---- THE DRIVE. A big spoked wheel outside the frame with a belt down to the shaft. The
	-- flywheel on its own never explained where the power was coming from; this does, and it
	-- gives the whole station something large and slow turning behind the fast little blade.
	millDrive   = Instance.new("Model"); millDrive.Name = "DriveWheel"; millDrive.Parent = f
	millDriveCF = at * CFrame.new(0, 4.4, -6.4) * CFrame.Angles(0, math.rad(90), 0)
	local dhub = piece({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_D,
		Size = Vector3.new(0.7, 1.6, 1.6) }, millDriveCF, millDrive)
	for i = 1, 6 do                                        -- rim laid as 6 flat segments
		local a = (i / 6) * math.pi * 2
		piece({ Color = PAL.WOOD, Size = Vector3.new(0.62, 0.6, 3.5) },
			millDriveCF * CFrame.new(0, math.cos(a) * 3.4, math.sin(a) * 3.4)
				* CFrame.Angles(a, 0, 0), millDrive)
	end
	for i = 1, 4 do                                        -- four spokes, not eight
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.42, 6.6, 0.34) },
			millDriveCF * CFrame.Angles((i / 4) * math.pi, 0, 0), millDrive)
	end
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON_D, Size = Vector3.new(0.9, 0.9, 0.9) },
		millDriveCF, millDrive)
	millDrive.PrimaryPart = dhub
	millDrive.WorldPivot  = millDriveCF

	for _, s in ipairs({ -1, 1 }) do                       -- the belt down to the shaft
		piece({ Color = PAL.BARK_D, Size = Vector3.new(0.2, 4.3, 0.34) },
			at * CFrame.new(s * 0.9, 4.75, -4.35) * CFrame.Angles(math.rad(9), 0, 0))
	end
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.55, 5.4, 0.55), CanCollide = true },
		at * CFrame.new(0, 2.2, -6.4))

	-- the drop-off prompt
	local hit = mk({ Transparency = 1, CanQuery = true, Size = Vector3.new(11, 11, 9),
	                 CFrame = at * CFrame.new(0, 4.5, 0), Parent = f })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MillPrompt"; prompt.ActionText = "Load the Mill"
	prompt.ObjectText = "Lumber Mill"; prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14; prompt.RequiresLineOfSight = false
	prompt.Enabled = false; prompt.Parent = hit
	return prompt, at
end

-- The 'stand' part is the operator's deck -- where you stand to work the mill. It gets a
-- planked platform, a rail on three sides so you are not just on a floating board, steps up
-- to it, and a rack for the tools you are not holding.
local function buildStand(part)
	local cf, sz = frameOf(part)
	local at = CFrame.new(Vector3.new(cf.Position.X, cf.Position.Y + sz.Y * 0.5, cf.Position.Z))
		* (cf - cf.Position)
	hideThing(part, true)
	local f = Instance.new("Folder"); f.Name = "MillStand"; f.Parent = camp
	local function piece(props, where)
		props.Parent = f
		local p = mk(props); p.CFrame = where; return p
	end

	-- planked deck, laid as separate boards on two stepped tones
	for i = 1, 7 do
		piece({ Color = (i % 2 == 0) and PAL.WOOD or PAL.WOOD_D,
			Size = Vector3.new(6.4, 0.28, 0.82), CanCollide = true, CastShadow = true },
			at * CFrame.new(0, 1.7, -2.6 + (i - 1) * 0.88))
	end
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(6.6, 0.22, 6.4) }, at * CFrame.new(0, 1.5, 0))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz2 in ipairs({ -1, 1 }) do
			piece({ Color = PAL.WOOD_D, Size = Vector3.new(0.5, 1.6, 0.5), CanCollide = true },
				at * CFrame.new(sx * 2.9, 0.8, sz2 * 2.8))
			piece({ Color = PAL.STONE_D, Size = Vector3.new(0.9, 0.36, 0.9), CanCollide = true },
				at * CFrame.new(sx * 2.9, 0.18, sz2 * 2.8))
		end
	end

	-- rail on three sides, open at the front where you step up
	local posts = { { -2.9, -2.8 }, { 2.9, -2.8 }, { -2.9, 2.8 }, { 2.9, 2.8 }, { 0, 2.8 } }
	for _, q in ipairs(posts) do
		piece({ Color = PAL.WOOD, Size = Vector3.new(0.32, 2.2, 0.32), CanCollide = true },
			at * CFrame.new(q[1], 2.9, q[2]))
	end
	piece({ Color = PAL.WOOD_L, Size = Vector3.new(6.2, 0.24, 0.24) }, at * CFrame.new(0, 3.9, 2.8))
	piece({ Color = PAL.WOOD_L, Size = Vector3.new(6.2, 0.18, 0.18) }, at * CFrame.new(0, 3.2, 2.8))
	for _, sx in ipairs({ -1, 1 }) do
		piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.24, 0.24, 5.8) },
			at * CFrame.new(sx * 2.9, 3.9, 0))
		piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.18, 0.18, 5.8) },
			at * CFrame.new(sx * 2.9, 3.2, 0))
	end

	-- steps up the front
	for i = 1, 3 do
		piece({ Color = PAL.WOOD_D, Size = Vector3.new(3.0, 0.3, 0.9), CanCollide = true },
			at * CFrame.new(0, 0.42 + (i - 1) * 0.44, -3.1 - (i - 1) * 0.85))
	end

	-- a rack on the back rail: spare handles, a mug, a lantern on a hook
	piece({ Color = PAL.WOOD_D, Size = Vector3.new(2.6, 0.3, 0.5) }, at * CFrame.new(-1.4, 4.2, 2.9))
	for i = 1, 3 do
		piece({ Color = PAL.WOOD_L, Size = Vector3.new(0.16, 1.2, 0.16) },
			at * CFrame.new(-2.2 + (i - 1) * 0.5, 4.9, 2.9) * CFrame.Angles(0, 0, math.rad((i - 2) * 7)))
	end
	piece({ Shape = Enum.PartType.Cylinder, Color = PAL.IRON, Size = Vector3.new(0.4, 0.6, 0.6) },
		at * CFrame.new(-0.4, 4.5, 2.9) * CFrame.Angles(0, math.rad(90), 0))
	piece({ Color = PAL.IRON_D, Size = Vector3.new(0.16, 0.7, 0.16) }, at * CFrame.new(2.3, 4.6, 2.9))
	local ln = piece({ Color = PAL.FLAME, Material = Enum.Material.Neon,
		Size = Vector3.new(0.46, 0.62, 0.46) }, at * CFrame.new(2.3, 4.05, 2.9))
	local lp = Instance.new("PointLight")
	lp.Color = PAL.FLAME; lp.Brightness = 1.4; lp.Range = 20; lp.Parent = ln

	print("[Smores] operator's stand built")
end

local function sawChips(at)
	local host = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = at, Parent = camp })
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(PAL.CHIP, PAL.WOOD)
	em.Lifetime = NumberRange.new(0.35, 0.8); em.Rate = 0
	em.Speed = NumberRange.new(9, 20); em.SpreadAngle = Vector2.new(38, 38)
	em.Size = NumberSequence.new(0.35); em.Acceleration = Vector3.new(0, -42, 0)
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1),
	                                       NumberSequenceKeypoint.new(1, 1) })
	em.Parent = host
	return em, host
end

-- ============================================================================
-- MINI-GAMES -- the bit you actually play
-- ============================================================================
-- One HUD serves both jobs, because they are the same widget underneath: a track, a needle
-- running along it, a target band and a fill showing how far through you are. Sawing asks you
-- to tap the needle inside the band; pulling a mushroom asks you to hold. Building it twice
-- would have meant two sets of tuning to keep in step.
--
-- Input goes through a full-screen invisible button rather than UserInputService, so a tap
-- meant for the mini-game cannot also swing the axe, and it works on touch without a second
-- code path.
local mgGui = Instance.new("ScreenGui")
mgGui.Name = "SmoresMiniGame"; mgGui.ResetOnSpawn = false; mgGui.DisplayOrder = 9
mgGui.IgnoreGuiInset = true; mgGui.Enabled = false; mgGui.Parent = PlayerGui

local mgCatch = Instance.new("TextButton")
mgCatch.Size = UDim2.fromScale(1, 1); mgCatch.BackgroundTransparency = 1
mgCatch.Text = ""; mgCatch.AutoButtonColor = false; mgCatch.ZIndex = 1
mgCatch.Parent = mgGui

local mgPanel = Instance.new("Frame")
mgPanel.Size = UDim2.new(0, 540, 0, 152)
mgPanel.Position = UDim2.new(0.5, -270, 0.74, 0)
mgPanel.BackgroundColor3 = PAL.PANEL; mgPanel.BackgroundTransparency = 0.12
mgPanel.BorderSizePixel = 0; mgPanel.ZIndex = 2; mgPanel.Parent = mgGui
Instance.new("UICorner", mgPanel).CornerRadius = UDim.new(0, 16)
local mgStroke = Instance.new("UIStroke")
mgStroke.Color = PAL.FLAME; mgStroke.Thickness = 3; mgStroke.Transparency = 0.15
mgStroke.Parent = mgPanel

local mgTitle = Instance.new("TextLabel")
mgTitle.Size = UDim2.new(1, -24, 0, 32); mgTitle.Position = UDim2.new(0, 12, 0, 10)
mgTitle.BackgroundTransparency = 1; mgTitle.Font = Enum.Font.GothamBlack
mgTitle.TextSize = 22; mgTitle.TextColor3 = Color3.fromRGB(255, 246, 232)
mgTitle.TextXAlignment = Enum.TextXAlignment.Left; mgTitle.ZIndex = 3
mgTitle.Text = ""; mgTitle.Parent = mgPanel

local mgCount = Instance.new("TextLabel")
mgCount.Size = UDim2.new(0, 120, 0, 32); mgCount.Position = UDim2.new(1, -132, 0, 10)
mgCount.BackgroundTransparency = 1; mgCount.Font = Enum.Font.GothamBlack
mgCount.TextSize = 22; mgCount.TextColor3 = PAL.FLAME
mgCount.TextXAlignment = Enum.TextXAlignment.Right; mgCount.ZIndex = 3
mgCount.Text = ""; mgCount.Parent = mgPanel

local mgTrack = Instance.new("Frame")
mgTrack.Size = UDim2.new(1, -32, 0, 44); mgTrack.Position = UDim2.new(0, 16, 0, 52)
mgTrack.BackgroundColor3 = Color3.fromRGB(22, 20, 17); mgTrack.BorderSizePixel = 0
mgTrack.ClipsDescendants = true; mgTrack.ZIndex = 3; mgTrack.Parent = mgPanel
Instance.new("UICorner", mgTrack).CornerRadius = UDim.new(0, 10)

local mgZone = Instance.new("Frame")
mgZone.Size = UDim2.new(0.2, 0, 1, 0); mgZone.Position = UDim2.new(0.4, 0, 0, 0)
mgZone.BackgroundColor3 = Color3.fromRGB(92, 196, 96); mgZone.BackgroundTransparency = 0.25
mgZone.BorderSizePixel = 0; mgZone.ZIndex = 4; mgZone.Parent = mgTrack
Instance.new("UICorner", mgZone).CornerRadius = UDim.new(0, 8)

local mgFill = Instance.new("Frame")
mgFill.Size = UDim2.new(0, 0, 1, 0); mgFill.BackgroundColor3 = PAL.FLAME
mgFill.BackgroundTransparency = 0.55; mgFill.BorderSizePixel = 0
mgFill.ZIndex = 5; mgFill.Parent = mgTrack

local mgNeedle = Instance.new("Frame")
mgNeedle.Size = UDim2.new(0, 6, 1, 0); mgNeedle.BackgroundColor3 = Color3.fromRGB(255, 250, 240)
mgNeedle.BorderSizePixel = 0; mgNeedle.ZIndex = 6; mgNeedle.Parent = mgTrack

local mgHint = Instance.new("TextLabel")
mgHint.Size = UDim2.new(1, -32, 0, 26); mgHint.Position = UDim2.new(0, 16, 0, 106)
mgHint.BackgroundTransparency = 1; mgHint.Font = Enum.Font.GothamMedium
mgHint.TextSize = 16; mgHint.TextColor3 = Color3.fromRGB(206, 198, 186)
mgHint.TextXAlignment = Enum.TextXAlignment.Left; mgHint.ZIndex = 3
mgHint.Text = ""; mgHint.Parent = mgPanel

local mgBusy = false

local function mgFlash(good)
	mgStroke.Color = good and Color3.fromRGB(120, 220, 120) or Color3.fromRGB(224, 76, 60)
	mgPanel.Size = UDim2.new(0, 552, 0, 156)
	tween(mgPanel, 0.16, { Size = UDim2.new(0, 540, 0, 152) })
	task.delay(0.18, function() mgStroke.Color = PAL.FLAME end)
end

local function mgOpen(title, hint, showZone)
	mgZone.Visible = showZone
	mgTitle.Text = title; mgHint.Text = hint; mgCount.Text = ""
	mgFill.Size = UDim2.new(0, 0, 1, 0)
	mgGui.Enabled = true
	mgPanel.Position = UDim2.new(0.5, -270, 0.82, 0)
	tween(mgPanel, 0.22, { Position = UDim2.new(0.5, -270, 0.74, 0) }, Enum.EasingStyle.Back)
end

local function mgClose()
	tween(mgPanel, 0.18, { Position = UDim2.new(0.5, -270, 0.84, 0) })
	task.delay(0.2, function() mgGui.Enabled = false end)
end

-- SAWING. The needle runs the track and you tap it inside the band. Every landed stroke
-- speeds it up and narrows the band, so the last cut is the hard one -- otherwise it is the
-- same tap eight times over and there is nothing to get better at.
local function playSaw(strokes, onStroke)
	if mgBusy then return false end
	mgBusy = true
	mgOpen("SAW THE LOG", "Tap when the blade is inside the green", true)

	local hit, pos, dir, speed = 0, 0, 1, 0.55
	local zc, zw = 0.5, 0.24
	local tapped = false
	local conn = mgCatch.MouseButton1Down:Connect(function() tapped = true end)

	local function drawZone()
		mgZone.Position = UDim2.new(zc - zw * 0.5, 0, 0, 0)
		mgZone.Size     = UDim2.new(zw, 0, 1, 0)
	end
	drawZone()

	while hit < strokes do
		local dt = math.min(task.wait(), 0.05)
		pos += dir * speed * dt
		if pos >= 1 then pos, dir = 1, -1 elseif pos <= 0 then pos, dir = 0, 1 end
		mgNeedle.Position = UDim2.new(pos, -3, 0, 0)
		mgCount.Text = ("%d / %d"):format(hit, strokes)

		if tapped then
			tapped = false
			if math.abs(pos - zc) <= zw * 0.5 then
				hit += 1
				speed = math.min(1.75, speed + 0.14)
				zw    = math.max(0.10, zw - 0.017)
				zc    = 0.14 + math.random() * 0.72
				mgFlash(true)
				playSound(SOUND_SAW, 0.5)
				if onStroke then onStroke(hit / strokes) end
			else
				speed = math.max(0.45, speed - 0.07)   -- a miss costs you time, not progress
				mgFlash(false)
			end
			drawZone()
			tween(mgFill, 0.15, { Size = UDim2.new(hit / strokes, 0, 1, 0) })
		end
	end

	mgCount.Text = ("%d / %d"):format(strokes, strokes)
	conn:Disconnect()
	task.wait(0.25)
	mgClose()
	mgBusy = false
	return true
end

-- PULLING. Hold and it comes; let go and it slips back. Quick and forgiving -- this is a
-- mushroom, not a tree.
local function playPull(secs)
	if mgBusy then return false end
	mgBusy = true
	mgOpen("PULL THE MUSHROOM", "Hold anywhere until the cap comes free", false)

	local down, v = false, 0
	local c1 = mgCatch.MouseButton1Down:Connect(function() down = true end)
	local c2 = mgCatch.MouseButton1Up:Connect(function() down = false end)
	local c3 = mgCatch.MouseLeave:Connect(function() down = false end)

	while v < 1 do
		local dt = math.min(task.wait(), 0.05)
		v = math.clamp(v + (down and dt / secs or -dt / (secs * 0.7)), 0, 1)
		-- the wobble is resistance: the cap gives in little jerks rather than sliding out
		local shown = math.clamp(v + (down and math.sin(os.clock() * 16) * 0.018 or 0), 0, 1)
		mgFill.Size = UDim2.new(shown, 0, 1, 0)
		mgNeedle.Position = UDim2.new(shown, -3, 0, 0)
		mgCount.Text = ("%d%%"):format(math.floor(v * 100))
		mgFill.BackgroundColor3 = PAL.FLAME:Lerp(Color3.fromRGB(120, 220, 120), v)
	end

	mgFlash(true)
	c1:Disconnect(); c2:Disconnect(); c3:Disconnect()
	task.wait(0.18)
	mgClose()
	mgBusy = false
	return true
end

-- ============================================================================
-- ROASTING STICKS -- your three 'Stickthatgoesup' parts
-- ============================================================================
-- These are YOUR parts, placed where you want them. The quest does not build sticks any more;
-- it hides the ones you placed and raises them out of the ground one per cut at the mill.
local function wireStick(p)
	for _, s in ipairs(sticks) do if s.part == p then return end end
	local home = p:IsA("Model") and p:GetPivot() or p.CFrame
	hideThing(p, true)
	sticks[#sticks + 1] = { part = p, home = home }
	print(("[Smores] stick %d wired and hidden"):format(#sticks))
end

-- Each stick owns the marshmallow nearest it, one to one. Done as a pass rather than at wire
-- time because sticks and marshmallows stream in independently -- whichever arrives second
-- would otherwise find nothing to pair with.
local function pairSticks()
	local used = {}
	for _, st in ipairs(sticks) do if st.marsh then used[st.marsh] = true end end
	for _, st in ipairs(sticks) do
		if not st.marsh then
			local best, bd
			for _, mm in ipairs(marshParts) do
				if not used[mm] then
					local d = (select(1, frameOf(mm)).Position - st.home.Position).Magnitude
					if not bd or d < bd then best, bd = mm, d end
				end
			end
			if best then st.marsh = best; used[best] = true end
		end
	end
end

local function raiseStick(i)
	local st = sticks[i]
	if not st or st.up then return end
	st.up = true
	local function put(cf)
		if st.part:IsA("Model") then st.part:PivotTo(cf) else st.part.CFrame = cf end
	end
	put(st.home * CFrame.new(0, -7, 0))
	hideThing(st.part, false)
	playSound(SOUND_POP, 0.6)
	task.spawn(function()
		for k = 1, 22 do
			put(st.home * CFrame.new(0, -7 * (1 - k / 22), 0))
			task.wait(0.03)
		end
		for k = 1, 7 do                                  -- a small settle as it plants
			put(st.home * CFrame.new(0, math.sin(k / 7 * math.pi) * 0.22, 0))
			task.wait(0.03)
		end
		put(st.home)
	end)
end

-- ============================================================================
-- THE FIRE
-- ============================================================================
-- A flame is not one shape that scales -- it is a lot of tongues of different heights, each
-- leaning and twisting on its own clock, over a bed of coals that outlives them. So this is
-- built as three tiers: a pale core, an orange middle, and short red tongues around the rim,
-- fifteen in all, each made of three stacked blocks that narrow as they rise. Animating the
-- stack from a common spine is what makes them taper and curl rather than just wobble.
local fireBits, fireCoals, fireLogs = {}, {}, {}
local fireLight, fireGlow, fireEmber, fireSmoke
local fireO, fireTop, fireHS
local fireCore, fireLight2
local fireLicks = {}
local fireLevel = 0                    -- 0..1, how established the fire is
local fireLit   = false

local function igniteFire()
	if fireLit then return end
	fireLit = true

	local cf, sz = frameOf(fireModel or firePart)
	local O   = cf.Position
	-- The flame sits FIRE_DROP below the top of the model bounding box. The box is the whole
	-- campfire, and its top is wherever the tallest log ends -- which is well above the wood
	-- the fire actually burns on, so unshifted the flame floats over the pile.
	local top = O.Y + sz.Y * 0.5 - FIRE_DROP
	-- everything below is sized off the pile: a fire built to fixed numbers either floats in
	-- the middle of a big campfire or swallows a small one
	local R  = math.clamp(math.max(sz.X, sz.Z) * 0.34, 1.4, 5.0)
	local HS = math.clamp(R / 1.5, 0.9, 2.4) * FLAME_SCALE
	local FR = R * FLAME_SCALE * FLAME_WIDTH   -- spread is its own dial, so the fire can be
	                                           -- tall and narrow rather than tall and fanned
	local f = Instance.new("Folder"); f.Name = "Fire"; f.Parent = camp

	-- ---- the bed of coals. These light BEFORE the flames and stay lit after, which is what
	-- sells it as a fire that was built rather than one that was switched on.
	for i = 1, 11 do
		local a = (i / 11) * math.pi * 2 + (i % 3) * 0.4
		local r = (0.3 + (i % 4) * 0.23) * R
		local c = mk({ Color = PAL.BARK_D, Material = Enum.Material.SmoothPlastic,
			Size = Vector3.new((0.55 + (i % 3) * 0.18) * HS, 0.28 * HS, (0.5 + (i % 2) * 0.2) * HS),
			CFrame = CFrame.new(O.X + math.cos(a) * r, top - 0.1, O.Z + math.sin(a) * r)
				* CFrame.Angles(0, a + 0.3, 0),
			Parent = f })
		table.insert(fireCoals, { p = c, phase = math.random() * 6.28 })
	end

	-- ---- THE WOODPILE ITSELF. Coals sitting next to untouched brown logs is what gave the
	-- old fire away. Every part of your campfire model chars as it burns, and how red it goes
	-- is set by how close it is to the core -- so the middle of the pile runs hot and the ends
	-- of the logs stay wood, which is what a real fire looks like.
	do
		local host = fireModel or firePart
		local list = {}
		if host:IsA("BasePart") then
			list = { host }
		else
			for _, d in ipairs(host:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(list, d) end
			end
		end
		local reach = math.max(2.6, math.max(sz.X, sz.Z) * 0.62)
		for _, p in ipairs(list) do
			local dv   = Vector3.new(p.Position.X - O.X, 0, p.Position.Z - O.Z).Magnitude
			local fall = math.clamp(1 - dv / reach, 0, 1)
			-- EVERY log runs hot -- this is the fire, not something stood near it. The falloff
			-- decides how hot, not whether: the core goes incandescent, the ends stay dull red.
			table.insert(fireLogs, { p = p, base = p.Color, phase = math.random() * 6.28,
				glow = 0.42 + 0.58 * fall ^ 1.15 })
		end
		print(("[Smores] %d log part(s) in the fire will char and glow"):format(#fireLogs))

		-- WISPS OFF THE WOOD. The tall column of smoke rises from above the flames, which is
		-- right, but nothing was coming off the wood itself -- and smoke curling straight off
		-- a glowing log is most of what makes it look like it is actually burning.
		table.sort(fireLogs, function(a, b) return a.glow > b.glow end)
		for i = 1, math.min(5, #fireLogs) do
			local l = fireLogs[i]
			if l.glow > 0.12 then
				local w = Instance.new("ParticleEmitter")
				w.Texture = "rbxasset://textures/particles/smoke_main.dds"
				w.Color = ColorSequence.new(PAL.SMOKE, Color3.fromRGB(168, 164, 158))
				w.Lifetime = NumberRange.new(1.4, 2.8)
				w.Rate = 2 + l.glow * 4
				w.Speed = NumberRange.new(1.2, 3.4)
				w.SpreadAngle = Vector2.new(26, 26)
				w.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35),
					NumberSequenceKeypoint.new(0.4, 1.5), NumberSequenceKeypoint.new(1, 3.2) })
				w.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.15, 0.74), NumberSequenceKeypoint.new(1, 1) })
				w.Acceleration = Vector3.new(0.5 + i * 0.15, 3.4, -0.2)
				w.RotSpeed = NumberRange.new(-30, 30)
				w.EmissionDirection = Enum.NormalId.Top
				w.Parent = l.p
			end
		end
	end

	-- ---- ground glow: a wide, dim neon slab that throws the fire's colour onto the dirt
	fireGlow = mk({ Color = PAL.EMBER, Material = Enum.Material.Neon, Transparency = 1,
		Size = Vector3.new(R * 4.6, 0.08, R * 4.6),
		CFrame = CFrame.new(O.X, top - 0.28, O.Z), Parent = f })

	-- ---- the tongues, three tiers
	local WS = math.min(1.7 * FLAME_SCALE, HS) * FLAME_WIDTH
	local TIERS = {
		{ n = 5, r0 = 0.00 * FR, r1 = 0.30 * FR, h = 3.1 * HS, w = 0.60 * WS, col = PAL.FLAME_H },
		{ n = 7, r0 = 0.30 * FR, r1 = 0.66 * FR, h = 2.3 * HS, w = 0.72 * WS, col = PAL.FLAME },
		{ n = 6, r0 = 0.66 * FR, r1 = 1.00 * FR, h = 1.5 * HS, w = 0.80 * WS, col = PAL.EMBER },
	}
	fireO, fireTop, fireHS = O, top, HS

	-- THE BASE IS THE BRIGHTEST PART OF A FIRE and it was missing entirely: right where the
	-- flame meets the wood there is a pool of white heat the individual tongues never make,
	-- because each one is thin there. One wide, flat, very bright disc supplies it.
	fireCore = mk({ Shape = Enum.PartType.Cylinder, Color = PAL.FLAME_H,
		Material = Enum.Material.Neon, Transparency = 1,
		Size = Vector3.new(0.5 * HS, FR * 1.9, FR * 1.9),
		CFrame = CFrame.new(O.X, top + 0.25 * HS, O.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = f })

	-- LICKS: shards that break off a tip, rise on their own and burn out. A fire is not a
	-- closed shape -- bits of it detach constantly, and nothing else here does that.
	for _ = 1, 9 do
		local p = mk({ Color = PAL.FLAME, Material = Enum.Material.Neon, Transparency = 1,
			Size = Vector3.new(0.3, 0.5, 0.3), CFrame = CFrame.new(O.X, top, O.Z), Parent = f })
		table.insert(fireLicks, { p = p, life = math.random(), rate = 0.65 + math.random() * 0.7 })
	end
	for ti, T in ipairs(TIERS) do
		for i = 1, T.n do
			local a = (i / T.n) * math.pi * 2 + ti * 0.7
			local r = T.r0 + ((i % 3) / 2) * (T.r1 - T.r0)
			local b = { segs = {}, h = T.h * (0.82 + (i % 3) * 0.12), w = T.w,
			            phase = math.random() * 6.28, surge = 0, tier = ti,
			            ang = a, rad = r,
			            life = math.random(), rate = 0.42 + math.random() * 0.36 }
			b.base = CFrame.new(O.X + math.cos(a) * r, top, O.Z + math.sin(a) * r)
			b.out  = Vector3.new(math.cos(a), 0, math.sin(a))
			-- COLOUR RUNS UP THE TONGUE, not across the tier: white-hot at the wood, orange
			-- through the middle, dull red at the tip, fading out as it goes. A tongue that is
			-- one flat colour top to bottom is the single biggest tell in a stylised fire.
			for k = 1, 3 do
				b.segs[k] = mk({ Material = Enum.Material.Neon,
					Color = (k == 1) and PAL.FLAME_H or ((k == 2) and T.col or PAL.EMBER),
					Transparency = 0.04 + (k - 1) * 0.19 + ti * 0.03,
					Size = Vector3.new(0.1, 0.1, 0.1), CFrame = b.base, Parent = f })
			end
			table.insert(fireBits, b)
		end
	end

	-- ---- light. Range and brightness both flicker, because a light that only dims reads as
	-- a lamp on a dimmer rather than a fire.
	fireLight = Instance.new("PointLight")
	fireLight.Color = PAL.FLAME; fireLight.Brightness = 0; fireLight.Range = 12
	fireLight.Shadows = true
	fireLight.Parent = fireGlow

	-- a second light, low and red, so the ground stays lit between flares. One light doing
	-- both jobs has to choose, and it always chose the flames.
	fireLight2 = Instance.new("PointLight")
	fireLight2.Color = PAL.EMBER; fireLight2.Brightness = 0; fireLight2.Range = 16
	fireLight2.Parent = fireGlow

	-- ---- smoke and embers
	local sh = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
	                CFrame = CFrame.new(O.X, top + 1.8 * HS, O.Z), Parent = f })
	local sm = Instance.new("ParticleEmitter")
	sm.Texture = "rbxasset://textures/particles/smoke_main.dds"
	sm.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, PAL.SMOKE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 148, 144)) })
	sm.Lifetime = NumberRange.new(3.4, 6.0); sm.Rate = 7
	sm.Speed = NumberRange.new(5, 11); sm.SpreadAngle = Vector2.new(18, 18)
	-- it keeps opening out the whole way up: smoke that stops growing reads as a column of
	-- fixed blobs rather than a plume
	sm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(0.35, 8), NumberSequenceKeypoint.new(1, 17) })
	sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.68), NumberSequenceKeypoint.new(1, 1) })
	sm.Acceleration = Vector3.new(0.7, 5, 0.2)
	sm.RotSpeed = NumberRange.new(-24, 24); sm.Parent = sh

	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(PAL.FLAME_H, PAL.EMBER)
	em.Lifetime = NumberRange.new(1.4, 3.0); em.Rate = 0
	em.Speed = NumberRange.new(5, 13); em.SpreadAngle = Vector2.new(46, 46)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(1, 0.08) })
	em.LightEmission = 1; em.Acceleration = Vector3.new(0.8, 3.2, 0)
	em.Drag = 1.4
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) })
	em.Parent = sh

	-- ash: dark flakes lifting off the pile, slower and heavier than the sparks. They read as
	-- the fire consuming something rather than just emitting light.
	local ash = Instance.new("ParticleEmitter")
	ash.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ash.Color = ColorSequence.new(Color3.fromRGB(56, 50, 46), Color3.fromRGB(120, 114, 108))
	ash.Lifetime = NumberRange.new(2.2, 4.0); ash.Rate = 5
	ash.Speed = NumberRange.new(3, 7); ash.SpreadAngle = Vector2.new(55, 55)
	ash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0.1) })
	ash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.75, 0.45), NumberSequenceKeypoint.new(1, 1) })
	ash.Acceleration = Vector3.new(0.4, 2.2, 0); ash.Drag = 2.5
	ash.RotSpeed = NumberRange.new(-90, 90); ash.Parent = sh

	fireEmber, fireSmoke = em, sm

	if SOUND_FIRE ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = SOUND_FIRE; s.Looped = true; s.Volume = 0
		s.RollOffMaxDistance = FIRE_RANGE; s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.Parent = sh
		pcall(function() s:Play() end)
		tween(s, 3, { Volume = FIRE_VOLUME })
	end

	-- ---- LIGHTING IT. Kindling smoulders and smokes, the coals come up, then it catches with
	-- a flare that overshoots and settles back. Everything arriving at once is the giveaway.
	task.spawn(function()
		sm.Rate = 24                                   -- damp smoke off the kindling first
		task.wait(1.1)

		for _, c in ipairs(fireCoals) do               -- the coals take
			tween(c.p, 1.6, { Color = PAL.EMBER })
			c.p.Material = Enum.Material.Neon
		end
		tween(fireGlow, 1.6, { Transparency = 0.86 })
		task.wait(0.7)

		playSound(SOUND_FIRE ~= "" and SOUND_FIRE or SOUND_POP, 0.5)
		em:Emit(70)                                    -- the catch
		sm.Rate = 14
		em.Rate = 14

		local t0 = os.clock()
		while true do
			local e = os.clock() - t0
			if e >= 3.4 then break end
			local u = e / 3.4
			-- overshoot then settle: it flares as it catches, then finds its level
			fireLevel = math.min(1.35, (1 - (1 - u) ^ 3) * 1.35) - math.max(0, (u - 0.55)) * 0.78
			task.wait()
		end
		fireLevel = 1
	end)

	-- ---- the marshmallows toast: white -> golden, slowly, once the fire is properly going
	task.delay(4.0, function()
		for i, st in ipairs(sticks) do
			task.delay(i * 1.1, function()
				if not st.marsh then return end
				local parts = {}
				if st.marsh:IsA("BasePart") then parts = { st.marsh }
				else
					for _, d in ipairs(st.marsh:GetDescendants()) do
						if d:IsA("BasePart") then table.insert(parts, d) end
					end
				end
				for _, p in ipairs(parts) do tween(p, 11, { Color = PAL.TOAST }) end
				local mp = parts[1]
				if mp then                              -- a little sizzle as it browns
					local sz = Instance.new("ParticleEmitter")
					sz.Texture = "rbxasset://textures/particles/smoke_main.dds"
					sz.Color = ColorSequence.new(Color3.fromRGB(220, 216, 210))
					sz.Lifetime = NumberRange.new(0.9, 1.8); sz.Rate = 3
					sz.Speed = NumberRange.new(1.4, 3); sz.SpreadAngle = Vector2.new(24, 24)
					sz.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3),
						NumberSequenceKeypoint.new(1, 1.5) })
					sz.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8),
						NumberSequenceKeypoint.new(1, 1) })
					sz.Acceleration = Vector3.new(0.3, 2.5, 0); sz.Parent = mp
				end
			end)
		end
	end)
end

-- Each tongue is animated off a spine: the three blocks ride up it, drifting further out and
-- narrowing as they go, while the whole tongue leans and twists. Randomly one surges -- a
-- flame licking up higher than the rest -- which is most of what stops it looking like a loop.
RunService.RenderStepped:Connect(function(dt)
	if #fireBits == 0 then return end
	dt = math.min(dt or 0.016, 0.05)
	local t  = os.clock()
	local lv = fireLevel
	local gust = 1 + math.sin(t * 0.7) * 0.1 + math.sin(t * 1.9 + 2) * 0.06
	-- one wind vector for the whole fire, turning slowly. Flames, smoke and embers all lean
	-- with it, which is what ties them together as one fire instead of three effects.
	local wind = Vector3.new(math.sin(t * 0.23) + math.sin(t * 0.61) * 0.4, 0,
	                         math.cos(t * 0.17) + math.cos(t * 0.53) * 0.4) * 0.3

	for _, b in ipairs(fireBits) do
		-- A TONGUE IS BORN, RISES AND PINCHES OUT, then starts again somewhere slightly else.
		-- Flames that only sway read as ribbons on a fan; the turnover is what makes it burn.
		b.life += dt * b.rate
		if b.life >= 1 then
			b.life -= 1
			b.phase = math.random() * 6.28
			b.rate  = 0.42 + math.random() * 0.36
			local a = b.ang + (math.random() - 0.5) * 0.9
			local r = b.rad * (0.7 + math.random() * 0.6)
			b.base  = CFrame.new(fireO.X + math.cos(a) * r, fireTop, fireO.Z + math.sin(a) * r)
			b.out   = Vector3.new(math.cos(a), 0, math.sin(a))
		end
		local env = math.sin(b.life * math.pi) ^ 0.55        -- quick to rise, slow to die

		if b.surge > 0 then
			b.surge = math.max(0, b.surge - 0.028)
		elseif math.random() < 0.004 then
			b.surge = 1
		end
		local H = b.h * lv * gust * env
			* (1 + math.sin(t * 5.2 + b.phase) * 0.1 + b.surge * 0.55)
		local twist = t * (0.9 + b.tier * 0.25) + b.phase

		for k = 1, 3 do
			local p  = b.segs[k]
			if p.Parent then
				local up = (k - 0.5) / 3 * H
				local dr = (k / 3) ^ 1.6                     -- drift grows toward the tip
				-- convection draws the tips INWARD over the core while the wind pushes them
				-- along: that inward pull is why a real fire tapers to a point
				local pull = (b.out * -0.44 + wind) * dr * (0.6 + b.surge * 0.4)
				local wob  = Vector3.new(math.sin(t * 3.4 + b.phase + k) * 0.14 * dr, up,
				                         math.cos(t * 2.8 + b.phase + k * 0.8) * 0.14 * dr)
				p.CFrame = b.base * CFrame.new(wob + pull) * CFrame.Angles(0, twist, 0)
				local w = b.w * lv * env * (1 - (k - 1) * 0.34)
				p.Size = Vector3.new(math.max(0.05, w), math.max(0.05, H / 3 * 1.12),
				                     math.max(0.05, w))
			end
		end
	end

	-- every so often the fire spits: a crack, a scatter of embers and a kick in the light
	if fireEmber and lv > 0.6 and math.random() < 0.008 then
		fireEmber:Emit(12 + math.random(14))
		if fireLight then fireLight.Brightness = fireLight.Brightness + 1.6 end
	end
	if fireSmoke then
		fireSmoke.Acceleration = Vector3.new(wind.X * 7 + 0.6, 5, wind.Z * 7)
	end

	-- licks break off a random tongue's base, rise, and burn out on their own clock
	for _, k in ipairs(fireLicks) do
		k.life += dt * k.rate
		if k.life >= 1 then
			k.life -= 1
			local b = fireBits[math.random(#fireBits)]
			k.from = b and b.base.Position or Vector3.new(fireO.X, fireTop, fireO.Z)
			k.h    = (2.0 + math.random() * 2.2) * (fireHS or 1)
			k.sw   = (math.random() - 0.5) * 1.5
		end
		if k.from and lv > 0.3 then
			local u  = k.life
			local sc = math.sin(u * math.pi) ^ 0.8
			k.p.Transparency = 1 - 0.86 * sc * math.min(1, lv)
			k.p.Size   = Vector3.new(0.32 * sc + 0.04, (0.5 + u * 0.8) * sc + 0.04, 0.32 * sc + 0.04)
			k.p.Color  = PAL.FLAME_H:Lerp(PAL.EMBER, u)
			k.p.CFrame = CFrame.new(k.from + Vector3.new(
				k.sw * u + wind.X * u * 2.4, u * k.h, k.sw * 0.6 * u + wind.Z * u * 2.4))
				* CFrame.Angles(0, u * 6, 0)
		else
			k.p.Transparency = 1
		end
	end

	-- the white-hot base holds steady: it comes up with the fire and then stays put
	if fireCore then
		fireCore.Transparency = math.clamp(1 - 0.72 * math.min(1, lv), 0.28, 1)
	end

	-- the woodpile: charred underneath, sitting at a steady red heat. Wood this hot does not
	-- flicker -- the flames above it do, and reading a pulse into the logs as well made the
	-- whole pile look like it was being switched on and off.
	for _, l in ipairs(fireLogs) do
		if l.p.Parent then
			-- the core logs go NEON once the fire is properly alight, which is the difference
			-- between a log painted red and a log that is actually glowing
			if not l.hot and lv > 0.5 and l.glow > 0.78 then
				l.hot = true
				l.p.Material = Enum.Material.Neon
			end
			local char = l.base:Lerp(Color3.fromRGB(32, 24, 20), 0.72 * math.min(1, lv))
			l.p.Color  = char:Lerp(l.hot and PAL.FLAME or PAL.EMBER,
				l.glow * 0.92 * math.min(1, lv))
		end
	end

	-- the coals hold a steady heat too; only how far they have come up varies, with the fire
	for _, c in ipairs(fireCoals) do
		if c.p.Parent then
			c.p.Color = PAL.BARK_D:Lerp(PAL.EMBER, 0.35 + 0.65 * math.min(1, lv))
		end
	end

	if fireLight then
		local fl = math.sin(t * 11) * 0.5 + math.sin(t * 4.3 + 1.7) * 0.8 + math.sin(t * 23) * 0.22
		fireLight.Brightness = math.max(0, (2.9 + fl) * lv)
		fireLight.Range      = 26 + fl * 3.5
		fireLight.Color      = PAL.EMBER:Lerp(PAL.FLAME_H, 0.45 + fl * 0.18)
	end
	if fireLight2 then
		fireLight2.Brightness = math.max(0, (1.9 + math.sin(t * 2.7) * 0.5) * lv)
		fireLight2.Range      = 15 + math.sin(t * 1.6) * 2
	end
	if fireGlow and fireGlow.Parent and lv > 0 then
		fireGlow.Transparency = math.clamp(0.84 - math.min(1, lv) * 0.12, 0.6, 0.95)
	end
end)

-- ============================================================================
-- THE NPC -- paged bubble on a Talk prompt, same pattern as island 1
-- ============================================================================
local function npcHeadOf(d)
	return (d:IsA("Model") and (d:FindFirstChild("Head") or d.PrimaryPart
		or d:FindFirstChildWhichIsA("BasePart", true)))
		or (d:IsA("BasePart") and d) or nil
end

local function findNPCHead()
	if not firePart then return nil end
	local best, bestD
	for _, d in ipairs(Workspace:GetDescendants()) do
		local match = false
		for _, w in ipairs(NPC_NAMES) do if norm(d.Name) == w then match = true; break end end
		if match then
			local h = npcHeadOf(d)
			if h then
				local dist = (h.Position - firePart.Position).Magnitude
				if dist <= NPC_MAX_DIST and (not bestD or dist < bestD) then best, bestD = h, dist end
			end
		end
	end
	return best
end

local function hideBubble(a)
	local prev = a:FindFirstChild("SpeechBubble"); if prev then prev:Destroy() end
end

function showBubble(a, text, persist, footer)
	hideBubble(a)
	local bb = Instance.new("BillboardGui")
	bb.Name = "SpeechBubble"; bb.Adornee = a; bb.Size = UDim2.new(0, 320, 0, 150)
	bb.StudsOffset = Vector3.new(0, 5.5, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 120
	local fr = Instance.new("Frame"); fr.Size = UDim2.fromScale(1, 1)
	fr.BackgroundColor3 = PAL.BUB_F; fr.BackgroundTransparency = 0.05; fr.BorderSizePixel = 0
	fr.Parent = bb
	Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = PAL.BUB_S; st.Thickness = 2
	st.Transparency = 0.4; st.Parent = fr
	local pd = Instance.new("UIPadding")
	pd.PaddingTop = UDim.new(0, 12); pd.PaddingBottom = UDim.new(0, 12)
	pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 14); pd.Parent = fr
	local lb = Instance.new("TextLabel")
	lb.Size = footer and UDim2.fromScale(1, 0.78) or UDim2.fromScale(1, 1)
	lb.BackgroundTransparency = 1; lb.Font = Enum.Font.FredokaOne; lb.Text = text
	lb.TextColor3 = PAL.BUB_T; lb.TextScaled = true; lb.TextWrapped = true; lb.Parent = fr
	local c1 = Instance.new("UITextSizeConstraint"); c1.MaxTextSize = 22; c1.Parent = lb
	if footer then
		local h = Instance.new("TextLabel")
		h.Size = UDim2.fromScale(1, 0.2); h.Position = UDim2.fromScale(0, 0.8)
		h.BackgroundTransparency = 1; h.Font = Enum.Font.FredokaOne; h.Text = footer
		h.TextColor3 = PAL.BUB_H; h.TextScaled = true; h.Parent = fr
		local c2 = Instance.new("UITextSizeConstraint"); c2.MaxTextSize = 14; c2.Parent = h
	end
	bb.Parent = a
	if not persist then
		task.delay(9, function()
			if bb and bb.Parent == a and bb.Name == "SpeechBubble" then bb:Destroy() end
		end)
	end
end

-- ============================================================================
-- GO
-- ============================================================================
-- WIRING -- prompts go on trees and mushrooms as they turn up
-- ============================================================================
local millPrompt
local treeList, shroomList = {}, {}

local function enableShroomPrompts(on)
	for _, s in ipairs(shroomList) do
		if s.prompt then s.prompt.Enabled = on end
	end
end

local function wireTree(tr)
	if tr:GetAttribute("SmoresWired") then return end
	local anchor = tr:IsA("BasePart") and tr or tr:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then return end                 -- still an empty shell; the sweep retries
	tr:SetAttribute("SmoresWired", true)
	-- NO PROMPT. Trees are registered and then hit by swinging the axe at them.
	table.insert(treeList, { model = tr, anchor = anchor, hits = 0, down = false })
end

-- THE CHOP POINT. Not shown -- there is no target to aim at, you just swing. It is worked out
-- once per tree and kept because two things still need it: the chips have to fly from somewhere,
-- the tree has to know which way to go over. Chosen on the side you are stood on, so both come
-- out right without you having to think about it.
local function trunkR(t, bs)
	return math.clamp(math.min(bs.X, bs.Z) * 0.13, 0.5, 2.2)
end

local function chopPoint(t)
	if t.markCF or t.down then return end
	local base = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
	local _, bs = frameOf(t.model)
	local footY = base.Position.Y - bs.Y * 0.5

	-- on the side you are stood on, at about chest height -- where you would actually cut
	local hrp  = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local face = Vector3.new(0, 0, 1)
	if hrp then
		local v = Vector3.new(hrp.Position.X - base.Position.X, 0, hrp.Position.Z - base.Position.Z)
		if v.Magnitude > 0.5 then face = v.Unit end
	end
	local rad = trunkR(t, bs)
	local mid = Vector3.new(base.Position.X, footY + 2.6, base.Position.Z)
	t.markCF = CFrame.lookAt(mid + face * rad, mid + face * 40)
	t.markF  = face
	t.rad    = rad
end

-- A hit throws chips off the trunk at the chop point. Nothing is drawn ON the tree -- an
-- earlier version cut a dark wedge in there and it just read as a black smudge stuck to the
-- bark, so the hit is all particles now.
local function chipHit(t)
	chopPoint(t)
	if not t.markCF then return end
	local em, host = sawChips(t.markCF * CFrame.new(0, 0, 0.4))
	em:Emit(22); Debris:AddItem(host, 2)
end

-- Fell one tree. The fall is INTEGRATED like a real pendulum rather than played back off a
-- fixed curve: angular acceleration is proportional to sin(angle), so it creaks over slowly,
-- accelerates through the middle and slams down -- which is what a falling tree actually does.
-- A linear or eased tween always reads as an object being rotated.
--
-- On top of that it does the three things a rotation alone cannot: the hinge SPLINTERS, the
-- trunk SLIPS off its stump as it goes over, and it TWISTS on the way down.
local function fellTree(t)
	if t.down then return end
	t.down = true

	local pivot = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
	local _, bs = frameOf(t.model)
	local rad   = t.rad or trunkR(t, bs)
	-- hinge at the STUMP, not the centre, or the crown swings through the ground
	local hinge = CFrame.new(pivot.Position.X, pivot.Position.Y - bs.Y * 0.5, pivot.Position.Z)

	-- IT FALLS AWAY FROM THE CHOP POINT, which was fixed on the side you were stood on when
	-- you started swinging -- so the tree always goes away from you, for the right reason.
	local away = t.markF
	if not away then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		away = Vector3.new(0, 0, 1)
		if hrp then
			local v = Vector3.new(pivot.Position.X - hrp.Position.X, 0, pivot.Position.Z - hrp.Position.Z)
			if v.Magnitude > 0.5 then away = v.Unit end
		end
	else
		away = -away                                   -- it faces you, so the tree goes the other way
	end
	local axis = Vector3.new(0, 1, 0):Cross(away)
	if axis.Magnitude < 0.01 then axis = Vector3.new(1, 0, 0) end
	axis = axis.Unit

	local FULL = math.rad(85)
	local function place(th)
		local k    = math.clamp(th / FULL, 0, 1)
		-- the butt SLIPS off the stump as it goes over, and the trunk twists as it falls
		local slip = CFrame.new(away * (k * k * 1.4) + Vector3.new(0, -k * 0.5, 0))
		local newCF = slip * hinge * CFrame.fromAxisAngle(axis, th) * hinge:Inverse() * pivot
			* CFrame.Angles(0, k * 0.22, 0)
		if t.model:IsA("Model") then t.model:PivotTo(newCF) else t.anchor.CFrame = newCF end
	end

	task.spawn(function()
		-- 1. the creak: it leans, hangs there a moment, and only then goes
		for i = 1, 14 do
			place(math.rad(3.5) * (i / 14) + math.rad(0.5) * math.sin(i * 1.5))
			task.wait(0.03)
		end
		task.wait(0.25)

		-- 2. THE HINGE SPLINTERS. Wood does not pivot cleanly; it tears, and the torn fibres
		-- stay stood on the stump after the trunk has gone.
		local hs = t.markCF or (hinge * CFrame.new(0, 2.6, 0))
		for i = 1, 6 do
			local sp = mk({ Color = PAL.WOOD_L,
				Size = Vector3.new(0.16 + (i % 3) * 0.08, 0.7 + (i % 4) * 0.5, 0.16),
				CFrame = hs * CFrame.new((i - 3.5) * rad * 0.36, -0.3, -rad * 0.35)
					* CFrame.Angles(math.rad(-8 - i * 4), 0, math.rad((i - 3.5) * 7)),
				Parent = camp })
			sp.Material = Enum.Material.WoodPlanks
		end
		local em0, h0 = sawChips(hs)
		em0:Emit(26); Debris:AddItem(h0, 2)

		-- 3. the fall
		local th, w = math.rad(4), 0
		while th < FULL do
			local dt = math.min(task.wait(), 0.05)
			w  += 2.3 * math.sin(th) * dt          -- torque falls off as it nears flat
			th += w * dt
			place(math.min(th, FULL))
		end

		-- 4. the impact: chips along the whole length, a dust burst under the crown, and a
		-- kick through the camera if you are stood close enough to feel it
		local em, host = sawChips(CFrame.new(pivot.Position))
		em:Emit(30); Debris:AddItem(host, 2)
		for i = 1, 3 do
			local d = mk({ Transparency = 1, Size = Vector3.new(1, 1, 1),
				CFrame = CFrame.new(hinge.Position + away * (bs.Y * 0.3 * i)), Parent = camp })
			local de = Instance.new("ParticleEmitter")
			de.Texture = "rbxasset://textures/particles/smoke_main.dds"
			de.Color = ColorSequence.new(PAL.CHIP)
			de.Lifetime = NumberRange.new(0.8, 1.8); de.Rate = 0
			de.Speed = NumberRange.new(7, 18); de.SpreadAngle = Vector2.new(80, 80)
			de.Size = NumberSequence.new(4.5); de.Acceleration = Vector3.new(0, -8, 0)
			de.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 1) })
			de.Parent = d; de:Emit(20)
			Debris:AddItem(d, 3)
		end

		local char = player.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		local hrp2 = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hrp2 and (hrp2.Position - hinge.Position).Magnitude < 90 then
			task.spawn(function()
				for i = 1, 12 do
					local k = 0.75 * (1 - i / 12)
					hum.CameraOffset = Vector3.new((math.random() - 0.5) * k,
					                               (math.random() - 0.5) * k, 0)
					task.wait(0.03)
				end
				hum.CameraOffset = Vector3.new()
			end)
		end

		for i = 1, 10 do
			place(FULL - math.rad(5) * math.sin(i / 10 * math.pi) * (1 - i / 12))
			task.wait(0.03)
		end
		place(FULL)

		-- 5. leave a stump where it stood
		local sr = math.max(0.9, rad)
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.BARK_D, CanCollide = true,
			Size = Vector3.new(1.5, sr * 2, sr * 2),
			CFrame = CFrame.new(hinge.Position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = camp })
		mk({ Shape = Enum.PartType.Cylinder, Color = PAL.WOOD_L,
			Size = Vector3.new(0.16, sr * 1.9, sr * 1.9),
			CFrame = CFrame.new(hinge.Position + Vector3.new(0, 1.28, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Parent = camp })

		-- 6. and it goes, Rust-style. Sink and fade together -- fading alone leaves a ghost
		-- lying there, sinking alone pops out of view at the last frame.
		task.wait(0.9)
		local parts = {}
		if t.model:IsA("BasePart") then parts = { t.model }
		else
			for _, d in ipairs(t.model:GetDescendants()) do
				if d:IsA("BasePart") then table.insert(parts, d) end
			end
		end
		for _, p in ipairs(parts) do tween(p, 1.3, { Transparency = 1 }) end
		local from = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
		for i = 1, 26 do
			local cf = from * CFrame.new(0, -(i / 26) * 3.2, 0)
			if t.model:IsA("Model") then t.model:PivotTo(cf) else t.anchor.CFrame = cf end
			task.wait(0.05)
		end
		hideThing(t.model, true)
	end)

	pickUp("log")
	if logsMilled + logsHeld >= LOGS_NEEDED then
		step = 2
		takeAxe()                                             -- chopping is done
		if millPrompt then millPrompt.Enabled = true end
	end
	refreshBanner()
end

-- the tree a swing would connect with: nearest, in reach, and roughly in front of you
local function targetTree()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestD
	for _, t in ipairs(treeList) do
		if not t.down and t.anchor.Parent then
			local to = t.anchor.Position - hrp.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			local d = flat.Magnitude
			if d <= CHOP_REACH and (d < 3 or flat.Unit:Dot(hrp.CFrame.LookVector) > 0.35) then
				if not bestD or d < bestD then best, bestD = t, d end
			end
		end
	end
	return best
end

-- CLICK OR TAP TO SWING. No ProximityPrompt: you just look at a pine and click.
local swinging = false
local function swingAxe()
	if step ~= 1 or not axeHeld or swinging or mgBusy then return end
	swinging = true
	axeSwingUntil = os.clock() + 0.55
	playSound(SOUND_CHOP, 0.7)
	local aim = targetTree()
	if aim then chopPoint(aim) end                -- fix the chop side before the hit lands

	-- the hit lands part-way through the swing, not on the click, so the axe visibly
	-- connects before the tree reacts
	task.delay(0.26, function()
		local t = targetTree()
		if t then
			t.hits += 1
			local em, host = sawChips(t.anchor.CFrame * CFrame.new(0, 1, 0))
			em:Emit(14); Debris:AddItem(host, 2)
			-- a shudder up the trunk on every hit that is not the last
			chipHit(t)                                -- chips off the trunk, nothing stuck to it
			if t.hits < SWINGS_PER_TREE then
				local base = t.model:IsA("Model") and t.model:GetPivot() or t.anchor.CFrame
				task.spawn(function()
					for i = 1, 6 do
						local k = math.sin(i / 6 * math.pi) * math.rad(1.6)
						local j = base * CFrame.Angles(k, 0, k * 0.5)
						if t.model:IsA("Model") then t.model:PivotTo(j) else t.anchor.CFrame = j end
						task.wait(0.03)
					end
					if t.model:IsA("Model") then t.model:PivotTo(base) else t.anchor.CFrame = base end
				end)
			else
				fellTree(t)
			end
		end
	end)
	task.delay(0.62, function() swinging = false end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		swingAxe()
	end
end)

local function wireShroom(sh)
	if sh:GetAttribute("SmoresWired") then return end
	local cap = sh:IsA("BasePart") and sh or topPartOf(sh)
	if not cap then return end
	sh:SetAttribute("SmoresWired", true)
	cap.CanQuery = true

	local pr = Instance.new("ProximityPrompt")
	pr.Name = "PickPrompt"; pr.ActionText = "Pick"; pr.ObjectText = "Mallow Mushroom"
	pr.HoldDuration = 0; pr.MaxActivationDistance = 12
	pr.RequiresLineOfSight = false; pr.Enabled = (step == 3); pr.Parent = cap
	table.insert(shroomList, { model = sh, prompt = pr, cap = cap })

	pr.Triggered:Connect(function(plr)
		if plr ~= player or step ~= 3 then return end
		if #carried >= CARRY_MAX or shroomsHeld >= SHROOMS_NEEDED then return end
		pr.Enabled = false
		if not playPull(SHROOM_PULL) then pr.Enabled = true; return end
		playSound(SOUND_POP, 0.6)
		-- ONLY THE CAP comes away. Everything else in the model is the stem, so it simply
		-- stays put; the cap hides and grows back later.
		hideThing(cap, true)
		pickUp("cap")
		refreshBanner()
		task.delay(REGROW_TIME, function()
			hideThing(cap, false)
			if step == 3 and shroomsHeld < SHROOMS_NEEDED then pr.Enabled = true end
		end)
	end)
end

-- ============================================================================
-- GO
-- ============================================================================
task.spawn(function()
	island = pollFor(findIsland, 90)

	-- Poll for a REAL PART, not just the name. island14 models replicate as empty shells
	-- before their parts arrive, so finding "campfire" proves nothing. The first version of
	-- this asked the shell for a BasePart, got nil, and the whole setup thread died on the
	-- spot -- which is why the mill, the marshmallows and the NPC all silently never happened.
	firePart = pollFor(function()
		local f = findOne(FIRE_NAME, island)
		if not f then return nil end
		if f:IsA("BasePart") then return f end
		return f:FindFirstChildWhichIsA("BasePart", true)
	end, 300)
	if not firePart then
		warn("[Smores] no usable part named 'campfire' -- quest inactive")
		return
	end
	-- KEEP THE WHOLE MODEL. firePart is just the first BasePart that happened to stream in,
	-- so sizing the fire off it gave a flame scaled to one log instead of to the woodpile.
	fireModel = findOne(FIRE_NAME, island) or firePart

	camp = Instance.new("Folder"); camp.Name = "CampSmores"; camp.Parent = Workspace
	print(("[Smores] campfire at (%.0f, %.0f, %.0f), island=%s")
		:format(firePart.Position.X, firePart.Position.Y, firePart.Position.Z,
		        island and island.Name or "?"))

	-- wait for a named thing to turn up AND actually have geometry
	local function pollSolid(key, secs)
		return pollFor(function()
			local o = findOne(key, island)
			if not o then return nil end
			if o:IsA("BasePart") then return o end
			return o:FindFirstChildWhichIsA("BasePart", true) and o or nil
		end, secs or 45)
	end
	-- ...and for a whole set of them, giving late arrivals a chance to show up
	local function pollMany(key, want, secs)
		local best = {}
		pollFor(function()
			local all = findAll(key, island)
			if #all > #best then best = all end
			return (#best >= want) or nil
		end, secs or 40)
		return best
	end

	-- ---- the axe: COPY IT FIRST, while it still looks right, then hide the world one.
	-- Cloning after hiding would copy a transparent axe.
	local axeSource = pollSolid(AXE_NAME, 40)
	if axeSource then
		axeTemplate = axeSource:Clone()
		hideThing(axeSource, true)
		print(("[Smores] axe found ('%s') -- original hidden, copy kept for the player")
			:format(axeSource.Name))
	else
		warn("[Smores] no 'axe' found -- chopping still works, you just will not hold one")
	end

	-- ---- the giant marshmallows: hidden until their stick is loaded
	marshParts = pollMany(MARSH_NAME, 3, 40)
	for _, m in ipairs(marshParts) do hideThing(m, true) end
	print(("[Smores] %d '%s' found and hidden"):format(#marshParts, MARSH_NAME))

	-- ---- the mill
	millPart = pollSolid(MILL_NAME, 40)
	if millPart then
		millPrompt = buildMill(millPart)
		print("[Smores] cutting station built on the 'mill' block")
	else
		warn("[Smores] no block named 'mill' found -- no cutting station")
	end

	-- ---- trees and mushrooms
	for _, tr in ipairs(pollMany(TREE_NAME, LOGS_NEEDED, 40)) do wireTree(tr) end
	for _, sh in ipairs(pollMany(SHROOM_NAME, SHROOMS_NEEDED, 40)) do wireShroom(sh) end
	print(("[Smores] %d tree(s), %d mushroom(s) wired"):format(#treeList, #shroomList))

	-- ---- your roasting sticks, hidden until the mill cuts them
	for _, sp in ipairs(pollMany(STICK_NAME, 3, 40)) do wireStick(sp) end
	pairSticks()
	print(("[Smores] %d '%s' found and hidden"):format(#sticks, STICK_NAME))

	-- ---- KEEP LOOKING. island14 hands the rest of itself over as you walk around it, so
	-- anything arriving late still gets hidden and wired instead of being missed.
	task.spawn(function()
		for _ = 1, 60 do
			task.wait(3)
			for _, tr in ipairs(findAll(TREE_NAME, island))   do wireTree(tr) end
			for _, sh in ipairs(findAll(SHROOM_NAME, island)) do wireShroom(sh) end
			for _, mm in ipairs(findAll(MARSH_NAME, island)) do
				local known = false
				for _, k in ipairs(marshParts) do if k == mm then known = true; break end end
				if not known then
					table.insert(marshParts, mm)
					hideThing(mm, true)
					print("[Smores] a marshmallow streamed in late -- hidden")
				end
			end
			for _, sp in ipairs(findAll(STICK_NAME, island)) do wireStick(sp) end
			pairSticks()
		end
	end)

	-- ---- the operator's stand
	task.spawn(function()
		local sp = pollFor(function()
			local d = findOne(STAND_NAME, island)
			if not d then return nil end
			if d:IsA("BasePart") then return d end
			return d:FindFirstChildWhichIsA("BasePart", true)
		end, 90)
		if sp then buildStand(sp) else print("[Smores] no part named 'stand' -- skipped") end
	end)

	-- ---- mill delivery -> saw -> sticks fly to the fire
	if millPrompt then
		-- ONE LOG AT A TIME. You pull the lever, saw that log through the blade yourself, and
		-- one stick comes up by the fire. Then you feed the next one in.
		millPrompt.Triggered:Connect(function(plr)
			if plr ~= player or milling or logsHeld == 0 then return end
			milling = true
			millPrompt.Enabled = false
			dropOne("log")
			logsHeld -= 1
			millLeft = MILL_STROKES
			refreshBanner()

			task.spawn(function()
				-- millBlade is a MODEL now, so it has no .CFrame -- use the stored shaft frame
				local em, host = sawChips(millBladeCF or CFrame.new())
				playSound(SOUND_SAW, 0.7)
				if millLever then                          -- throw the lever to start it
					millLever:PivotTo(millLeverCF * CFrame.Angles(0, 0, math.rad(-52)))
				end
				-- THE CARRIAGE ONLY MOVES WHEN YOU LAND A STROKE. It chases the target rather
				-- than snapping to it, so each stroke reads as a shove of the log into the blade.
				local lg = buildLogProp()
				lg:PivotTo(millCradle * CFrame.Angles(0, math.rad(90), 0))
				local target, shown, running = 0, 0, true
				task.spawn(function()
					while running do
						spinMill(0.22)                    -- blade and flywheel on the one shaft
						shown += (target - shown) * 0.11
						local ride = millCradle:Lerp(millOut, math.clamp(shown, 0, 1))
						lg:PivotTo(ride * CFrame.Angles(0, math.rad(90), 0))
						if millCarriage then millCarriage:PivotTo(ride) end
						task.wait()
					end
				end)

				playSaw(MILL_STROKES, function(p)
					target   = p
					millLeft = math.max(0, MILL_STROKES - math.floor(p * MILL_STROKES + 0.5))
					refreshBanner()
					em:Emit(16)
					if millDust then millDust:Emit(12) end
				end)

				task.wait(0.5)                            -- let the carriage finish its run out
				running = false
				lg:Destroy()
				if millCarriage then millCarriage:PivotTo(millCradle) end
				Debris:AddItem(host, 2)
				if millLever then millLever:PivotTo(millLeverCF * CFrame.Angles(0, 0, math.rad(16))) end

				logsMilled += 1
				milling = false
				pairSticks()
				raiseStick(logsMilled)                    -- one cut, one stick up by the fire
				refreshBanner()

				if logsMilled >= LOGS_NEEDED then
					step = 3
					enableShroomPrompts(true)
					refreshBanner()
					if npcHead then showBubble(npcHead, "Sticks are up! Now we need mallows.", false) end
				else
					millPrompt.Enabled = (logsHeld > 0)
					if npcHead and logsHeld == 0 then
						showBubble(npcHead, "That is one. Fetch me another log.", false)
					end
				end
			end)
		end)
	end

	-- ---- the NPC
	local function startQuest()
		if questAccepted then return end
		questAccepted = true; step = 1
		giveAxe()
		buildBackpack()
		refreshBanner()
	end

	-- THIS ISLAND'S NPC, not somebody else's. There are several models called "Candy Npc" in
	-- this place -- island 13 has one, and there is another parented straight to Workspace --
	-- so a plain Workspace-wide search could easily wire the wrong quest giver.
	--
	-- Look INSIDE island14 first and take that unconditionally. Only if the island has none of
	-- its own do we fall back to a proximity search, and even then it has to be within
	-- NPC_MAX_DIST of this campfire.
	local function npcIn(scope, needDist)
		local best, bestD
		for _, d in ipairs(scope:GetDescendants()) do
			local match = false
			for _, w in ipairs(NPC_NAMES) do if norm(d.Name) == w then match = true; break end end
			if match then
				local h = npcHeadOf(d)
				if h then
					local dist = (h.Position - firePart.Position).Magnitude
					if (not needDist or dist <= NPC_MAX_DIST) and (not bestD or dist < bestD) then
						best, bestD = h, dist
					end
				end
			end
		end
		return best
	end

	npcHead = pollFor(function()
		if island then
			local mine = npcIn(island, false)
			if mine then return mine end
		end
		return npcIn(Workspace, true)
	end, 45)

	if not npcHead then
		warn(("[Smores] no 'Candy Npc' within %d studs of the campfire -- starting anyway")
			:format(NPC_MAX_DIST))
		startQuest()
	else
		print(("[Smores] Candy Npc wired -- %.0f studs from the campfire")
			:format((npcHead.Position - firePart.Position).Magnitude))

		local pages, index = nil, 0
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Talk"; prompt.ObjectText = "Candy Npc"; prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false
		prompt.Parent = npcHead

		local function pagesFor()
			if step >= 5 then
				return { "Best night this camp has had in years.", "Sit. Have one. \xF0\x9F\x8D\xA1" }
			elseif step == 4 then
				if shroomsHeld > 0 then return { "Hand them over, I will load the sticks." } end
				return { ("%d of %d sticks loaded. Keep the mallows coming."):format(loaded, #sticks) }
			elseif step == 3 then
				return { "Mallow mushrooms grow all over this island.",
				         ("Take the caps only -- leave the stems and they grow back. %d of %d.")
				             :format(shroomsHeld, SHROOMS_NEEDED) }
			elseif step == 2 then
				return { "Good chopping. Now run those logs through the mill." }
			elseif step == 1 then
				return { ("Four pines should do it. %d down."):format(logsMilled + logsHeld) }
			end
			return {
				"You picked a good night to turn up.",
				"I have a fire pit with no fire, and nothing to roast on either.",
				"Here -- take my axe. Fell four pines and run them through the mill.",
				"Then bring me six mallow mushrooms and we will get this camp going.",
			}
		end

		local function closeIt()
			hideBubble(npcHead); prompt.ActionText = "Talk"; index = 0; pages = nil
		end

		prompt.Triggered:Connect(function(plr)
			if plr ~= player then return end

			-- handing the mallows over is this SAME prompt, so there is no second one to hunt for
			if step == 4 and shroomsHeld > 0 then
				local give = shroomsHeld
				dropAll("cap")
				shroomsHeld = 0
				local per = math.max(1, math.floor(SHROOMS_NEEDED / math.max(1, #sticks)))
				task.spawn(function()
					for _ = 1, math.floor(give / per) do
						local st = sticks[loaded + 1]
						if st and st.marsh and not st.done then
							st.done = true
							loaded += 1
							hideThing(st.marsh, false)
							local mp = st.marsh:IsA("BasePart") and st.marsh or topPartOf(st.marsh)
							if mp then
								local pe = Instance.new("ParticleEmitter")
								pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
								pe.Color = ColorSequence.new(PAL.MALLOW)
								pe.Lifetime = NumberRange.new(0.5, 1); pe.Rate = 0
								pe.Speed = NumberRange.new(3, 8); pe.SpreadAngle = Vector2.new(180, 180)
								pe.Size = NumberSequence.new(0.6); pe.LightEmission = 0.6
								pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1),
									NumberSequenceKeypoint.new(1, 1) })
								pe.Parent = mp; pe:Emit(30); Debris:AddItem(pe, 2)
							end
							playSound(SOUND_POP, 0.6)
						end
						refreshBanner()
						task.wait(0.8)
					end

					local all = (#sticks > 0)
					for _, st in ipairs(sticks) do if not st.done then all = false end end
					if all and step < 5 then
						step = 5
						refreshBanner()
						showBubble(npcHead, "That is the lot. Stand back!", false)
						task.delay(1.4, function()
							igniteFire()
							local ce = ReplicatedStorage:FindFirstChild("CoinEvent")
							if ce then pcall(function() ce:FireServer(COIN_REWARD) end) end
							_G.smoresQuestComplete = true
							print(("[Smores] QUEST COMPLETE -- +%d coins"):format(COIN_REWARD))
						end)
					end
				end)
				return
			end

			if index == 0 then pages = pagesFor() end
			index += 1
			if not pages or index > #pages then closeIt(); return end
			if index == 3 and step == 0 then startQuest() end   -- the page where he hands the axe over
			local last = index >= #pages
			showBubble(npcHead, pages[index], true,
				last and "[E] close" or ("[E] more  (%d/%d)"):format(index, #pages))
			prompt.ActionText = last and "Close" or "Continue"
		end)
		prompt.PromptHidden:Connect(function() if index ~= 0 then closeIt() end end)
	end

	-- step 3 -> 4 once you have enough caps
	task.spawn(function()
		while step < 5 do
			if step == 3 and shroomsHeld >= SHROOMS_NEEDED then step = 4; refreshBanner() end
			task.wait(0.4)
		end
	end)

	refreshBanner()
	print("[Smores] ready -- chop -> mill -> gather -> deliver -> ignite")
end)

-- ============================================================================
-- /complete -- test command: finish the campsite instantly
-- ============================================================================
-- Island-scoped, the same as the other quests: typed anywhere else it does nothing, so it
-- can never light island 14's fire from across the map.
local function onCommand(msg)
	if tostring(msg or ""):lower():sub(1, 9) ~= "/complete" then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (firePart and firePart.Parent and hrp) then return end
	if (hrp.Position - firePart.Position).Magnitude > 420 then return end
	if step >= 5 then return end

	questAccepted = true
	takeAxe()
	dropAll("log"); dropAll("cap")
	logsHeld, shroomsHeld = 0, 0
	logsMilled = LOGS_NEEDED
	enableShroomPrompts(false)
	if millPrompt then millPrompt.Enabled = false end
	step = 5
	refreshBanner()

	-- run it as the sequence, not as a snap to the end state: the sticks come up, the
	-- marshmallows land on them, and only then does it light. Skipping straight to a lit fire
	-- would hide exactly the bits worth checking.
	task.spawn(function()
		pairSticks()
		for i = 1, #sticks do
			raiseStick(i)
			task.wait(0.35)
		end
		task.wait(0.5)
		for _, st in ipairs(sticks) do
			if st.marsh and not st.done then
				st.done = true
				loaded += 1
				hideThing(st.marsh, false)
				playSound(SOUND_POP, 0.6)
				task.wait(0.35)
			end
		end
		refreshBanner()
		task.wait(0.6)
		igniteFire()
		local ce = ReplicatedStorage:FindFirstChild("CoinEvent")
		if ce then pcall(function() ce:FireServer(COIN_REWARD) end) end
		_G.smoresQuestComplete = true
		print(("[Smores][TEST] /complete -- campsite finished, +%d coins"):format(COIN_REWARD))
	end)
end
pcall(function()
	TextChatService.MessageReceived:Connect(function(m)
		if m.TextSource and m.TextSource.UserId == player.UserId then onCommand(m.Text) end
	end)
end)
pcall(function() player.Chatted:Connect(onCommand) end)
