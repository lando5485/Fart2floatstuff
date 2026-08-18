--======================================================================
-- NpcChatRange.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- NPC CHAT DISAPPEARS WHEN YOU WALK AWAY. Every quest NPC in this realm talks through the same
-- island1-style helper: a BillboardGui named "SpeechBubble" adorned to the NPC (thirteen quest scripts
-- carry an identical copy of it). Those bubbles render out to MaxDistance = 120 studs -- so an NPC you
-- finished talking to keeps mouthing its line at you from across the island.
--
-- This enforces one rule for all of them: a SpeechBubble is visible only within 12 STUDS of its NPC.
-- Step past that and it disappears; step back inside it (while the bubble's own lifetime hasn't ended)
-- and it returns, which is the correct reading of "walked away mid-conversation, came back".
--
-- ===== WHY A WATCHER AND NOT THIRTEEN EDITS =====
--   * One rule in one file beats the same number pasted into thirteen constructors -- and it also covers
--     any BAKED-IN copies of those quest scripts (Rojo only ever adds), which per-file edits never could.
--   * MaxDistance measures from the CAMERA; 12 studs of chat range should measure from the CHARACTER.
--     Zoom out with the mouse wheel and a camera-based cutoff hides a bubble you are standing next to.
--   * Only the NAME "SpeechBubble" is matched. Signs, counters, title tags and waypoint arrows are
--     billboards too, and a distance rule meant for dialogue must not start hiding wayfinding.
--
-- Toggles Enabled rather than destroying: each bubble's creator owns its lifetime (they self-destroy on
-- a timer or on the next line of dialogue), and destroying from outside would fight that.
--======================================================================

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local RANGE   = 12      -- studs from the CHARACTER, not the camera
local RANGE2  = RANGE * RANGE
local PERIOD  = 0.15    -- ~7 checks/second; dialogue range does not need frame precision

local bubbles = {} -- [BillboardGui] = true

local function adopt(inst)
	if inst:IsA("BillboardGui") and inst.Name == "SpeechBubble" then
		bubbles[inst] = true
	end
end

for _, d in ipairs(Workspace:GetDescendants()) do adopt(d) end
Workspace.DescendantAdded:Connect(function(d)
	task.defer(function()
		if d.Parent then adopt(d) end
	end)
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < PERIOD then return end
	acc = 0
	if next(bubbles) == nil then return end
	-- Stand down while the intro cinematic runs: its own sweep hides every billboard and re-asserts each
	-- RenderStepped, so writing Enabled here would only churn properties it immediately overrides.
	if _G.introPlaying then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local myPos = hrp.Position

	for bb in pairs(bubbles) do
		if not bb.Parent then
			bubbles[bb] = nil -- its creator destroyed it; forget it
		else
			-- the anchor is the adornee (the NPC part the bubble floats over); fall back to the parent part
			local anchor = bb.Adornee or bb.Parent
			local pos = (typeof(anchor) == "Instance" and anchor:IsA("BasePart")) and anchor.Position
				or (typeof(anchor) == "Instance" and anchor:IsA("Model") and anchor:GetPivot().Position)
				or nil
			if pos then
				local d = myPos - pos
				local inside = (d.X * d.X + d.Y * d.Y + d.Z * d.Z) <= RANGE2
				if bb.Enabled ~= inside then bb.Enabled = inside end
			end
		end
	end
end)

print(("[NpcChatRange] active -- NPC speech bubbles hide beyond %d studs (character-measured, all quests + baked copies)")
	:format(RANGE))
