-- ItemStands.server.lua -- SWORD + GUN purchase stands, cloned from the existing Speed Coil stand.
--
-- HOW THIS WORKS: it does NOT build a dummy from scratch. It finds your real Speed Coil rig ("noob"),
-- :Clone()s it whole -- every part, accessory, hat and weld comes along for free -- then swaps ONLY the
-- part it holds. Same deal for the pad and the two BillboardGui labels: cloned from yours, so styling
-- (pink name / green price) is inherited rather than re-created and can never drift out of sync.
--
-- OWNERSHIP: these are Developer Products (repeatable by nature), but the player OWNS THE ITEM FOREVER.
-- So ownership is persisted here in a DataStore, and the tool is re-granted on every respawn. Once owned,
-- stepping on the pad just hands the tool over again -- it does not re-prompt for Robux.
--
-- RECEIPTS: PlayerStats owns the place's SINGLE MarketplaceService.ProcessReceipt (only one script may).
-- This script does NOT assign it. It registers _G.standsHandleReceipt, which PlayerStats calls -- the same
-- hook pattern already used by _G.gardenHandleDonationReceipt and _G.petsHandleReceipt.

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService    = game:GetService("DataStoreService")
local ServerStorage       = game:GetService("ServerStorage")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")

-- ============================================================================
-- CONFIG -- the only part you should need to touch.
-- ============================================================================

-- >>> PUT YOUR REAL DEVELOPER PRODUCT IDS HERE. While these are 0 the stand still builds, but the pad
-- >>> warns instead of prompting (a PromptProductPurchase on id 0 throws).
local ITEMS = {
	{
		key            = "Sword",
		displayName    = "Sword",          -- pink name label text
		productId      = 0,                -- <<< FILL IN
		toolName       = "ClassicSword",   -- the Tool itself (lives inside your "Sword giver" model)
		placementIndex = 1,                -- which "placementpart" to stand on (see startup print)
	},
	{
		key            = "Gun",
		displayName    = "Hyper Laser Gun",
		productId      = 0,                -- <<< FILL IN
		toolName       = "hyperlasergun",
		placementIndex = 2,
	},
}

-- Names of the EXISTING Speed Coil objects used as templates.
local TEMPLATE_DUMMY_NAME = "noob"
local TEMPLATE_PAD_NAME   = "SpeedCoil Gamepass Button!"
local PLACEMENT_PART_NAME = "placementpart"

local PRICE_LABEL_MARKER  = "Robux"   -- the price label is the one whose text mentions Robux; the other is the name
local TOUCH_DEBOUNCE      = 2         -- seconds, per player per pad

-- ============================================================================

local ownedStore = DataStoreService:GetDataStore("ItemStandOwnership_v1")

-- =====================  FINDING YOUR EXISTING STUFF  =====================

-- Recursive find-by-name, first match. Used instead of hardcoded paths so it doesn't matter whether your
-- stand sits at workspace.SpeedCoilStand, workspace.Shop.Coil, or loose in Workspace.
local function findByName(root, name)
	if root.Name == name then return root end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then return d end
	end
	return nil
end

-- The Tool to sell. Searched across the usual homes; your two tools live in different places (the gun as a
-- plain Tool, the sword nested inside a "Sword giver" model), so we search rather than assume one path.
local function findTool(name)
	for _, container in ipairs({ ServerStorage, ReplicatedStorage, workspace }) do
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("Tool") and d.Name == name then return d end
		end
	end
	return nil
end

-- The part the dummy is HOLDING. This deliberately skips Accessory handles: every hat on an R15 rig also
-- contains a BasePart named "Handle", so a naive FindFirstChild("Handle", true) would grab the dummy's hat
-- and weld a sword to its head. We take a Tool's Handle if one is equipped, otherwise the first loose part
-- named Handle whose parent is NOT an Accessory.
local function findHeldHandle(rig)
	local tool = rig:FindFirstChildOfClass("Tool")
	if tool then
		local h = tool:FindFirstChild("Handle")
		if h and h:IsA("BasePart") then return h end
	end
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Handle" and not d.Parent:IsA("Accessory") then
			return d
		end
	end
	return nil
end

-- Whatever the old handle was joined to (the hand). Falls back to the rig's hand part by name if the joint
-- can't be read, so an anchored/unwelded template still works.
local function findGripPart(rig, handle)
	for _, d in ipairs(rig:GetDescendants()) do
		-- JointInstance (Weld/Motor6D) and WeldConstraint both expose Part0/Part1, so one branch covers both.
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			if d.Part0 == handle and d.Part1 then return d.Part1 end
			if d.Part1 == handle and d.Part0 then return d.Part0 end
		end
	end
	return rig:FindFirstChild("RightHand") or rig:FindFirstChild("Right Arm")
