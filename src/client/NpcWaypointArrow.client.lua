--======================================================================
-- NPC WAYPOINT ARROW   (LocalScript, per-player)   -- ported from npc-waypoint-arrow
--======================================================================
-- THE BOUNCING ▼ OVER THE QUEST GIVER'S HEAD.
--
-- The ground chevrons say "walk this way"; this says "THAT is the one". Together they answer the two
-- questions a player actually has on landing, and neither answers the other's.
--
-- ===== WHAT IS PORTED, AND WHAT IS NOT =====
-- The source kit drove this from its own hard-coded NPC table, its own island detector and its own timers.
-- All three are dropped. In this realm NpcGuideArrow ALREADY works out which island you are on, which NPC
-- belongs to it, and when guidance should retire -- so this script renders and nothing else. It reads the one
-- value that script publishes:
--
--     _G.questArrowNpc   -- the NPC model to point at right now, or nil for none
--
-- That is deliberate. The kit's own doc has the arrow UNGATED ("always on") and warns that its island loop is
-- the block you must rewrite or every arrow hides forever. Giving it a second copy of the island logic is
-- exactly how the two guides end up disagreeing -- the trail gone but the ▼ still burning over an NPC you met
-- five minutes ago. One brain, two renderers.
--
-- So it obeys, for free, every rule the trail obeys:
--   * gone the moment you fly away
--   * gone after the 45-second visit window
--   * gone once you have reached that NPC
--
-- ===== WHY A BILLBOARDGUI IN PLAYERGUI =====
-- BillboardGui always faces the camera and holds a constant on-screen size, so the ▼ is the same readable
-- blob at 5 studs or 200. It is parented to PlayerGui rather than to the NPC because StreamingEnabled will
-- stream the NPC out from under it -- parented to the NPC, the gui dies with it mid-frame and the render loop
-- is left writing to a destroyed instance. Adornee'd from PlayerGui, it stays ours to destroy on our schedule.
--
-- StudsOffsetWorldSpace, NOT StudsOffset: these NPCs turn to face you (NpcLife), and StudsOffset is relative
-- to the adornee's orientation -- the arrow would swing around their head like a compass needle as they
-- turned. World space keeps "up" up.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer
local playerGui  = player:WaitForChild("PlayerGui")

-- ===== TUNING =====
local ARROW_COLOR  = Color3.fromRGB(50, 220, 80) -- the green of the chevron trail: one guidance colour
local ARROW_SIZE   = UDim2.fromOffset(60, 60)    -- screen pixels, constant at any distance
local ARROW_MARGIN = 3                           -- studs above the NPC's bounding-box TOP
local BOUNCE_AMP   = 1                           -- studs of travel each way
local BOUNCE_SPEED = 2.5                         -- rad/sec -> ~2.5s cycle
local MAX_DISTANCE = 240                         -- backstop if island detection ever lags

local gui, label, adornee, baseOffset

local function teardown()
	if gui then gui:Destroy() end
	gui, label, adornee, baseOffset = nil, nil, nil, nil
end

-- HORIZONTAL position comes from the body root; VERTICAL comes from the bounding box.
--
-- Conflating those is the usual bug: a model's bounding-box CENTRE is dragged off the body by whatever sticks
-- out furthest (a held tool, a long hat), and the arrow ends up hovering over empty ground beside the NPC.
-- Only the HEIGHT is taken from the box -- which is what makes tall and short rigs both work with no
-- per-NPC offset.
local function anchorOf(npc)
	local hrp = npc:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then return hrp end
	if npc:IsA("Model") and npc.PrimaryPart then return npc.PrimaryPart end
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "head", 1, true) then return d end
	end
	return npc:FindFirstChildWhichIsA("BasePart", true)
end

local function build(npc)
	local part = anchorOf(npc)
	if not part then return false end -- parts have not streamed in yet; try again next frame

	local top = part.Position.Y + 3
	local ok, cf, size = pcall(function() return npc:GetBoundingBox() end)
	if ok and cf then top = cf.Position.Y + size.Y * 0.5 end

	adornee    = part
	baseOffset = Vector3.new(0, (top - part.Position.Y) + ARROW_MARGIN, 0)

	gui = Instance.new("BillboardGui")
	gui.Name = "QuestWaypointArrow"
	gui.Adornee = part
	gui.Size = ARROW_SIZE
	gui.StudsOffsetWorldSpace = baseOffset
	gui.AlwaysOnTop = true   -- readable through the island's own scenery
	gui.LightInfluence = 0   -- full brightness at night and in shadow
	gui.MaxDistance = MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.Text = "\xE2\x96\xBC" -- BLACK DOWN-POINTING TRIANGLE
	label.TextColor3 = ARROW_COLOR
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.3 -- has to survive a bright sky
	label.Parent = gui
	return true
end

-- The NPC talking puts a speech bubble exactly where this arrow sits. Two overlapping billboards is a mess,
-- and the bubble is the more urgent of the two, so the arrow yields while it is up.
local function bubbleUp(npc)
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BillboardGui") and d ~= gui then
			local n = string.lower(d.Name)
			if string.find(n, "speech", 1, true) or string.find(n, "bubble", 1, true) then
				return d.Enabled ~= false
			end
		end
	end
	return false
end

RunService.Heartbeat:Connect(function()
	local npc = _G.questArrowNpc

	-- Not guiding, or the NPC streamed out / was destroyed -> no arrow. Checking Parent matters: the model
	-- can vanish between frames and an Adornee pointing at a destroyed part renders in the world origin.
	if not (npc and npc.Parent) then
		if gui then teardown() end
		return
	end

	if not gui then
		if not build(npc) then return end
	elseif gui.Adornee ~= adornee or (adornee and not adornee.Parent) then
		teardown() -- guiding to a DIFFERENT npc now, or ours streamed out: rebuild against the new one
		return
	end

	gui.Enabled = not bubbleUp(npc)
	gui.StudsOffsetWorldSpace = baseOffset
		+ Vector3.new(0, math.sin(os.clock() * BOUNCE_SPEED) * BOUNCE_AMP, 0)
end)

print("[NpcArrow] ready -- bouncing marker over the quest giver, on the same rules as the ground trail")
