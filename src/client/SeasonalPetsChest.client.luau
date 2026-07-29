--======================================================================
-- SeasonalPetsChest.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- SEASONAL PETS LEAVES THE MENU AND BECOMES A PLACE YOU GO.
--
-- It used to be a row in MORE+, which made a limited-time reward feel like a settings
-- entry. Now there is a treasure box beside the Global Garden: walk up, press E, and the
-- Seasonal Pets panel opens. The reward for the garden lives AT the garden.
--
-- ===== IT DOES NOT REBUILD THE PANEL =====
-- The Seasonal Pets UI already exists -- CoreClient builds it as `LockerGui` (its own
-- header, close button and grid of the four seasonal pets) and opens it through
-- `openLocker()`, which also refreshes ownership from the server first. This script only
-- adds the door. A second copy of that grid would be a second thing that can disagree
-- with the server about what the player owns.
--
-- ===== FINDING THE BOX =====
-- Tries, in order: a model/part you have named or tagged; then the garden's own
-- DonationChest as an ANCHOR to place a new box beside (never replacing it -- donating
-- and opening seasonal pets are different actions and must not share a prompt).
-- If neither is found it says so once, loudly, rather than silently doing nothing.
--
-- The box is built CLIENT-SIDE. It is a UI door, not gameplay: nothing about it needs to
-- replicate, and building it here means no server edit and no risk to the garden build.
--======================================================================

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local player            = Players.LocalPlayer
local PlayerGui         = player:WaitForChild("PlayerGui")

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- 1. If you tag a part/model with this, it is used as-is and nothing is built.
	TAG = "SeasonalPetsChest",
	-- 2. Otherwise any model/part with one of these names (searched in Workspace).
	NAMES = { "SeasonalChest", "SeasonalPetsChest", "TreasureBox", "TreasureChest" },
	-- 3. Otherwise a box is built next to this, offset by BUILD_OFFSET.
	ANCHOR_NAME  = "DonationChest",
	BUILD_OFFSET = Vector3.new(6, 0, 0), -- studs to the side of the anchor

	PROMPT_ACTION = "Open",
	PROMPT_OBJECT = "Seasonal Pets \xE2\x9D\x84\xEF\xB8\x8F",
	PROMPT_DIST   = 12,
	HOLD_DURATION = 0,   -- 0 = instant press; raise for a hold-to-open

	-- Chest look (matches the garden's own chests: warm wood + gold bands)
	WOOD = Color3.fromRGB(120, 74, 38),
	GOLD = Color3.fromRGB(214, 168, 54),
	SIZE = Vector3.new(4, 2.6, 2.8),
}

--======================================================================
-- OPEN THE PANEL
--
-- Three ways in, most correct first. openLocker() is the real one -- it re-requests
-- ownership from the server and expands the current season before showing the panel, so
-- a player who just earned a pet sees it. Enabling the GUI directly skips that refresh,
-- which is why it is the fallback and not the first choice.
--======================================================================
local function openSeasonalPets()
	if _G.playUIClick then pcall(_G.playUIClick) end

	if type(_G.openLocker) == "function" then
		local ok = pcall(_G.openLocker)
		if ok then return true end
	end
	if _G.MainMenuManager and _G.MainMenuManager.notifyOpened then
		local g = PlayerGui:FindFirstChild("LockerGui")
		if g then
			pcall(_G.MainMenuManager.notifyOpened, "Locker")
			g.Enabled = true
			return true
		end
	end
	local g = PlayerGui:FindFirstChild("LockerGui")
	if g then g.Enabled = true; return true end

	warn("[SeasonalChest] no LockerGui and no _G.openLocker -- the Seasonal Pets panel is not built yet")
	return false
end

--======================================================================
-- FIND OR BUILD THE BOX
--======================================================================
local function findTagged()
	for _, inst in ipairs(CollectionService:GetTagged(CONFIG.TAG)) do
		if inst:IsDescendantOf(Workspace) then return inst end
	end
	return nil
end

local function findByName()
	for _, name in ipairs(CONFIG.NAMES) do
		local f = Workspace:FindFirstChild(name, true)
		if f then return f end
	end
	return nil
end

