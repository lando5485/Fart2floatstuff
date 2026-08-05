--======================================================================
-- GardenDonationClient.client.lua  (LocalScript)  -- the DonationChest E-prompt -> "Support the Garden" HUD.
--======================================================================
-- Holding E on the DonationChest's "DonationChestPrompt" (server-created) HINGES the lid open (per-client, purely
-- visual) and opens a native-styled blue panel offering Robux DONATION tiers. Layout: title bar + 2 subtitle lines +
-- a 2x2 grid of green preset cards (25 / 100 / 500 / 1000 R$, each a heart + amount + Donate button) + a thank-you footer.
--
-- PURCHASES: each preset Donate button prompts its matching Robux Developer Product. Robux is granted by the game's
-- SINGLE ProcessReceipt (PlayerStats -> CommunityGarden._G.gardenHandleDonationReceipt), which counts the donor
-- (recordDonor -> unique-donor sign) and broadcasts GardenDonationEvent { name, robux } -> a thank-you banner for
-- everyone. PURE tip jar: no gameplay effect at all. The treasure-box HUD link (the E-prompt) is unchanged.
--======================================================================

local Players              = game:GetService("Players")
local RS                   = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local MarketplaceService   = game:GetService("MarketplaceService")
local TweenService         = game:GetService("TweenService")
local Workspace            = game:GetService("Workspace")
local Debris               = game:GetService("Debris")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== CONSTANTS (product IDs) ========================================================================
-- \xE2\x9A\xA0 REPLACE the 0s with your Robux Developer Product IDs (one per tier). These MUST match the productId
--    values in DONATION_TIERS inside CommunityGarden.server.lua (the server validates the receipt by product id).
local GAMEPASS_IDS = {} -- (donations use no gamepasses; kept for parity / future use)
local PRODUCT_IDS  = { Donate25 = 3608150932, Donate100 = 3608151059, Donate500 = 3608151160, Donate1000 = 3608151576 }

-- the 4 preset tiers, in grid order (source of truth for both the cards and the custom-amount rounding)
local PRESETS = {
	{ amount = 25,   productId = PRODUCT_IDS.Donate25 },
	{ amount = 100,  productId = PRODUCT_IDS.Donate100 },
	{ amount = 500,  productId = PRODUCT_IDS.Donate500 },
	{ amount = 1000, productId = PRODUCT_IDS.Donate1000 },
}

local GardenDonationEvent = RS:WaitForChild("GardenDonationEvent", 30)
if not GardenDonationEvent then return end

-- ===== palette =====
local BLUE_PANEL  = Color3.fromRGB(25, 90, 185)
local BLUE_HEADER = Color3.fromRGB(15, 60, 140)
local CARD_GREEN  = Color3.fromRGB(46, 160, 74)
local BTN_GREEN   = Color3.fromRGB(70, 200, 92)
local BTN_GREEN2  = Color3.fromRGB(38, 150, 66)
local CAN_GREEN   = Color3.fromRGB(74, 196, 100)
local WATER_BLUE  = Color3.fromRGB(150, 210, 255)

-- ===== UI helpers (same ones the shop / reward panels use) =====
local function mkCorner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = p; return c end
local function mkStroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = t; s.Parent = p; return s end
local function mkLabel(p, props) local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; for k, v in pairs(props) do l[k] = v end; l.Parent = p; return l end
local function mkFrame(p, props) local f = Instance.new("Frame"); for k, v in pairs(props) do f[k] = v end; f.Parent = p; return f end
local function mkButton(p, props) local b = Instance.new("TextButton"); for k, v in pairs(props) do b[k] = v end; b.Parent = p; return b end
-- top-lit bevels (a UIGradient that MULTIPLIES the element colour -> subtle 3D depth without darkening it much)
local function juice(p) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.new(1,1,1), Color3.fromRGB(170,170,170)); g.Rotation = 90; g.Parent = p; return g end  -- chunky (buttons)
local function soft(p)  local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.new(1,1,1), Color3.fromRGB(222,222,222)); g.Rotation = 90; g.Parent = p; return g end  -- gentle (panels/cards)