end

-- Your two BillboardGuis. Classified by CONTENT, not by name, so I don't have to guess what you called them:
-- the one whose text mentions "Robux" is the price, the other is the name.
local function findLabels(scope)
	local nameGui, priceGui
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("BillboardGui") then
			local isPrice = false
			for _, g in ipairs(d:GetDescendants()) do
				if g:IsA("TextLabel") and string.find(g.Text, PRICE_LABEL_MARKER, 1, true) then
					isPrice = true
					break
				end
			end
			if isPrice then priceGui = priceGui or d else nameGui = nameGui or d end
		end
	end
	return nameGui, priceGui
end

local function setGuiText(gui, text)
	if not gui then return end
	for _, g in ipairs(gui:GetDescendants()) do
		if g:IsA("TextLabel") then
			g.Text = text -- colour/font/size left exactly as your template had them
			return
		end
	end
end

-- =====================  OWNERSHIP  =====================

local owned = {} -- [userId] = { [itemKey] = true }

local function ownershipKey(userId) return "u_" .. userId end

local function loadOwnership(player)
	local data
	local ok = pcall(function()
		data = ownedStore:GetAsync(ownershipKey(player.UserId))
	end)
	if not ok then
		-- Do NOT default to an empty set on a DataStore failure -- that would look like "owns nothing" and
		-- could re-charge a player who already bought. Leave them nil; grants are skipped until a load works.
		warn("[ItemStands] ownership load FAILED for " .. player.Name .. " -- not granting this session")
		return
	end
	owned[player.UserId] = data or {}
end

local function saveOwnership(userId)
	local set = owned[userId]
	if not set then return end
	pcall(function() ownedStore:SetAsync(ownershipKey(userId), set) end)
end

local function ownsItem(player, key)
	local set = owned[player.UserId]
	return set ~= nil and set[key] == true
end

-- Puts the tool in the Backpack, and in StarterGear so it survives respawns/resets too.
local function giveTool(player, item)
	local source = findTool(item.toolName)
	if not source then
		warn("[ItemStands] cannot grant '" .. item.displayName .. "': no Tool named '" .. item.toolName .. "' found")
		return false
	end
	local backpack   = player:FindFirstChildOfClass("Backpack")
	local starterGear = player:FindFirstChildOfClass("StarterGear")
	if backpack and not backpack:FindFirstChild(source.Name) then
		source:Clone().Parent = backpack
	end
	if starterGear and not starterGear:FindFirstChild(source.Name) then
		source:Clone().Parent = starterGear
	end
	return true
end

local function grantForever(player, item)
	owned[player.UserId] = owned[player.UserId] or {}
	owned[player.UserId][item.key] = true
	saveOwnership(player.UserId)
	giveTool(player, item)
end

-- =====================  BUILD THE STANDS  =====================

local dummyTemplate = findByName(workspace, TEMPLATE_DUMMY_NAME)
local padTemplate   = findByName(workspace, TEMPLATE_PAD_NAME)

if not dummyTemplate then
	warn("[ItemStands] ABORT: no model named '" .. TEMPLATE_DUMMY_NAME .. "' in Workspace")
	return
end
if not padTemplate or not padTemplate:IsA("BasePart") then
	warn("[ItemStands] ABORT: no BasePart named '" .. TEMPLATE_PAD_NAME .. "' in Workspace")
	return
end

-- Labels are searched on the dummy first, then on whatever the dummy is parented under (in case they hang
-- off the pad or a sibling part rather than the rig itself).
local nameTemplate, priceTemplate = findLabels(dummyTemplate)
if not nameTemplate and dummyTemplate.Parent then
	nameTemplate, priceTemplate = findLabels(dummyTemplate.Parent)
end
if not nameTemplate or not priceTemplate then
	warn("[ItemStands] heads up: could not find both label GUIs on the template (name=" ..
		tostring(nameTemplate ~= nil) .. ", price=" .. tostring(priceTemplate ~= nil) ..
		"). Stands will still build; missing labels are skipped.")
end

-- Collect the placement blocks. All three share a name, so they're sorted into a stable order (X then Z) --
-- otherwise :GetDescendants() order could shuffle your stands around between sessions. The startup print
-- below tells you which index landed where so you can retune placementIndex in the config.
local placements = {}
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == PLACEMENT_PART_NAME then
		table.insert(placements, d)
	end
end
table.sort(placements, function(a, b)
	if a.Position.X ~= b.Position.X then return a.Position.X < b.Position.X end
	return a.Position.Z < b.Position.Z
end)

for i, p in ipairs(placements) do
	p.Transparency = 1      -- invisible, as asked
	p.CanCollide   = false  -- and non-solid, so you don't trip on them
	p.Anchored     = true
	print(string.format("[ItemStands] placementpart #%d at %s", i, tostring(p.Position)))