local function part(parent, name, size, color, cf)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color; p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A small chest: body, lid, two gold bands, a latch. Deliberately simple -- it is a
-- signpost for a menu, so it must read at a glance and cost nothing.
local function buildChest(atCFrame)
	local m = Instance.new("Model"); m.Name = "SeasonalPetsChest"
	local s = CONFIG.SIZE

	local body = part(m, "Body", Vector3.new(s.X, s.Y * 0.62, s.Z), CONFIG.WOOD,
		atCFrame * CFrame.new(0, s.Y * 0.31, 0))
	m.PrimaryPart = body

	part(m, "Lid", Vector3.new(s.X, s.Y * 0.38, s.Z), CONFIG.WOOD,
		atCFrame * CFrame.new(0, s.Y * 0.81, 0))
	-- gold bands around the body, and one across the lid
	part(m, "BandL", Vector3.new(0.28, s.Y * 0.66, s.Z + 0.06), CONFIG.GOLD,
		atCFrame * CFrame.new(-s.X * 0.32, s.Y * 0.31, 0))
	part(m, "BandR", Vector3.new(0.28, s.Y * 0.66, s.Z + 0.06), CONFIG.GOLD,
		atCFrame * CFrame.new( s.X * 0.32, s.Y * 0.31, 0))
	part(m, "LidBand", Vector3.new(s.X + 0.06, 0.24, s.Z + 0.06), CONFIG.GOLD,
		atCFrame * CFrame.new(0, s.Y * 0.81, 0))
	local latch = part(m, "Latch", Vector3.new(0.5, 0.5, 0.22), CONFIG.GOLD,
		atCFrame * CFrame.new(0, s.Y * 0.62, s.Z * 0.5))
	latch.Shape = Enum.PartType.Block

	m.Parent = Workspace
	return m
end

local function attachPrompt(target)
	local host = target
	if target:IsA("Model") then
		host = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	end
	if not (host and host:IsA("BasePart")) then return nil end

	-- Never stack a second prompt (respawn, re-run, or a box that already had one).
	local existing = host:FindFirstChild("SeasonalPetsPrompt")
	if existing then existing:Destroy() end

	local pr = Instance.new("ProximityPrompt")
	pr.Name = "SeasonalPetsPrompt"
	pr.ActionText = CONFIG.PROMPT_ACTION
	pr.ObjectText = CONFIG.PROMPT_OBJECT
	pr.KeyboardKeyCode = Enum.KeyCode.E
	pr.MaxActivationDistance = CONFIG.PROMPT_DIST
	pr.HoldDuration = CONFIG.HOLD_DURATION
	pr.RequiresLineOfSight = false -- the garden has walls and pillars; losing the prompt behind one is just annoying
	pr.Parent = host

	pr.Triggered:Connect(function(plr)
		if plr ~= player then return end
		openSeasonalPets()
	end)
	return pr
end

--======================================================================
-- RUN -- the garden is built by the server a few seconds after join, so this retries
-- rather than looking once and giving up.
--======================================================================
task.spawn(function()
	local target, built
	for _ = 1, 60 do -- ~30s of retries
		target = findTagged() or findByName()
		if target then break end

		local anchor = Workspace:FindFirstChild(CONFIG.ANCHOR_NAME, true)
		if anchor then
			local base = anchor:IsA("Model")
				and (anchor.PrimaryPart or anchor:FindFirstChildWhichIsA("BasePart"))
				or anchor
			if base and base:IsA("BasePart") then
				-- Sit it on the ground beside the anchor, facing the same way.
				local cf = base.CFrame * CFrame.new(CONFIG.BUILD_OFFSET)
				cf = CFrame.new(Vector3.new(cf.Position.X, base.Position.Y - base.Size.Y * 0.5, cf.Position.Z))
					* (base.CFrame - base.CFrame.Position)
				target = buildChest(cf)
				built = true
				break
			end
		end
		task.wait(0.5)
	end

	if not target then
		warn(("[SeasonalChest] no chest found and no %q to build beside. Tag a part %q, "
			.. "or name one of: %s"):format(CONFIG.ANCHOR_NAME, CONFIG.TAG, table.concat(CONFIG.NAMES, ", ")))
		return
	end

	local pr = attachPrompt(target)
	if not pr then
		warn("[SeasonalChest] found " .. target:GetFullName() .. " but it has no BasePart to hold a prompt")
		return
	end

	print(("[SeasonalChest] ready -- %s at %s (%s)"):format(
		built and "built a box" or "using existing",
		target:GetFullName(),
		built and "beside " .. CONFIG.ANCHOR_NAME or "found"))
end)
