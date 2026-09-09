--======================================================================
-- NPC WAYPOINT ARROW   (LocalScript, per-player)
--======================================================================
-- THE ONE GUIDE ARROW -- the same arrow the Space Realm uses, pointed at this island's quest giver.
--
-- ===== WHAT CHANGED, AND WHY =====
-- This used to render a bouncing green BillboardGui triangle over the NPC's head. It told you WHICH one, but
-- only once you could already see them -- stood at the far end of Popcorn Pinnacle with the quest giver
-- behind a projector, a marker over their head is a marker you have not found yet. The Space Realm answers
-- the question a lost player actually has ("which WAY?") with a single arrow floating at chest height in
-- front of them, turning to follow the target as they walk. That arrow is now shared: src/shared/GuideArrow
-- is the Space Realm's module, copied verbatim except for an optional colour, so all four realms point the
-- same way with the same object.
--
-- ===== THIS FILE IS STILL ONLY A RENDERER =====
-- NpcGuideArrow remains the brain. It works out which island you are on, who its quest giver is, and when
-- guidance should retire, and publishes the answer on one global:
--
--     _G.questArrowNpc   -- the NPC model to point at right now, or nil for none
--
-- Everything that made the old marker well-behaved is inherited unchanged, because it all lives there:
--   * gone the moment you fly away
--   * gone after the visit window
--   * gone once you have reached that NPC
--
-- reachDistance = 0 is deliberate. GuideArrow can retire itself on proximity, but the brain ALREADY clears
-- _G.questArrowNpc on arrival -- if both did it, the arrow would delete itself a frame before the brain
-- agreed and rebuild on the next Heartbeat, flickering at exactly the moment the player arrives.
-- One owner for retirement, and it is not this file.
--
-- ===== THE GARDEN TRAIL IS UNTOUCHED =====
-- GardenGuideTrail's ground chevrons still run the opening minutes (gardener, then the island-1 food stand).
-- That is the intro teaching a brand-new player to walk somewhere, on a flat island with nothing else on
-- screen, and a line of chevrons on the floor is the right shape for it. Everything AFTER the intro -- every
-- island quest giver on all fourteen islands -- is this single arrow.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

-- The shared module, required THROUGH Shared so a missing map in default.project.json shows up as an
-- infinite-yield warning naming the module rather than as an arrow that silently never appears.
local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GuideArrow = require(Shared:WaitForChild("GuideArrow"))

-- The chevron trail's green. One guidance colour across the realm: whatever is pointing at something, in the
-- world or on the floor, is this colour.
local ARROW_GREEN = Color3.fromRGB(50, 220, 80)

-- ===== THUNDERSTORMS =====
-- A storm blacks the sky out and the arrow goes with it, then comes back when the storm ends -- the same rule
-- the marker obeyed. Windstorms are deliberately NOT included: they do not obscure anything, and hiding
-- guidance during an event that does not hide it is just losing it.
local function stormUp()
	return _G.thunderstormActive == true
end

local shown  = nil   -- the NPC the live arrow is pointing at (nil = no arrow up)
local handle = nil   -- GuideArrow handle, so stop() can never kill a newer arrow

local function clear()
	if handle then GuideArrow.stop(handle) end
	handle, shown = nil, nil
end

RunService.Heartbeat:Connect(function()
	local npc = _G.questArrowNpc

	-- Not guiding, the NPC streamed out / was destroyed, or a storm is up -> no arrow. Checking Parent
	-- matters: the model can vanish between frames, and the module would then hold an arrow pointing at
	-- nothing while it waits for a target that is never coming back.
	if not (npc and npc.Parent) or stormUp() then
		if shown then clear() end
		return
	end

	if shown == npc then return end   -- already pointing there; the module owns the per-frame work

	local name = npc.Name
	handle = GuideArrow.start({
		tag           = "NpcArrow",
		targetName    = name,
		color         = ARROW_GREEN,
		reachDistance = 0,             -- retirement belongs to NpcGuideArrow (see the header)
		getTarget     = function() return _G.questArrowNpc end,
		activeLog     = "[NpcArrow] guide arrow up -> " .. name,
		removeLog     = "[NpcArrow] guide arrow away",
	})
	shown = npc
end)

print("[NpcArrow] ready -- ONE guide arrow at chest height points the way to the quest giver " ..
	"(same arrow as the Space Realm; hidden for the duration of a thunderstorm, restored when it ends)")