end

local padDebounce = {} -- [padPart] = { [userId] = lastTouchTime }

local function buildStand(item)
	local place = placements[item.placementIndex]
	if not place then
		warn("[ItemStands] skipping '" .. item.displayName .. "': no placementpart #" .. tostring(item.placementIndex))
		return
	end

	local sourceTool = findTool(item.toolName)
	if not sourceTool or not sourceTool:FindFirstChild("Handle") then
		warn("[ItemStands] skipping '" .. item.displayName .. "': Tool '" .. item.toolName ..
			"' missing, or it has no Handle")
		return
	end

	local stand = Instance.new("Model")
	stand.Name = item.key .. "Stand"

	-- The whole rig, accessories and all.
	local rig = dummyTemplate:Clone()
	rig.Name = item.key .. "Dummy"
	rig.Parent = stand

	-- Swap ONLY what it's holding.
	local oldHandle = findHeldHandle(rig)
	if oldHandle then
		local grip      = findGripPart(rig, oldHandle)
		local newHandle = sourceTool.Handle:Clone() -- brings its mesh/decals/sounds with it
		newHandle.Name     = "Handle"
		newHandle.CFrame   = oldHandle.CFrame       -- inherit the exact grip pose
		newHandle.Anchored = oldHandle.Anchored
		newHandle.CanCollide = false
		newHandle.Parent   = rig

		if not newHandle.Anchored and grip then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = newHandle   -- WeldConstraint locks the CURRENT relative CFrame, which we just matched
			weld.Part1 = grip
			weld.Parent = newHandle
		end

		-- Remove the old coil handle (and the Tool wrapper, if it was equipped as a Tool).
		local wrapper = oldHandle.Parent
		oldHandle:Destroy()
		if wrapper and wrapper:IsA("Tool") then wrapper:Destroy() end
	else
		warn("[ItemStands] '" .. item.displayName .. "': template dummy holds no Handle -- rig cloned without an item")
	end

	-- The pad.
	local pad = padTemplate:Clone()
	pad.Name = item.key .. " Button"
	pad.Parent = stand

	-- Labels, cloned so pink/green styling is inherited verbatim; only the text changes.
	if nameTemplate then
		local g = nameTemplate:Clone()
		setGuiText(g, item.displayName)
		g.Parent = pad
		g.Adornee = pad
	end
	if priceTemplate then
		local g = priceTemplate:Clone()
		setGuiText(g, item.productId .. " Robux")
		g.Parent = pad
		g.Adornee = pad
	end

	-- Move the whole assembly. Pivoting on the PAD (not the rig) means the pad lands exactly on the
	-- placement block and the dummy keeps its original offset behind it.
	stand.PrimaryPart = pad
	stand.Parent = workspace
	stand:PivotTo(place.CFrame)

	-- Buy on touch.
	padDebounce[pad] = {}
	pad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local now  = os.clock()
		local last = padDebounce[pad][player.UserId]
		if last and (now - last) < TOUCH_DEBOUNCE then return end
		padDebounce[pad][player.UserId] = now

		-- Already bought it? Just hand it back -- never charge twice.
		if ownsItem(player, item.key) then
			giveTool(player, item)
			return
		end

		if item.productId == 0 then
			warn("[ItemStands] '" .. item.displayName .. "' has no productId set -- purchase prompt skipped")
			return
		end

		MarketplaceService:PromptProductPurchase(player, item.productId)
	end)

	print("[ItemStands] built " .. item.key .. "Stand at placementpart #" .. item.placementIndex)
end

for _, item in ipairs(ITEMS) do
	buildStand(item)
end

-- =====================  RECEIPTS + RESPAWN  =====================

-- Called by PlayerStats' SINGLE MarketplaceService.ProcessReceipt. Returns true if this productId was one of
-- ours (so PlayerStats returns PurchaseGranted), false to let other handlers have a look at it.
_G.standsHandleReceipt = function(player, productId)
	for _, item in ipairs(ITEMS) do
		if item.productId ~= 0 and item.productId == productId then
			grantForever(player, item)
			return true
		end
	end
	return false
end

Players.PlayerAdded:Connect(function(player)
	loadOwnership(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.5) -- let the Backpack exist
		for _, item in ipairs(ITEMS) do
			if ownsItem(player, item.key) then giveTool(player, item) end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	saveOwnership(player.UserId)
	owned[player.UserId] = nil
end)

-- Players already in-game when this script starts (Studio hot-reload / Rojo sync).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadOwnership, player)
end

print("[ItemStands] ready -- " .. #ITEMS .. " stands cloned from the Speed Coil template")