-- A small GREEN WATERING-CAN icon built from frames (body + angled spout + rose + handle loop + water droplets).
-- Purely decorative; parented into whatever `parent` frame the caller gives it.
local function makeWateringCan(parent, holderProps)
	local holder = mkFrame(parent, holderProps or { Size = UDim2.new(0, 56, 0, 56), BackgroundTransparency = 1 })
	local body   = mkFrame(holder, { Size = UDim2.new(0, 30, 0, 26), Position = UDim2.new(0.58, 0, 1, -3), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = CAN_GREEN }); mkCorner(body, 7)
	local spout  = mkFrame(holder, { Size = UDim2.new(0, 24, 0, 8),  Position = UDim2.new(0.20, 0, 0.44, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = CAN_GREEN, Rotation = -32 }); mkCorner(spout, 4)
	local rose   = mkFrame(holder, { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0.04, 0, 0.30, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = CAN_GREEN }); mkCorner(rose, 6)
	local handle = mkFrame(holder, { Size = UDim2.new(0, 22, 0, 16), Position = UDim2.new(0.70, 0, 0.28, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }); mkCorner(handle, 8); mkStroke(handle, CAN_GREEN, 4)
	for _, off in ipairs({ { 0.00, 0.06 }, { 0.09, 0.18 }, { -0.05, 0.22 } }) do
		local d = mkFrame(holder, { Size = UDim2.new(0, 5, 0, 5), Position = UDim2.new(0.04 + off[1], 0, 0.42 + off[2], 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WATER_BLUE }); mkCorner(d, 3)
	end
	return holder
end

-- forward-declared UI handles + functions
local gui, panel, noticeLbl
local buildHUD, openHUD, promptDonate, setNotice, showThanks

--======================================================================
-- ONE CHEST, ONE HUD
--======================================================================
-- An OLD copy of this LocalScript is baked into the place, so Rojo adds this one BESIDE it and both run: two
-- scripts hook the same DonationChestPrompt and each builds its own "GardenDonationGui", which is why holding E
-- opened two donation panels stacked on each other. THIS file is the newer panel (gold title bar, 2x2 tier grid),
-- so it wins: the stale script and any donation GUI it built get removed.
--
-- SURGICAL ON PURPOSE. It only ever touches LocalScripts with this script's exact name and ScreenGuis named
-- exactly GardenDonationGui that this script did not create -- never a blanket PlayerGui sweep, which has broken
-- unrelated HUDs here before.
local function claimDonationHud()
	for _, container in ipairs({ script.Parent, player:FindFirstChild("PlayerScripts"), PlayerGui }) do
		if container then
			for _, inst in ipairs(container:GetDescendants()) do
				if inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
					pcall(function() inst.Disabled = true; inst:Destroy() end)
					warn("[GardenDonate] removed a STALE duplicate GardenDonationClient -- delete it in Studio for good")
				end
			end
		end
	end
	for _, inst in ipairs(PlayerGui:GetChildren()) do
		if inst ~= gui and inst:IsA("ScreenGui") and inst.Name == "GardenDonationGui" then
			pcall(function() inst:Destroy() end)
		end
	end
end
claimDonationHud()
-- The stale copy can build its panel later than we run (it waits on the same remote, then on the prompt), so
-- re-check on the same cadence the other duplicate guards in this game use, and watch for one appearing.
task.delay(1, claimDonationHud); task.delay(4, claimDonationHud)
PlayerGui.ChildAdded:Connect(function(inst)
	if inst ~= gui and inst:IsA("ScreenGui") and inst.Name == "GardenDonationGui" then
		task.defer(function() if inst ~= gui and inst.Parent then pcall(function() inst:Destroy() end) end end)
	end
end)

--======================================================================
-- LID HINGE (per-client, purely visual): swing the DonationChest's "Lid" model open about its "LidHinge" attachment,
-- then closed. Anchored server parts are moved locally (renders for us only) and RESTORED to their captured CFrames on
-- close, so nothing is left displaced. Fully pcall-guarded; if the lid/hinge is missing it silently no-ops.
--======================================================================
local lidState = nil
local OPEN_ANGLE = math.rad(-74) -- negative -> the front (latch/-X) rises

local function closeLid()
	if not lidState then return end
	for part, orig in pairs(lidState.parts) do
		if part and part.Parent then
			pcall(function() TweenService:Create(part, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = orig }):Play() end)
		end
	end
	lidState = nil
end

local function openLid(chestModel)
	closeLid()
	local lid = chestModel and chestModel:FindFirstChild("Lid")
	local body = chestModel and chestModel:FindFirstChild("ChestBody")
	local hinge = body and body:FindFirstChild("LidHinge")
	if not (lid and hinge) then return end
	local pivot = hinge.WorldCFrame
	lidState = { parts = {} }
	for _, part in ipairs(lid:GetChildren()) do
		if part:IsA("BasePart") then
			lidState.parts[part] = part.CFrame
			local target = pivot * CFrame.Angles(0, 0, OPEN_ANGLE) * pivot:Inverse() * part.CFrame
			pcall(function() TweenService:Create(part, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = target }):Play() end)
		end
	end
end

-- a gold sparkle burst at the chest (cosmetic)
local function sparkle(pos)
	local host = Instance.new("Part")
	host.Anchored = true; host.CanCollide = false; host.CanQuery = false; host.Transparency = 1
	host.Size = Vector3.new(1, 1, 1); host.CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0)); host.Parent = Workspace
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(255, 180, 40))
	em.Lifetime = NumberRange.new(0.5, 0.95); em.Speed = NumberRange.new(5, 11); em.SpreadAngle = Vector2.new(70, 70)
	em.Rate = 0; em.Size = NumberSequence.new(0.6); em.LightEmission = 0.6; em.Parent = host
	em:Emit(40)
	Debris:AddItem(host, 1.3)
