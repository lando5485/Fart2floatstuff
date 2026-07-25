-- ============================================================================================
-- TITLE TAGS (client) -- renders the floating TITLE above every player's head.
--
-- A title is a pure BRAG REWARD: it is not buyable, not earnable by playtime, and grants no gameplay
-- advantage whatsoever. It is granted by the server (currently only by Pet Hub collection milestones --
-- see COLLECTION_MILESTONES in PetSystem) and stored as the player attribute "Title".
--
-- WHY AN ATTRIBUTE: player attributes replicate to EVERY client automatically, so this script needs no
-- remotes at all -- each client simply watches every player's "Title" attribute and draws a billboard.
-- The server sets it once; everyone sees it, including late joiners, with no sync code.
--
-- Cosmetic only. Never touches flight, gas, coins, or any stat.
-- ============================================================================================

local Players = game:GetService("Players")

local TAG_NAME = "PlayerTitleTag"

-- Look for the title colour the server picked; fall back to gold. Kept in one place so a new title only
-- needs an entry here to get its own colour (unknown titles still render, just in the default gold).
local TITLE_COLOR = {
	["Pet Collector"] = Color3.fromRGB(80, 220, 140),  -- matches the Collector gut skin (green)
	["Beastmaster"]   = Color3.fromRGB(255, 190, 50),  -- matches the Beastmaster gut skin (gold)
}
local DEFAULT_COLOR = Color3.fromRGB(255, 215, 0)

-- Build (or rebuild) the billboard above one character's head.
local function applyTitle(player, character)
	if not (player and character) then return end
	local head = character:FindFirstChild("Head")
	if not head then return end

	local old = head:FindFirstChild(TAG_NAME)
	if old then old:Destroy() end

	local title = player:GetAttribute("Title")
	if type(title) ~= "string" or title == "" then return end -- no title -> nothing to draw

	local color = TITLE_COLOR[title] or DEFAULT_COLOR

	local bb = Instance.new("BillboardGui")
	bb.Name = TAG_NAME
	bb.Adornee = head
	bb.Size = UDim2.new(0, 200, 0, 34)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0) -- sits above the default Roblox nametag
	bb.AlwaysOnTop = false                            -- respects walls; a title shouldn't shine through terrain
	bb.MaxDistance = 120
	bb.LightInfluence = 0
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = color
	lbl.Text = title
	lbl.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = lbl

	print("[TitleTags] rendered title '" .. title .. "' above " .. player.Name)
end

-- Watch ONE player: draw their title now, redraw it whenever it changes, and re-draw on every respawn
-- (a fresh character = a fresh Head, so the old billboard is gone with the old body).
local function watch(player)
	if player.Character then applyTitle(player, player.Character) end
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 10)
		applyTitle(player, char)
	end)
	player:GetAttributeChangedSignal("Title"):Connect(function()
		applyTitle(player, player.Character) -- title earned/changed mid-session -> appears immediately, no rejoin
	end)
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end -- players already here when this script starts
Players.PlayerAdded:Connect(watch)

print("[TitleTags] ready -- titles render above every player's head (attribute-driven, no remotes)")
