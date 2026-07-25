-- ============================================================================================
-- REBIRTH TAG (client) -- renders the player's REBIRTH LEVEL above every player's head.
--
-- Attribute-driven (like TitleTags): the server sets the "Rebirths" player attribute (RebirthSystem), which
-- replicates to EVERY client automatically, so this needs no remotes -- each client watches every player's
-- "Rebirths" attribute and draws a small purple/gold billboard. Sits ABOVE the title tag so both can show.
-- Cosmetic only; only appears once a player has rebirthed at least once.
-- ============================================================================================

local Players = game:GetService("Players")

local TAG_NAME = "RebirthLevelTag"
local COL_PURPLE = Color3.fromRGB(190, 130, 255)
local COL_GOLD   = Color3.fromRGB(255, 214, 90)

local function apply(player, character)
	if not (player and character) then return end
	local head = character:FindFirstChild("Head")
	if not head then return end

	local old = head:FindFirstChild(TAG_NAME); if old then old:Destroy() end

	local n = tonumber(player:GetAttribute("Rebirths")) or 0
	if n < 1 then return end -- no rebirths yet -> nothing to draw

	local bb = Instance.new("BillboardGui")
	bb.Name = TAG_NAME; bb.Adornee = head
	bb.Size = UDim2.new(0, 150, 0, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0) -- above the title tag (2.6) + the default nametag
	bb.AlwaysOnTop = false; bb.MaxDistance = 130; bb.LightInfluence = 0; bb.Parent = head

	-- little rounded pill so the level reads clearly at a distance
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(0.5, 0.5); pill.Position = UDim2.fromScale(0.5, 0.5); pill.Size = UDim2.new(1, 0, 1, 0)
	pill.BackgroundColor3 = Color3.fromRGB(58, 30, 84); pill.BackgroundTransparency = 0.15; pill.Parent = bb
	local corner = Instance.new("UICorner", pill); corner.CornerRadius = UDim.new(1, 0)
	local pstroke = Instance.new("UIStroke", pill); pstroke.Color = COL_GOLD; pstroke.Thickness = 1.5

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -10, 1, -6); lbl.Position = UDim2.fromScale(0.5, 0.5); lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.FredokaOne; lbl.TextScaled = true; lbl.TextColor3 = COL_PURPLE
	lbl.Text = "\xF0\x9F\x94\x84 Rebirth " .. n; lbl.Parent = pill
	local s = Instance.new("UIStroke", lbl); s.Color = Color3.new(0, 0, 0); s.Thickness = 2
end

local function watch(player)
	if player.Character then apply(player, player.Character) end
	player.CharacterAdded:Connect(function(char) char:WaitForChild("Head", 10); apply(player, char) end)
	player:GetAttributeChangedSignal("Rebirths"):Connect(function() apply(player, player.Character) end)
end

for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(watch)

print("[RebirthTag] ready -- rebirth level renders above every player's head (attribute-driven)")