end

--======================================================================
-- PURCHASE HELPERS
--======================================================================
-- Prompt the Robux Developer Product for a tier. Guards the placeholder 0 id so it can't fire a broken prompt.
function promptDonate(productId, amount)
	if productId and productId > 0 then
		pcall(function() MarketplaceService:PromptProductPurchase(player, productId) end)
	else
		setNotice(string.format("The %d R$ tier isn't set up yet.", amount or 0))
	end
end

--======================================================================
-- HUD
--======================================================================
local activeChest
-- Set by buildHUD once the tab bar exists; openHUD calls it so the chest always opens on
-- DONATE rather than on whichever tab you happened to close it on.
local resetTabs

local function closePanel()
	if gui then gui.Enabled = false end
	closeLid()
end

function setNotice(text)
	if noticeLbl then noticeLbl.Text = text or "" end
end

-- ---- shared chrome (the same treatment the Garden Reward chest panel uses) ---------------------------------
-- FIXED 700x520 at the shops' centre, plus the SAME adaptive UIScale every other menu gets from
-- _G.applyHudScaling -- min(vp.X/1280, vp.Y/720, 1). The panel used to be sized in SCALE (0.6 x 0.62), which
-- meant it was a different shape on every screen and never matched the Shop / Pet Hub / crate panels sitting
-- next to it in the same session.
local function hudScale(frame)
	local s = Instance.new("UIScale"); s.Parent = frame
	local function apply()
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		s.Scale = math.min(vp.X / 1280, vp.Y / 720, 1)
	end
	apply()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	return s
end

-- soft navy drop shadow behind a panel: two rounded twins, never black (black on blue reads as grime)
local function dropShadow(frame, radius)
	local parent = frame.Parent
	for i, sp in ipairs({ 54, 30 }) do
		local sh = mkFrame(parent, {
			AnchorPoint = frame.AnchorPoint, Position = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, frame.Position.Y.Scale, frame.Position.Y.Offset + 6),
			Size = UDim2.new(0, frame.Size.X.Offset + sp, 0, frame.Size.Y.Offset + sp),
			BackgroundColor3 = Color3.fromRGB(6, 26, 80), BackgroundTransparency = ({ 0.8, 0.62 })[i],
			BorderSizePixel = 0, ZIndex = 0,
		})
		mkCorner(sh, radius + sp)
	end
end

