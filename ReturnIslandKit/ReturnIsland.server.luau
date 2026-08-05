--======================================================================
-- ReturnIsland.server.luau   (ServerScriptService, Script)
--======================================================================
-- "RETURN TO <HIGHEST PLACE YOU REACHED>" -- the fall-catch safety button.
--
-- PORTABLE COPY of the feature from Fart to Float (CoreClient's ReturnIslandGui + PlayerStats'
-- ReturnToIslandEvent / ReturnPromptIsland driver), cut free of that game so any realm can drop it in.
--
-- WHAT IT DOES
--   * Watches every player's height against the highest anchor they have reached.
--   * The moment they are below it by more than CONFIG.CATCH_MARGIN studs, it sets an attribute on them
--     (ReturnPromptIsland = that anchor's index). The client script shows the button off that attribute.
--   * Tapping asks the server to put them back. THE SERVER DOES THE TELEPORT -- see below.
--   * There is NO auto-teleport. Falling is part of the game; the player chooses to give up on the fall.
--
-- ===== WHY THE SERVER OWNS THE TELEPORT =====
-- A client that can move its own character to an arbitrary point is a client that can move it to the top
-- of the map. The button therefore sends an empty "I tapped it" and nothing else -- no position, no index,
-- no target. The server recomputes which anchor the player has actually reached and teleports them there
-- itself. A hacked client can spam the remote and the worst it achieves is being put back somewhere it had
-- already earned. Never accept a destination from the client here, however convenient it looks.
--
-- ===== WHAT COUNTS AS "REACHED" =====
-- Two sources, in order:
--   1. A leaderstats IntValue (CONFIG.PROGRESS_STAT, default "Island") if the realm keeps one. That is
--      persistent progress and survives a rejoin.
--   2. Otherwise, the highest anchor the player has been at or above THIS SESSION, tracked below.
-- The second exists so a realm with no progression stat still gets a working button. If your realm has a
-- saved "furthest reached" value, point PROGRESS_STAT at it -- it is strictly better.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

--======================================================================
-- CONFIG
--======================================================================
local CONFIG = {
	-- ---- WHERE THE ANCHORS ARE ------------------------------------------------------
	-- A part is an anchor if it carries this attribute, whose value is the anchor's INDEX (1, 2, 3...).
	-- Tag one part per island/platform in Studio: Attributes -> add a number named ReturnAnchor.
	--
	-- Prefer this to naming conventions. A name match ("Island3") breaks the first time somebody renames a
	-- model; an attribute is attached to the thing itself and survives being moved, renamed or reparented.
	ANCHOR_ATTRIBUTE = "ReturnAnchor",

	-- Fallback if you would rather not tag anything: parts named PREFIX .. n directly under this folder.
	-- Leave FOLDER nil to disable the fallback entirely.
	FALLBACK_FOLDER  = nil,      -- e.g. Workspace:WaitForChild("Islands")
	FALLBACK_PREFIX  = "Island", -- looks for Island1, Island2, ... inside that folder

	-- ---- WHEN THE BUTTON APPEARS ----------------------------------------------------
	CATCH_MARGIN = 60,   -- studs BELOW the anchor before the prompt appears. Too small and the button
	                     -- flickers on every hop; too large and a falling player waits to be offered help.

	-- ---- WHERE THEY LAND ------------------------------------------------------------
	DROP_HEIGHT  = 6,    -- studs above the anchor's top face, so they land ON it rather than inside it
	FACE_CENTRE  = true, -- turn them to face the anchor's centre, so "back" doesn't also mean "disoriented"

	-- ---- PROGRESS -------------------------------------------------------------------
	PROGRESS_STAT = "Island", -- leaderstats IntValue naming the furthest anchor reached; nil to ignore

	-- ---- RATE ------------------------------------------------------------------------
	CHECK_HZ = 5,   -- how often the height check runs. 5/sec is plenty and costs nothing; per-frame is waste.
}

--======================================================================
-- REMOTE
--======================================================================
local function getOrCreate(parent, class, name)
	local e = parent:FindFirstChild(name)
	if not e then e = Instance.new(class); e.Name = name; e.Parent = parent end
	return e
end
local ReturnToIslandEvent = getOrCreate(ReplicatedStorage, "RemoteEvent", "ReturnToIslandEvent")

--======================================================================
-- THE ANCHORS
--======================================================================
-- Rebuilt on demand rather than cached once at startup: with StreamingEnabled, and in any realm that builds
-- its world from a script, the parts do not all exist on the first frame. A stale cache here means the
-- button silently does nothing for the islands that loaded late -- which looks exactly like a broken button.
local anchorCache, anchorCacheAt = {}, 0

local function rebuildAnchors()
	local found = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			local idx = tonumber(d:GetAttribute(CONFIG.ANCHOR_ATTRIBUTE))
			if idx and idx > 0 then found[idx] = d end
		end
	end
	if next(found) == nil and CONFIG.FALLBACK_FOLDER then
		for i = 1, 64 do
			local p = CONFIG.FALLBACK_FOLDER:FindFirstChild(CONFIG.FALLBACK_PREFIX .. i, true)
			if p and p:IsA("BasePart") then found[i] = p end
		end
	end
	anchorCache, anchorCacheAt = found, os.clock()
	return found
end

local function anchors()
	if os.clock() - anchorCacheAt > 5 then return rebuildAnchors() end
	return anchorCache
end

local function anchorTopY(part)
	return part.Position.Y + part.Size.Y / 2
end

--======================================================================
-- HOW FAR HAVE THEY GOT
--======================================================================
local sessionBest = {} -- [player] = highest anchor index they have been at or above this session

local function highestReached(player)
	local best = 0
	if CONFIG.PROGRESS_STAT then
		local ls = player:FindFirstChild("leaderstats")
		local v = ls and ls:FindFirstChild(CONFIG.PROGRESS_STAT)
		if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then best = math.floor(v.Value) end
	end
	best = math.max(best, sessionBest[player] or 0)

	-- Clamp DOWN to an anchor that actually exists. A progression stat can legitimately run ahead of the
	-- anchors (an island unlocked by a shop purchase, a part that has not streamed in yet), and teleporting
	-- to an anchor that is not there is a fall through the void. Walk down to the highest one we can see.
	local a = anchors()
	while best > 1 and not a[best] do best = best - 1 end
	return best
end

--======================================================================
-- THE TELEPORT
--======================================================================
local function putOnAnchor(char, part)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and part) then return false end
	local target = Vector3.new(part.Position.X, anchorTopY(part) + CONFIG.DROP_HEIGHT, part.Position.Z)
	if CONFIG.FACE_CENTRE then
		-- Face the anchor's centre from slightly outside it, so they arrive looking AT the thing they
		-- returned to rather than off the edge of it.
		local from = target + Vector3.new(0, 0, math.max(6, part.Size.Z / 2 + 4))
		char:PivotTo(CFrame.lookAt(from, Vector3.new(target.X, from.Y, target.Z)))
	else
		char:PivotTo(CFrame.new(target))
	end
	-- Kill the fall. Without this they arrive carrying whatever downward velocity they had and drop
	-- straight back off, which reads as the button not working.
	hrp.AssemblyLinearVelocity = Vector3.zero
	return true
