--======================================================================
-- Campfire.client.luau  (LocalScript)   [Bean Island]
--======================================================================
-- Purely feedback for the AFK campfire. The server (Campfire.server.lua) does ALL the work -- builds the
-- fire, decides who's resting, and credits the coins. Here we just show a cozy "warming up" pill while the
-- server says this player is resting, so idling by the fire feels like it's doing something. If this script
-- never runs, the campfire still works; you just don't get the pill.
--
-- Driven entirely by two attributes the server sets on the player: CampfireResting (bool) and CampfireRate
-- (coins per tick). No remotes, no polling of the world.
--======================================================================
local Players = game:GetService("Players")
local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")

-- DUPLICATE GUARD ---------------------------------------------------------------------------------------
-- THREE copies of this script run: the Rojo one plus two stale copies baked into the place (MenuBackdropGuard
-- lists Campfire under both its duplicate-LocalScript and duplicate-ScreenGui warnings). Each built its own
-- CampfireHud with its own Roast/Stop/Eat bar stacked on the same screen position, so a tap could land on a
-- stale bar instead of this one -- and the oldest copy has no Remove button at all. That is why the buttons
-- felt dead: you were pressing a different script's.
--
-- First loader wins and clears the others out. Repeated on a timer because we do not choose load order: a
-- stale copy that starts after us is only reachable once it has built itself.
if _G.__CampfireClient then return end
_G.__CampfireClient = true

local function nukeStaleCampfireUi()
	local removed = 0
	for _, inst in ipairs(player:GetDescendants()) do
		-- any CampfireHud that is not the one THIS script made (ours carries the stamp set below)
		if inst:IsA("ScreenGui") and inst.Name == "CampfireHud" and not inst:GetAttribute("BuiltByLiveScript") then
			pcall(function() inst:Destroy() end); removed = removed + 1
		elseif inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
			-- the running copies live under the player (PlayerScripts / PlayerGui), not in StarterPlayer
			pcall(function() inst.Disabled = true; inst:Destroy() end); removed = removed + 1
		end
	end
	if removed > 0 then
		warn("[Campfire] cleared " .. removed .. " STALE duplicate campfire UI/script(s) -- their buttons were " ..
			"stacked on top of the working ones. Delete them in Studio for good.")
	end
end
nukeStaleCampfireUi()

local screen = Instance.new("ScreenGui")
screen.Name = "CampfireHud"; screen.ResetOnSpawn = false; screen.IgnoreGuiInset = true
-- DisplayOrder 200, was 40. Roblox routes a click to the TOPMOST GuiObject under it, and DisplayOrder is what
-- decides "topmost" ACROSS ScreenGuis. At 40 this bar sat under several full-screen elements that are invisible
-- but still input-eating -- ButterFishingHUD is 88 and spawns a screen-covering tap catcher, and the bottom HUD
-- overlaps this bar's exact rectangle. A transparent button still swallows the press. 200 puts the roasting
-- bar above all of them, which is correct on its own terms: while you are stood at a fire holding a stick,
-- these four ARE the frontmost controls on screen.
screen.DisplayOrder = 200
screen:SetAttribute("BuiltByLiveScript", true) -- stamp so the sweep above never destroys OUR hud
screen.Parent = gui
task.delay(1, nukeStaleCampfireUi); task.delay(4, nukeStaleCampfireUi); task.delay(9, nukeStaleCampfireUi)

-- (the "Warming up +1" resting pill was removed -- resting still quietly credits coins server-side)

--======================================================================
-- ROASTING BUTTONS: Go / Stop / Eat, shown only while you're holding the Marshmallow Stick.
-- The buttons just fire the server; it owns the cooking + eating.
--======================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ===== PICK THE REMOTE BY STAMP, NOT BY NAME =====
-- WaitForChild("CampfireStick") is what broke every button. More than one RemoteEvent carries that name --
-- a stale duplicate server script makes its own -- and WaitForChild returns whichever replicated first. When
-- that was not the one the live server connected its handler to, FireServer went into a void: the click
-- registered, the guards passed, the press was sent, and nothing on the server ever heard it.
--
-- The live server stamps its remote with CampfireRemoteLive and destroys same-named rivals, so the stamp is
-- the only reliable way to tell them apart. We wait for the stamped one specifically, and only fall back to
-- the plain name if no stamp shows up (an older server build that predates the stamp).
local REMOTE_STAMP = "CampfireRemoteLive"