-- The four tiers get four DIFFERENT identities instead of four identical green boxes -- a kid can tell them
-- apart at a glance, and the ladder (sprout -> sunflower -> tree -> trophy) says "bigger" without reading a
-- number. Colours are the house palette; nothing here changes what any tier costs or grants.
local TIER_LOOK = {
	{ emoji = "\xF0\x9F\x8C\xB1", top = Color3.fromRGB(126, 217,  87), bot = Color3.fromRGB( 74, 168,  42), ink = Color3.fromRGB( 24,  72,  16), tag = nil },
	{ emoji = "\xF0\x9F\x8C\xBB", top = Color3.fromRGB(255, 210,  74), bot = Color3.fromRGB(226, 160,  30), ink = Color3.fromRGB( 96,  60,   4), tag = "POPULAR" },
	{ emoji = "\xF0\x9F\x8C\xB3", top = Color3.fromRGB( 94, 198, 255), bot = Color3.fromRGB( 40, 130, 220), ink = Color3.fromRGB( 10,  48, 100), tag = nil },
	{ emoji = "\xF0\x9F\x8F\x86", top = Color3.fromRGB(226, 158, 255), bot = Color3.fromRGB(150,  86, 224), ink = Color3.fromRGB( 62,  20, 108), tag = "LEGEND" },
}