end

ReturnToIslandEvent.OnServerEvent:Connect(function(player)
	-- The client sends NOTHING. Everything below is recomputed here; see the header.
	local n = highestReached(player)
	if n <= 1 then return end                      -- nowhere to return TO
	local part = anchors()[n]
	if not part then
		warn(("[Return] %s tapped but anchor %d is not loaded yet"):format(player.Name, n))
		return
	end
	local char = player.Character
	if not (char and char:FindFirstChild("HumanoidRootPart")) then return end

	-- ALWAYS honour the tap. It deliberately does NOT re-check the below-margin condition: the button is
	-- only ever shown while the player is below home, and re-testing here meant a player who tapped just as
	-- they crossed back over the line got a silent no-op -- a button that sometimes does nothing is worse
	-- than one that occasionally repositions you three studs. It cannot skip progress either way: the only
	-- destination it can ever produce is somewhere the player already reached.
	if putOnAnchor(char, part) then
		player:SetAttribute("ReturnPromptIsland", 0)
		print(("[Return] %s returned to anchor %d"):format(player.Name, n))
	end
end)

--======================================================================
-- THE PROMPT DRIVER
--======================================================================
-- Sets ReturnPromptIsland on every player: the anchor index to offer, or 0 for "hide the button".
-- Shown whenever they are below home -- flying, falling or standing. Hidden only on or above it.
task.spawn(function()
	local period = 1 / math.max(1, CONFIG.CHECK_HZ)
	while true do
		task.wait(period)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local a = anchors()
				local y = hrp.Position.Y

				-- session progress: the highest anchor they are at or above right now
				local reachedNow = 0
				for idx, part in pairs(a) do
					if y >= anchorTopY(part) - 2 and idx > reachedNow then reachedNow = idx end
				end
				if reachedNow > (sessionBest[plr] or 0) then sessionBest[plr] = reachedNow end

				local home = highestReached(plr)
				local want = 0
				if home > 1 then
					local part = a[home]
					if part and y < anchorTopY(part) - CONFIG.CATCH_MARGIN then want = home end
				end
				if (plr:GetAttribute("ReturnPromptIsland") or 0) ~= want then
					plr:SetAttribute("ReturnPromptIsland", want)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) sessionBest[p] = nil end)

print(("[Return] ready -- anchors by '%s' attribute, %d-stud catch margin, server-authoritative teleport")
	:format(CONFIG.ANCHOR_ATTRIBUTE, CONFIG.CATCH_MARGIN))