local stickRemote
do
	local deadline = os.clock() + 30
	repeat
		for _, d in ipairs(ReplicatedStorage:GetChildren()) do
			if d:IsA("RemoteEvent") and d.Name == "CampfireStick" and d:GetAttribute(REMOTE_STAMP) then
				stickRemote = d; break
			end
		end
		if not stickRemote then task.wait(0.1) end
	until stickRemote or os.clock() > deadline

	if not stickRemote then
		stickRemote = ReplicatedStorage:FindFirstChild("CampfireStick")
		warn("[Campfire] no STAMPED remote appeared in 30s -- falling back to the first one named " ..
			"'CampfireStick'. If the buttons do nothing, the server script is stale or not running.")
	end
end

if stickRemote then
	local bar = Instance.new("Frame")
	bar.Name = "RoastBar"; bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 0.86, 0)
	bar.Size = UDim2.fromOffset(330, 60)
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = screen
	local row = Instance.new("UIListLayout", bar)
	row.FillDirection = Enum.FillDirection.Horizontal; row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center; row.Padding = UDim.new(0, 10)

	local function mkBtn(text, color)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(100, 54); b.AutoButtonColor = true
		b.BackgroundColor3 = color; b.Text = text
		b.Font = Enum.Font.FredokaOne; b.TextScaled = true; b.TextColor3 = Color3.new(1, 1, 1)
		-- Hands-off, ButtonTextStyle: setLive() below drives this fill, and grey here MEANS "you cannot do this
		-- right now". A generic restyler re-asserting a remembered colour would un-grey a dead button.
		b:SetAttribute("BTS_Skip", true)
		b.Parent = bar
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
		local s = Instance.new("UIStroke", b); s.Color = Color3.new(0, 0, 0); s.Transparency = 0.4; s.Thickness = 2
		local pad = Instance.new("UIPadding", b); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
		return b
	end

	local goBtn   = mkBtn("\xF0\x9F\x94\xA5 Roast", Color3.fromRGB(214, 108, 44))
	local stopBtn = mkBtn("\xE2\x9C\x8B Stop",     Color3.fromRGB(90, 96, 110))
	local eatBtn  = mkBtn("\xF0\x9F\x98\x8B Eat",  Color3.fromRGB(86, 170, 78))
	goBtn.LayoutOrder = 1; stopBtn.LayoutOrder = 2; eatBtn.LayoutOrder = 3

	-- Is there anything on the end of the stick? The server flips a HasMarsh attribute on the tool when you eat
	-- and again when you refill at the bucket, and attributes replicate, so the buttons track it with no extra
	-- remote. A MISSING attribute counts as YES -- a stick handed out by an older server copy must still work.
	local function marshOn()
		local char = player.Character
		local tool = char and char:FindFirstChild("Marshmallow Stick")
		return tool ~= nil and tool:GetAttribute("HasMarsh") ~= false
	end

	-- ===== WHAT IS LEGAL RIGHT NOW =====
	-- The server owns these rules and re-checks every one of them; this mirrors them ONLY so a button that
	-- cannot work looks like it cannot work. Both the greying and the click guard read the SAME functions, so
	-- a live-looking button can never be a dead one.
	--
	-- Everything here comes from replicated state -- attributes the server sets on the stick, and CampfireLit
	-- on Workspace -- so no extra remote is needed and every client sees the same answer.
	local RAW_UNTIL = 18 -- keep in step with RAW_UNTIL in Campfire.server.lua
	local function stickTool()
		local char = player.Character
		return char and char:FindFirstChild("Marshmallow Stick")
	end
	local function isRoasting()
		local t = stickTool()
		return t ~= nil and t:GetAttribute("Roasting") == true
	end
	local function roastVal()
		local t = stickTool()
		return (t and t:GetAttribute("Roast")) or 0
	end
	local function firesAreLit()
		-- missing attribute = an older server copy that never published it; assume lit rather than dead-lock
		return workspace:GetAttribute("CampfireLit") ~= false
	end

	local canRoast = function() return marshOn() and not isRoasting() and firesAreLit() end
	local canStop  = function() return isRoasting() end
	local canEat   = function() return marshOn() and roastVal() >= RAW_UNTIL end

	-- ===== WIRING THE PRESSES =====
	-- MouseButton1Click, not Activated. Every other button in this game (CoreClient, ShopClient, RailGuard,
	-- the crate UIs) uses MouseButton1Click; these four were the only ones on Activated. Whatever else is
	-- wrong, being the odd one out is one variable too many when four buttons all read as dead at once.
	--
	-- And NOTHING here fails silently any more. A press that is refused says which guard refused it and what
	-- that guard saw -- because "I pressed it and nothing happened" is identical from the outside whether the
	-- click never landed, the guard blocked it, or the server dropped it, and those are three different bugs.
	--
	-- NOTE ON WHAT THIS PRINTS: it reads `bar.Visible`, NOT holdingStick()/atCampfire(). Those two are
	-- declared further down the file, and a `local` is invisible to a closure written above it -- referencing
	-- them here would resolve them as nil globals and throw on the first press, killing all four buttons.
	-- That is the precise bug that took the server handler down last round. bar.Visible IS those two ANDed
	-- together and it is already in scope, so it carries the same information with none of the hazard.
	local function press(name, allowed, action)
		print(("[Campfire][press] %s -- allowed=%s | marsh=%s roasting=%s roast=%d lit=%s barShown=%s")
			:format(name, tostring(allowed), tostring(marshOn()), tostring(isRoasting()), roastVal(),
				tostring(firesAreLit()), tostring(bar.Visible)))
		if not allowed then return end
		stickRemote:FireServer(action)
	end

	goBtn.MouseButton1Click:Connect(function()   press("Roast", canRoast(), "roast") end)
	stopBtn.MouseButton1Click:Connect(function() press("Stop",  canStop(),  "stop")  end)
	eatBtn.MouseButton1Click:Connect(function()  press("Eat",   canEat(),   "eat")   end)

	-- a little red Remove button, centred UNDER the middle (Stop) button. Puts the whole stick down: no eat,
	-- no reward. This is the deliberate way to hand yourself the bottom buttons back (gut pill / gas meter /
	-- BUY FOOD) without having to walk away from the fire -- the stick is gone, so the HUD authority in
	-- CoreClient stops hiding them within a quarter-second, exactly as if you had left.
	local removeBtn = Instance.new("TextButton")
	removeBtn.AnchorPoint = Vector2.new(0.5, 0)
	removeBtn.Position = UDim2.new(0.5, 0, 0.865, 6) -- just below the bar, centred (under the middle button)
	removeBtn.Size = UDim2.fromOffset(120, 28)
	removeBtn.BackgroundColor3 = Color3.fromRGB(200, 58, 58)
	removeBtn.Text = "\xF0\x9F\x97\x91 Remove"; removeBtn.AutoButtonColor = true
	removeBtn.Font = Enum.Font.FredokaOne; removeBtn.TextScaled = true; removeBtn.TextColor3 = Color3.new(1, 1, 1)
	removeBtn.Visible = false
	removeBtn.Parent = screen
	Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 10)
	local rs = Instance.new("UIStroke", removeBtn); rs.Color = Color3.new(0, 0, 0); rs.Transparency = 0.4; rs.Thickness = 2
	local rpad = Instance.new("UIPadding", removeBtn); rpad.PaddingLeft = UDim.new(0, 6); rpad.PaddingRight = UDim.new(0, 6)
	-- Remove has no legality guard -- putting the stick down is legal in every state -- so if THIS one reads as
	-- dead, the click is not reaching the button at all and the problem is a GUI sitting on top of it, not the
	-- rules. That makes it the most informative of the four, so it reports what is actually under the cursor.
	removeBtn.MouseButton1Click:Connect(function()
		local over = {}
		pcall(function()
			local m = player:GetMouse()
			for _, o in ipairs(gui:GetGuiObjectsAtPosition(m.X, m.Y)) do over[#over + 1] = o:GetFullName() end
		end)
		print("[Campfire][press] Remove -- GUI stack under the cursor, topmost first: " ..
			(#over > 0 and table.concat(over, "  >  ") or "(nothing -- the click did not land on any GUI)"))
		stickRemote:FireServer("remove")
	end)

	-- Because eating now KEEPS the stick, you can be stood at the fire holding a bare stick -- and a Roast or
	-- Eat button that silently does nothing reads as broken. Say what to do instead.
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 0.86, -66)
	hint.Size = UDim2.fromOffset(340, 26)
	hint.BackgroundColor3 = Color3.fromRGB(26, 18, 12); hint.BackgroundTransparency = 0.25
	hint.Text = "Grab a marshmallow from the bucket"
	hint.Font = Enum.Font.FredokaOne; hint.TextScaled = true; hint.TextColor3 = Color3.fromRGB(255, 232, 200)
	hint.Visible = false
	hint.Parent = screen
	Instance.new("UICorner", hint).CornerRadius = UDim.new(1, 0)
	local hpad = Instance.new("UIPadding", hint); hpad.PaddingLeft = UDim.new(0, 10); hpad.PaddingRight = UDim.new(0, 10)
	-- CoreClient force-sets TextScaled on every PlayerGui TextLabel, so cap the size here instead of via TextSize
	local hcap = Instance.new("UITextSizeConstraint", hint); hcap.MaxTextSize = 16

	-- HIDE JUST THE BOTTOM BAR WHILE ROASTING. BottomStackGui is the little fart/gut meter + the "TAP TO
	-- FART! / BUY FOOD FIRST!" button; everything else (coins, side buttons, etc.) stays visible.
	--
	-- This script does NOT set g.Enabled itself, on purpose. STALE DUPLICATE copies of this file are baked into
	-- the place and run their own older hide/restore, so writing Enabled here is a coin-flip against a copy that
	-- cannot be edited from here -- and when the old copy won, the bottom buttons never came back after the stick
	-- was removed. Instead we only DECLARE a reason, and the bottom-HUD authority in CoreClient (no duplicate,
	-- re-asserts on a timer) decides and enforces it. That authority runs the same holding-the-stick-AND-at-a-fire
	-- test itself, so the restore still happens even if this entire script is shadowed by a stale copy.
	local function setHudHidden(hidden)
		if _G.hudHold then _G.hudHold("Campfire", hidden) end
	end

	-- The roasting bar belongs to a campfire, so it needs BOTH conditions: the "Marshmallow Stick" tool in the
	-- character AND actually being at a fire. Holding alone meant wandering off with the stick still equipped
	-- left the bottom HUD hidden with no way to get it back short of dropping the stick.
	local NEAR_FIRE = 45 -- studs; generous, so stepping back from the flames does not flicker the bar
	local function holdingStick()
		local char = player.Character
		return char and char:FindFirstChild("Marshmallow Stick") ~= nil
	end
	local function atCampfire()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return false end
		-- The server parents every built fire to Workspace as a Model named 'Campfire'.
		for _, m in ipairs(workspace:GetChildren()) do
			if m.Name == "Campfire" and m:IsA("Model") then
				local pivot = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
				if pivot and (pivot.Position - hrp.Position).Magnitude <= NEAR_FIRE then return true end
			end
		end
		return false
	end
	local GO_COLOR, STOP_COLOR, EAT_COLOR =
		Color3.fromRGB(214, 108, 44), Color3.fromRGB(90, 96, 110), Color3.fromRGB(86, 170, 78)
	local function setLive(btn, on, liveColor)
		btn.AutoButtonColor = on
		btn.BackgroundColor3 = on and liveColor or Color3.fromRGB(96, 96, 104)
		btn.TextTransparency = on and 0 or 0.35
	end

	local function updateBar()
		local active = holdingStick() and atCampfire()
		bar.Visible = active
		removeBtn.Visible = active
		setHudHidden(active)
		-- Each button is lit only while its action would actually be accepted. Remove is the exception and
		-- stays live always: it is the way to hand yourself the bottom HUD back without walking off, and
		-- putting the stick down is legal in every state.
		setLive(goBtn,   active and canRoast(), GO_COLOR)
		setLive(stopBtn, active and canStop(),  STOP_COLOR)
		setLive(eatBtn,  active and canEat(),   EAT_COLOR)

		-- Say WHY, when the reason isn't obvious from the buttons alone.
		local msg = nil
		if active and not marshOn() then
			msg = "Grab a marshmallow from the bucket"
		elseif active and not firesAreLit() then
			msg = "\xF0\x9F\x8C\xA7 The fire is out -- wait for it to dry"
		elseif active and isRoasting() and roastVal() < RAW_UNTIL then
			msg = "\xF0\x9F\x94\xA5 Roasting... hold it there"
		elseif active and not canEat() then
			msg = "Still raw -- roast it first"
		end
		hint.Text = msg or hint.Text
		hint.Visible = active and msg ~= nil
	end

	-- The stick's own attributes drive three of the four buttons, and Roast ticks several times a second while
	-- cooking. Waiting on the half-second poll would leave Eat greyed for up to half a second after the
	-- marshmallow stopped being raw, which feels like a stuck button -- so follow the attributes directly.
	local function hookStick(inst)
		if inst:IsA("Tool") and inst.Name == "Marshmallow Stick" then
			inst.AttributeChanged:Connect(updateBar)
		end
		updateBar()
	end
	local function hookChar(char)
		char.ChildAdded:Connect(hookStick)
		char.ChildRemoved:Connect(updateBar)
		for _, d in ipairs(char:GetChildren()) do hookStick(d) end -- already equipped when we hooked up
		updateBar()
	end
	-- the fire going out (or drying) must grey/un-grey Roast for everyone standing there, immediately
	workspace:GetAttributeChangedSignal("CampfireLit"):Connect(updateBar)
	if player.Character then hookChar(player.Character) end
	player.CharacterAdded:Connect(hookChar)
	-- ChildAdded/ChildRemoved cover equipping and dropping, but WALKING AWAY fires no character event at all,
	-- so distance has to be polled. Twice a second is plenty for a 45-stud radius and costs a handful of
	-- comparisons against the few Campfire models in the world.
	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(updateBar)
		end
	end)
end

print("[Campfire] client ready -- roasting buttons wired")