function buildHUD()
	gui = Instance.new("ScreenGui")
	gui.Name = "GardenDonationGui"; gui.ResetOnSpawn = false; gui.DisplayOrder = 100; gui.Enabled = false; gui.Parent = PlayerGui

	-- dim click-catcher backdrop: it swallows clicks that land off the panel, but does NOT close it
	local backdrop = mkButton(gui, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(6, 26, 80), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false, Active = true })
	-- NOTE: there is deliberately NO click-outside-to-close handler (matching the Pet Hub). The backdrop spans
	-- the whole screen, so a click anywhere off the panel used to slam it shut, which made menus feel like they
	-- closed at random. This panel now closes ONLY on an explicit action: its X button, its own toggle, or
	-- MainMenuManager closing it because another menu opened.

	-- PANEL -- bright house blue, thick white cartoon border, navy shadow underneath
	panel = mkFrame(gui, {
		Size = UDim2.new(0, 700, 0, 520), Position = UDim2.new(0.5, 0, 0.5, -45), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = BLUE_PANEL, ClipsDescendants = true, Active = true, ZIndex = 2,
	})
	mkCorner(panel, 24); mkStroke(panel, Color3.new(1, 1, 1), 4)
	do local g = Instance.new("UIGradient", panel); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(46, 122, 226), BLUE_HEADER) end
	dropShadow(panel, 24)
	hudScale(panel)

	-- TITLE BAR -- gold, because this is the treasure chest's panel and gold is what a chest is full of
	local header = mkFrame(panel, { Size = UDim2.new(1, -28, 0, 66), Position = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Color3.fromRGB(255, 200, 60), ZIndex = 3 })
	mkCorner(header, 16); mkStroke(header, Color3.new(1, 1, 1), 2)
	do local g = Instance.new("UIGradient", header); g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140), Color3.fromRGB(232, 172,  36)) end

	local chestBadge = mkFrame(header, { Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromRGB(255, 248, 224), ZIndex = 4 })
	mkCorner(chestBadge, 12); mkStroke(chestBadge, Color3.fromRGB(180, 120, 20), 2)
	mkLabel(chestBadge, { Text = "\xF0\x9F\x92\xB0", Font = Enum.Font.FredokaOne, TextSize = 26, Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })

	mkLabel(header, { Text = "SUPPORT THE GARDEN", Font = Enum.Font.FredokaOne, TextSize = 30, TextColor3 = Color3.fromRGB(84, 48, 4), Size = UDim2.new(1, -190, 1, 0), Position = UDim2.new(0, 70, 0, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })

	local closeBtn = mkButton(header, { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = Color3.fromRGB(232, 72, 84), Text = "X", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
	mkCorner(closeBtn, 12); mkStroke(closeBtn, Color3.new(1, 1, 1), 2); juice(closeBtn)
	do local cp = Instance.new("UIPadding", closeBtn); for _, s in ipairs({"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"}) do cp[s] = UDim.new(0, 9) end end
	closeBtn.MouseButton1Click:Connect(closePanel)


	--======================================================================
	-- TABS -- DONATE | SEASONAL PETS
	--
	-- Seasonal Pets used to be its own treasure box standing beside this one in the garden:
	-- two near-identical chests, three studs apart, and no way to tell from across the lawn
	-- which one did what. It is a tab in here now. The garden has ONE chest again.
	--
	-- The seasonal page deliberately does NOT rebuild the seasonal grid. That panel already
	-- exists as CoreClient's LockerGui and it re-asks the SERVER who owns what before it
	-- shows -- a second copy of the grid built here would be a second thing that can
	-- disagree with the server about which pets you own. This page is a door to the real one.
	--======================================================================
	local donatePage = mkFrame(panel, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 3 })

	-- SEASONAL PETS IS A DOOR, NOT A PAGE. The tab used to show a card with an "OPEN SEASONAL
	-- PETS" button on it -- a page whose only purpose was to make you press one more thing.
	-- Pressing the tab now opens the real panel directly.
	--
	-- It still does NOT rebuild the seasonal grid: that panel already exists as CoreClient's
	-- LockerGui and it re-asks the SERVER who owns what before it shows, so a copy built here
	-- would be a second thing that can be wrong about which pets you own.
	-- BACK, INSIDE THE SEASONAL PANEL. Going through the tab used to be a one-way door: the chest
	-- closed, LockerGui opened, and the only way out was its X and a second walk to the chest.
	-- A BACK button is injected into LockerGui itself, so the two panels behave like one flow.
	--
	-- It is built ONCE and re-shown, and only ever appears when you arrived FROM the chest -- opening
	-- Seasonal Pets any other way has nothing to go back TO, and a button that lies about where it
	-- leads is worse than no button. LockerGui belongs to CoreClient, so this adds a child and
	-- touches nothing else about it.
	-- ROUND EVERY INNER RECTANGLE. Run over LockerGui rather than authored into it, because that panel
	-- belongs to CoreClient and a stale duplicate of that script can be the one that actually built it --
	-- so patching only the source would fix the copy we can see and miss the one on screen.
	--
	-- Full-width bars are SKIPPED. The header and footer strips run edge to edge and are clipped by the
	-- panel's own rounded corners; rounding them as well would carve visible notches out of the middle
	-- of the panel where the strip meets the straight side wall.
	local function roundCorners(root)
		local panelW = (root.AbsoluteSize and root.AbsoluteSize.X) or 700
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("Frame") or d:IsA("ViewportFrame") or d:IsA("ScrollingFrame")
				or d:IsA("TextButton") or d:IsA("TextLabel") or d:IsA("ImageLabel"))
				and d.BackgroundTransparency < 0.95
				and not d:FindFirstChildOfClass("UICorner")
			then
				local sz = d.AbsoluteSize
				if sz.X > 0 and sz.Y > 0 and (panelW <= 0 or sz.X < panelW * 0.95) then
					local c = Instance.new("UICorner")
					c.CornerRadius = UDim.new(0, math.clamp(math.floor(math.min(sz.X, sz.Y) / 2), 4, 12))
					c.Parent = d
				end
			end
		end
	end

	-- BACK, IN THE HEADER NEXT TO THE X. It used to sit at the panel's top-left, straight on top of the
	-- "Seasonal Pets" title. It is now mirrored off the X button found at runtime -- same size, same
	-- corner radius, same baseline -- and placed one gap to its left, so the two read as a pair.
	--
	-- Its FILL is deliberately not the X's red. Two red buttons side by side both say "leave", and the
	-- one that goes back would be indistinguishable from the one that closes. It takes the header's own
	-- brown instead: matched in shape and weight, distinct in meaning.
	local seasonalBack
	local function ensureSeasonalBack()
		if seasonalBack and seasonalBack.Parent then return seasonalBack end
		local g = PlayerGui:FindFirstChild("LockerGui")
		local host = g and g:FindFirstChild("Frame")
		if not (host and host:IsA("GuiObject")) then return nil end

		-- find the close button: the small square TextButton reading "X" nearest the top-right
		local x
		for _, d in ipairs(host:GetDescendants()) do
			if d:IsA("TextButton") and (d.Text == "X" or d.Text == "\xE2\x9C\x95")
				and d.AbsoluteSize.X <= 60 and (not x or d.AbsolutePosition.Y < x.AbsolutePosition.Y) then
				x = d
			end
		end
		local parent = (x and x.Parent) or host
		local size   = (x and x.Size) or UDim2.new(0, 34, 0, 34)
		local w      = (x and x.AbsoluteSize.X > 0 and x.AbsoluteSize.X) or 34
		local radius = 9
		if x then
			local xc = x:FindFirstChildOfClass("UICorner")
			if xc then radius = xc.CornerRadius.Offset end
		end

		seasonalBack = mkButton(parent, {
			Name = "ChestBack", AnchorPoint = (x and x.AnchorPoint) or Vector2.new(1, 0.5),
			Size = size, Position = (x and UDim2.new(x.Position.X.Scale, x.Position.X.Offset - w - 8,
				x.Position.Y.Scale, x.Position.Y.Offset)) or UDim2.new(1, -54, 0.5, 0),
			BackgroundColor3 = Color3.fromRGB(120, 78, 40), Text = "\xE2\x97\x80",
			Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.fromRGB(255, 244, 214),
			ZIndex = 50, Visible = false,
		})
		mkCorner(seasonalBack, radius)
		seasonalBack.MouseButton1Click:Connect(function()
			seasonalBack.Visible = false
			local lg = PlayerGui:FindFirstChild("LockerGui")
			if lg then lg.Enabled = false end
			openHUD(nil, activeChest)   -- straight back to the chest panel, on the DONATE tab
		end)
		return seasonalBack
	end

	local function openSeasonal()
		closePanel()
		local opener = _G.openSeasonalPets or _G.openLocker
		if type(opener) == "function" then pcall(opener) end
		local g = PlayerGui:FindFirstChild("LockerGui")
		if g then
			g.Enabled = true    -- harmless if the opener already did it; required if there was none
			local b = ensureSeasonalBack()
			if b then b.Visible = true end
			-- The panel rebuilds its season cards on every refresh, so one sweep is not enough: run it
			-- now, again once the refresh has landed, and keep watching while the panel is up.
			local host = g:FindFirstChild("Frame")
			if host then
				roundCorners(host)
				task.delay(0.15, function() if g.Enabled then roundCorners(host) end end)
				task.delay(0.6,  function() if g.Enabled then roundCorners(host) end end)
			end
		else
			warn("[GardenDonate] Seasonal Pets panel (LockerGui) is not built yet")
		end
	end

	local tabBar = mkFrame(panel, { Size = UDim2.new(0, 420, 0, 36), Position = UDim2.new(0.5, 0, 0, 88), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(16, 56, 148), ZIndex = 4 })
	mkCorner(tabBar, 18); mkStroke(tabBar, Color3.fromRGB(120, 180, 250), 1)
	do
		local tabs = {}
		local function selectTab(which)
			-- the seasonal tab is an ACTION: it opens the other panel and leaves this one on
			-- DONATE, so re-opening the chest never lands you on a blank tab
			if which == "season" then openSeasonal(); which = "donate" end
			donatePage.Visible = true
			for name, btn in pairs(tabs) do
				local on = (name == which)
				btn.BackgroundColor3 = on and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(16, 56, 148)
				btn.BackgroundTransparency = on and 0 or 1
				btn.TextColor3 = on and Color3.fromRGB(84, 48, 4) or Color3.fromRGB(206, 232, 255)
			end
		end
		local function mkTab(key, text, xScale)
			local b = mkButton(tabBar, {
				Size = UDim2.new(0.5, -6, 1, -6), Position = UDim2.new(xScale, xScale == 0 and 3 or -3, 0.5, 0),
				AnchorPoint = Vector2.new(xScale, 0.5), Text = text, Font = Enum.Font.FredokaOne, TextSize = 18,
				BackgroundColor3 = Color3.fromRGB(16, 56, 148), AutoButtonColor = false, ZIndex = 5,
			})
			mkCorner(b, 15); juice(b)
			b.MouseButton1Click:Connect(function() selectTab(key) end)
			tabs[key] = b
			return b
		end
		mkTab("donate", "\xF0\x9F\x92\x9B  DONATE", 0)
		mkTab("season", "\xE2\x9D\x84\xEF\xB8\x8F  SEASONAL PETS", 1)
		selectTab("donate")
		-- openHUD() resets to the DONATE tab every time the chest is opened, so the panel never
		-- re-opens on whatever page you happened to leave it on.
		resetTabs = function() selectTab("donate") end
	end

	-- SUBTITLE + the honesty chip. One line each: the old two grey lines read as small print.
	-- Both moved DOWN to clear the tab bar, and both live on the donate page now.
	mkLabel(donatePage, { Text = "Love the garden? Chip in to help keep it growing! \xF0\x9F\x8C\xBB", Font = Enum.Font.FredokaOne, TextSize = 21, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0.5, 0, 0, 134), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local chip = mkFrame(donatePage, { Size = UDim2.new(0, 372, 0, 28), Position = UDim2.new(0.5, 0, 0, 162), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(16, 56, 148), ZIndex = 3 })
	mkCorner(chip, 14); mkStroke(chip, Color3.fromRGB(120, 180, 250), 1)
	mkLabel(chip, { Text = "\xF0\x9F\x92\x9B Pure support \xE2\x80\x94 no boosts, just our thanks", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(206, 232, 255), Size = UDim2.new(1, 0, 1, 0), ZIndex = 4 })

	-- 2x2 PRESET GRID  (also nudged down by the tab bar's height)
	local gridFrame = mkFrame(donatePage, { Size = UDim2.new(0, 620, 0, 246), Position = UDim2.new(0.5, 0, 0, 196), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 3 })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -8, 0.5, -8); grid.CellPadding = UDim2.new(0, 16, 0, 16)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center; grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder; grid.Parent = gridFrame

	for i, p in ipairs(PRESETS) do
		local look = TIER_LOOK[i] or TIER_LOOK[1]
		local card = mkFrame(gridFrame, { BackgroundColor3 = look.bot, LayoutOrder = i, ZIndex = 3 })
		mkCorner(card, 18); mkStroke(card, Color3.new(1, 1, 1), 2.5)
		do local g = Instance.new("UIGradient", card); g.Rotation = 90; g.Color = ColorSequence.new(look.top, look.bot) end
		do -- soft shine across the top of the card
			local sh = mkFrame(card, { Size = UDim2.new(1, -20, 0, 12), Position = UDim2.new(0, 10, 0, 7), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 4 }); mkCorner(sh, 6)
			local sg = Instance.new("UIGradient", sh); sg.Rotation = 90; sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		end

		-- tier motif in a white well (the same icon-well shape the shop cards use)
		local well = mkFrame(card, { Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 12, 0, 14), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.16, ZIndex = 4 })
		mkCorner(well, 12)
		mkLabel(well, { Text = look.emoji, Font = Enum.Font.FredokaOne, TextSize = 26, Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })

		-- the amount, big, right of the motif -- outlined in the tier's own dark ink so white text stays legible
		-- on the lighter tiers (the gold one especially)
		local amountLbl = mkLabel(card, { Text = string.format("%d R$", p.amount), Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -70, 0, 44), Position = UDim2.new(0, 64, 0, 14), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
		do
			local ts = Instance.new("UIStroke"); ts.Color = look.ink; ts.Thickness = 2.5
			ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; ts.LineJoinMode = Enum.LineJoinMode.Round
			ts.Parent = amountLbl
		end

		if look.tag then
			local badge = mkFrame(card, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0, 86, 0, 22), Position = UDim2.new(1, -10, 0, -8), BackgroundColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 6 })
			mkCorner(badge, 11); mkStroke(badge, look.ink, 2)
			mkLabel(badge, { Text = look.tag, Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = look.ink, Size = UDim2.new(1, 0, 1, 0), ZIndex = 7 })
		end

		local donateBtn = mkButton(card, { Size = UDim2.new(1, -24, 0, 46), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = BTN_GREEN, Text = "\xF0\x9F\x92\x96  DONATE", Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
		mkCorner(donateBtn, 13); mkStroke(donateBtn, Color3.new(1, 1, 1), 2); juice(donateBtn)
		local ds = Instance.new("UIScale"); ds.Parent = donateBtn -- hover pop
		donateBtn.MouseEnter:Connect(function() TweenService:Create(ds, TweenInfo.new(0.1), { Scale = 1.05 }):Play() end)
		donateBtn.MouseLeave:Connect(function() TweenService:Create(ds, TweenInfo.new(0.1), { Scale = 1 }):Play() end)
		donateBtn.MouseButton1Click:Connect(function() promptDonate(p.productId, p.amount) end)
	end

	-- NOTICE line (setup / personal thank-you) + FOOTER
	noticeLbl = mkLabel(donatePage, { Text = "", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.fromRGB(255, 235, 140), Size = UDim2.new(1, -40, 0, 22), Position = UDim2.new(0.5, 0, 1, -52), AnchorPoint = Vector2.new(0.5, 1), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	mkLabel(donatePage, { Text = "\xF0\x9F\x92\x9B Thank you for helping our garden grow! \xF0\x9F\x92\x9B", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = Color3.fromRGB(255, 245, 200), Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
end

function showThanks(donorName, robux)
	if not (gui and gui.Enabled) then return end
	if donorName == player.Name then
		setNotice(string.format("\xF0\x9F\x8E\x89 Thank you for donating %d R$! \xF0\x9F\x92\x9B", robux))
	end
end

function openHUD(promptPart, chestModel)
	if not gui then buildHUD() end
	activeChest = chestModel
	if resetTabs then pcall(resetTabs) end
	-- the BACK button injected into the Seasonal Pets panel belongs to that trip only -- opening the
	-- chest again starts a fresh one, so it must not be left showing behind us
	do
		local lg = PlayerGui:FindFirstChild("LockerGui")
		local host = lg and lg:FindFirstChild("Frame")
		local b = host and host:FindFirstChild("ChestBack")
		if b then b.Visible = false end
	end
	gui.Enabled = true
	claimDonationHud() -- the stale copy opens on this same prompt; drop its panel the instant ours is up
	setNotice("")
	-- pop in, like every other menu: starting slightly small and settling reads as a panel arriving rather than
	-- blinking into existence
	panel.Size = UDim2.new(0, 660, 0, 490)
	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 700, 0, 520) }):Play()
	if chestModel then pcall(function() openLid(chestModel) end) end
	if promptPart then pcall(function() sparkle(promptPart.Position) end) end
end

--======================================================================
-- SERVER-WIDE THANK-YOU BANNER: shown to EVERYONE when any player donates (a gold-trimmed toast that slides in + fades).
--======================================================================
-- Goes through NotifyCenter's HERO lane at PURCHASE priority (a donation IS a real-money purchase).
-- It used to build a fresh toast at UDim2.new(0.5,0,0,16) on a DisplayOrder-95 ScreenGui with no gate
-- of any kind, so it drew ON TOP of the arrival/announce/reward banners -- and two simultaneous
-- donations stacked two toasts on the identical pixel.
local function showBanner(text)
	local NC = _G.NotifyCenter
	if not NC then return end
	NC.push({
		top      = "\xF0\x9F\x92\x9A DONATION",
		text     = text,
		color    = Color3.fromRGB(35, 120, 60),
		priority = NC.PRIORITY.PURCHASE,
		duration = 3.6,
	})
end

GardenDonationEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local name  = tostring(data.name or "Someone")
	local robux = tonumber(data.robux) or 0
	showBanner(string.format("\xF0\x9F\x92\x9B %s donated %d R$ to the garden!", name, robux))
	showThanks(name, robux)
end)

-- PromptTriggered fires on THIS client for the local player's triggers -> open the donation HUD for OUR chest prompt.
-- (Keeps the treasure-box HUD link intact: the DonationChest's "DonationChestPrompt" is what opens this panel.)
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt and prompt.Name == "DonationChestPrompt" then
		local promptPart = (prompt.Parent and prompt.Parent:IsA("BasePart")) and prompt.Parent or nil
		local chestModel = prompt:FindFirstAncestorOfClass("Model")
		openHUD(promptPart, chestModel)
	end
end)

print("GARDEN DONATE GUI UPDATED")
