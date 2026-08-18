--======================================================================
-- IslandNameTag.client.lua  (LocalScript)
--======================================================================
-- Every player's name is coloured by the highest island they have reached. White at Bean Farm, gold at
-- Pizza Palms. Rank you can read across a crowded spawn without opening anything.
--
-- ===== IT REPLACES THE DEFAULT NAMEPLATE, IT DOES NOT ADD A FOURTH ONE =====
-- There are already two custom billboards stacked over every head -- TitleTags at 2.6 studs and RebirthTag at
-- 3.5 -- sitting on top of Roblox's own nameplate. Adding a third would make a totem pole out of every
-- player. So this hides the default plate (DisplayDistanceType = None) and draws the name itself at 1.9,
-- which slots UNDER the existing two and leaves the stack the same height it already was.
--
-- Nothing else in the game touches the player nameplate: the other DisplayDistanceType writes in this
-- codebase are all on NPCs (shopkeeper, gardener, island quest givers, the squirrel).
--
-- ===== WHY IT READS AN ATTRIBUTE =====
-- HighestIsland is a replicated player attribute that PlayerStats sets on load, on every island change and
-- on rebirth -- the same mechanism RebirthTag reads "Rebirths" from. That means this needs no remote, no
-- server script, and it is correct for OTHER players automatically, which is the entire point of a rank tag.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

if _G.__IslandNameTagClient then
	warn("[IslandNameTag] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__IslandNameTagClient = true

local TAG_NAME = "IslandNameTag"
local HEIGHT   = 1.9   -- studs above the head: below TitleTags (2.6) and RebirthTag (3.5)

--======================================================================
-- THE LADDER
--======================================================================
-- Bands, not a per-island colour. Fourteen shades nobody can tell apart is a legend to memorise; six bands
-- with a clear jump between them is something you read at a glance from across the spawn.
local function bandFor(island)
	if island >= 14 then return Color3.fromRGB(255, 206, 92),  Color3.fromRGB(120, 78, 0)    -- gold
	elseif island >= 12 then return Color3.fromRGB(255, 158, 88), Color3.fromRGB(112, 52, 0)  -- orange
	elseif island >= 9  then return Color3.fromRGB(196, 150, 240), Color3.fromRGB(60, 28, 96)  -- purple
	elseif island >= 6  then return Color3.fromRGB(120, 186, 255), Color3.fromRGB(12, 48, 104) -- blue
	elseif island >= 3  then return Color3.fromRGB(150, 216, 120), Color3.fromRGB(24, 74, 20)  -- green
	else return Color3.fromRGB(245, 245, 250), Color3.fromRGB(30, 30, 40) end                  -- white
end

--======================================================================
-- BUILD / REFRESH
--======================================================================
local function apply(plr, char)
	char = char or plr.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if not (head and hum) then return end

	-- hide Roblox's plate; ours takes its place rather than sitting on top of it
	pcall(function() hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)

	local bb = head:FindFirstChild(TAG_NAME)
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = TAG_NAME
		bb.Adornee = head
		bb.Size = UDim2.fromOffset(200, 26)
		bb.StudsOffsetWorldSpace = Vector3.new(0, HEIGHT, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 120  -- the default plate fades out too; a rank tag readable from orbit is noise
		bb.Parent = head
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Name"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.Parent = bb
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = 15; c.Parent = lbl
		local st = Instance.new("UIStroke"); st.Name = "Edge"; st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; st.Parent = lbl
	end

	local island = math.clamp(math.floor(tonumber(plr:GetAttribute("HighestIsland")) or 1), 1, 14)
	local fill, edge = bandFor(island)
	local lbl = bb:FindFirstChild("Name")
	if lbl then
		lbl.Text = plr.DisplayName or plr.Name
		lbl.TextColor3 = fill
		local st = lbl:FindFirstChild("Edge")
		if st then st.Color = edge end
	end
end

--======================================================================
-- WIRE UP
--======================================================================
local function track(plr)
	-- CharacterAdded rebuilds the head, so the tag has to be rebuilt with it -- this is why the tag is not
	-- created once and forgotten.
	plr.CharacterAdded:Connect(function(char)
		-- the Head can arrive a frame or two after the model does
		task.spawn(function()
			for _ = 1, 40 do
				if char:FindFirstChild("Head") then break end
				task.wait(0.1)
			end
			apply(plr, char)
		end)
	end)
	plr:GetAttributeChangedSignal("HighestIsland"):Connect(function() apply(plr) end)
	if plr.Character then apply(plr, plr.Character) end
end

for _, plr in ipairs(Players:GetPlayers()) do track(plr) end
Players.PlayerAdded:Connect(track)

-- Slow sweep. Attributes and characters can both land while this client is still booting, and a missed
-- CharacterAdded means one player wears no tag for their whole session. Re-applying is idempotent -- apply()
-- reuses the existing billboard -- so the cost of this is a table walk every few seconds.
task.spawn(function()
	while true do
		task.wait(5)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if char and char:FindFirstChild("Head") and not char.Head:FindFirstChild(TAG_NAME) then
				apply(plr, char)
			end
		end
	end
end)

print("[IslandNameTag] ready -- player names tinted by highest island (6 bands, replaces the default plate)")
