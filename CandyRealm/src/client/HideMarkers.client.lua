-- ============================================================================================================
-- PLACEMENT MARKERS ARE NEVER SEEN -- Candy realm.
-- ============================================================================================================
-- Quests position things by looking up a named brick in the world: the gumball orbs, the dig spots, the fishing
-- spot, the storm anchors. Those bricks are COORDINATES, not scenery -- the quest builds its real prop on top
-- of them. Left alone they sit there as solid coloured blocks exactly where the thing you are meant to collect
-- should be.
--
-- Hiding used to be each quest's own business, done as a side effect of adopting a brick. That leaves holes
-- wherever a brick is NOT adopted: surplus bricks past the quest's target, bricks that stream in after a
-- quest's scan window has closed, and every brick left over once a quest is finished. Same rule, three
-- different places to forget it. So it lives here instead, once, applied to the world rather than to whatever
-- a quest happened to pick up.
--
-- WHAT COUNTS AS A MARKER -- name-based, and deliberately narrow:
--   * exactly "gumball"        -- the collectible anchors on island 1
--   * any name ending in "spot" -- digspot1..5, buriedeggspot, waterspot, fishspot, stormspot, shovelspot,
--                                  rodbarrelspot, popcorneggspot, "production spot"
--
-- ENDING in "spot", not CONTAINING it: "spotlight" contains it and is a real light that must stay. The suffix
-- rule excludes it for free, and that is the whole reason the test is written this way.
--
-- NOT touched: oven, mixer, campfire, crystal, bell, axe, giantcookie, pinetree and friends. Those names turn
-- up in the same quest configs but they are REAL objects the player is supposed to see -- hiding by "is it
-- referenced by a quest" instead of "is it a position anchor" would strip the islands bare.
--
-- STREAMING: island parts arrive as the player moves, so this cannot be a one-shot sweep -- a marker that
-- appears thirty seconds in has to be hidden the moment it lands. Hence the DescendantAdded hook.
--
-- CanQuery goes off as well as CanCollide: an invisible marker that still answers raycasts silently eats
-- clicks and proximity prompts aimed at whatever stands in front of it, which is worse than seeing it.
-- ============================================================================================================

local Workspace = game:GetService("Workspace")

local function isMarker(inst)
	if not inst:IsA("BasePart") then return false end
	local n = string.lower(inst.Name)
	if n == "gumball" then return true end
	-- Trailing numbering and spaces come off first: markers are placed in sets, so the real names in the
	-- world are DigSpot1..DigSpot5, not "DigSpot". Testing the raw name would have hidden "buriedeggspot"
	-- and missed every numbered dig spot -- the exact bricks most likely to be left showing.
	n = (n:gsub("[%s%d]+$", ""))
	-- ENDS with "spot", never merely contains it: "spotlight" is a real light and must stay visible.
	return #n >= 4 and string.sub(n, -4) == "spot"
end

local function hide(inst)
	if not isMarker(inst) then return false end
	inst.Transparency = 1
	inst.CanCollide   = false
	inst.CanQuery     = false
	return true
end

local seen = {} -- name -> count, purely so the log says what was actually caught

local function hideAndCount(inst)
	if hide(inst) then
		local n = string.lower(inst.Name)
		seen[n] = (seen[n] or 0) + 1
		return true
	end
	return false
end

local total = 0
for _, d in ipairs(Workspace:GetDescendants()) do
	if hideAndCount(d) then total += 1 end
end

local parts = {}
for n, c in pairs(seen) do parts[#parts + 1] = ("%s x%d"):format(n, c) end
table.sort(parts)
print(("[HideMarkers] hid %d placement marker(s) -- invisible, no collision%s")
	:format(total, (#parts > 0) and (": " .. table.concat(parts, ", ")) or ""))

Workspace.DescendantAdded:Connect(function(d)
	-- one beat: properties are not always populated on the frame an instance replicates in
	task.defer(function()
		if d.Parent then pcall(hideAndCount, d) end
	end)
end)
