--======================================================================
-- DinoPortal.client.luau  (LocalScript)   [SENDING PLACE]
--======================================================================
-- TEMPLATE -- the CLIENT half of the Dino Realm transition. Mirrors WorldClient's black-hole orb.
-- Its ONLY jobs are: (1) detect that the local player touched the portal, (2) fire INTENT to the
-- server, (3) render whatever status string the server sends back. It NEVER teleports anyone --
-- the server does that (see DinoRealmTeleport.server.lua).
--
-- FINDING THE PORTAL: this looks for a Part/Model named "DinoPortal" anywhere in Workspace, so you
-- can just build one in Studio and name it. If you'd rather build it in code, replace findPortal().
--======================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---- status message (centred, same slot the Space Realm message uses) ----
local msgGui = Instance.new("ScreenGui")
msgGui.Name = "DinoRealmMsg"; msgGui.ResetOnSpawn = false; msgGui.IgnoreGuiInset = true
msgGui.DisplayOrder = 60; msgGui.Parent = playerGui

local msgLbl = Instance.new("TextLabel")
msgLbl.AnchorPoint = Vector2.new(0.5, 0.5)
msgLbl.Position = UDim2.new(0.5, 0, 0.42, 0)
msgLbl.Size = UDim2.new(0, 540, 0, 72)
msgLbl.BackgroundColor3 = Color3.fromRGB(12, 34, 16)
msgLbl.BackgroundTransparency = 1 -- box hidden until there's a real message
msgLbl.Font = Enum.Font.FredokaOne
msgLbl.TextSize = 30
msgLbl.TextColor3 = Color3.fromRGB(190, 255, 190)
msgLbl.Text = ""
msgLbl.Visible = false
msgLbl.Parent = msgGui
Instance.new("UICorner", msgLbl).CornerRadius = UDim.new(0, 14)
local mstk = Instance.new("UIStroke", msgLbl); mstk.Color = Color3.fromRGB(90, 200, 90); mstk.Thickness = 2

local function showMsg(t) msgLbl.Text = t; msgLbl.BackgroundTransparency = 0.2; msgLbl.Visible = true end
local function hideMsg() msgLbl.Visible = false; msgLbl.BackgroundTransparency = 1; msgLbl.Text = "" end

-- ---- the remote ----
local enterEvent = ReplicatedStorage:WaitForChild("DinoRealmEnterEvent", 30)
if not enterEvent then
	warn("[DinoPortal] DinoRealmEnterEvent missing -- is DinoRealmTeleport.server.lua running?")
	return
end

local traveling = false -- local debounce (one touch -> one intent)

-- The SERVER decides what we show. We just render the string it hands us.
enterEvent.OnClientEvent:Connect(function(status)
	if status == "traveling" then
		showMsg("\xF0\x9F\xA6\x96 Traveling to the Dino Realm...")
		-- FAILSAFE: if the teleport never lands (Studio, or a TeleportAsync error), don't strand the box.
		task.delay(5, function() if traveling then hideMsg(); traveling = false end end)
	elseif status == "locked" then
		showMsg("\xF0\x9F\x94\x92 Dino Realm \xE2\x80\x94 Coming soon!")
		task.delay(2.5, function() hideMsg(); traveling = false end)
	elseif status == "error" then
		showMsg("Couldn't travel right now, try again")
		task.delay(2.5, function() hideMsg(); traveling = false end)
	end
end)

-- ---- wire the portal's touch ----
local function wire(part)
	part.CanTouch = true
	part.Touched:Connect(function(hit)
		if traveling then return end
		local char = player.Character
		if not (char and hit and hit:IsDescendantOf(char)) then return end -- ONLY the local player's own body
		traveling = true
		pcall(function() enterEvent:FireServer() end) -- INTENT ONLY. No arguments. The server gates + teleports.
	end)
end

local function findPortal()
	local p = Workspace:FindFirstChild("DinoPortal", true)
	if not p then return nil end
	if p:IsA("BasePart") then return { p } end
	if p:IsA("Model") then
		local parts = {}
		for _, d in ipairs(p:GetDescendants()) do
			if d:IsA("BasePart") then parts[#parts + 1] = d end
		end
		return parts
	end
	return nil
end

task.spawn(function()
	local parts, waited = findPortal(), 0
	while not parts and waited < 30 do -- the portal may stream/build in after us
		task.wait(0.5); waited = waited + 0.5; parts = findPortal()
	end
	if not parts then
		warn("[DinoPortal] no Part/Model named 'DinoPortal' found in Workspace -- nothing to touch")
		return
	end
	for _, p in ipairs(parts) do wire(p) end
	print("[DinoPortal] ready -- wired " .. #parts .. " part(s) of 'DinoPortal'")
end)
