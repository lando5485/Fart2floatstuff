--======================================================================
-- FirstBuy.client.lua  (LocalScript)   [Bean Island]
--======================================================================
-- THE FIRST BITE. The first time a new player successfully buys food, the game stops and makes a thing of
-- it: a warm flash, a hero banner, a chime, and the Farmer turning to wave at them.
--
-- Every game that converts well scripts this moment deliberately, because buying the first Beans is where a
-- new player finds out the loop exists. Right now that purchase is silent -- the coin counter goes down, the
-- gas bar goes up, and nothing tells them they just did the thing the whole game is built on.
--
-- ===== WHY THIS IS A SEPARATE SCRIPT =====
-- The obvious place for it is PlayerStats, next to BuyFoodEvent -- and that is exactly why it is not there.
-- BootCheck reports PlayerStats running as TWO copies (the Rojo one plus a stale one baked into the place),
-- so an edit there runs alongside a copy that has never heard of it. This script touches nothing and only
-- listens, so no amount of duplication elsewhere can double-fire it or leave it half-applied.
--
-- ===== HOW A SUCCESSFUL PURCHASE IS DETECTED =====
-- Not by listening to BuyFoodEvent: that is the REQUEST, and the server refuses plenty of them (too few
-- coins, stomach already full). What actually proves a purchase landed is CurrentPower going UP -- the same
-- signal ShopClient already uses to decide whether to play its crunch, for the same reason. Power only rises
-- when food is eaten.
--
-- ===== WHY IT DOESN'T FIRE FOR VETERANS =====
-- "First purchase" means the first one EVER, and this script has no save data to check that against. What it
-- can see is TotalCoinsEarned, which is lifetime and never resets -- a player who has earned more than
-- VETERAN_COINS has demonstrably bought food before, whatever this session thinks. So the moment is gated on
-- being genuinely early, and someone on their fortieth join never sees it.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- DUPLICATE GUARD. Rojo adds, it never overwrites, so a stale copy baked into the place file would run
-- alongside this one -- and two copies of a once-ever moment is the one thing it must never be.
if _G.__FirstBuyClient then
	warn("[FirstBuy] a SECOND copy is running -- this one is bailing out. Delete the stale LocalScript in Studio.")
	return
end
_G.__FirstBuyClient = true

--======================================================================
-- TUNING
--======================================================================
local VETERAN_COINS = 400   -- lifetime earnings above this = not a new player. Beans cost 10 and island 1
                            -- pays out slowly, so anyone still under 400 is on their first few flights.
local FLASH_TIME    = 0.9
-- A known-good asset: CrateClient's boot diagnostic reports this one loading successfully, while several
-- other ids in the place fail with "Asset type does not match requested type". Swap it for something of
-- your own when you have one -- this is a placeholder that is at least guaranteed to play.
local CHIME_ID      = "rbxassetid://4612378364"

--======================================================================
-- THE MOMENT
--======================================================================
local function celebrate()
	-- 1. FLASH -- a warm wash rather than a white one, so it reads as sunlight and not as damage
	local gui = Instance.new("ScreenGui")
	gui.Name = "FirstBuyFlash"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200; gui.Parent = PlayerGui
	local flash = Instance.new("Frame")
	flash.Size = UDim2.new(1, 0, 1, 0); flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.fromRGB(255, 226, 160)
	flash.BackgroundTransparency = 0.35
	flash.Parent = gui
	TweenService:Create(flash, TweenInfo.new(FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(gui, FLASH_TIME + 0.3)

	-- 2. CHIME
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = CHIME_ID; s.Volume = 0.6; s.Parent = SoundService
		s:Play()
		game:GetService("Debris"):AddItem(s, 5)
	end)

	-- 3. BANNER. EXCLUSIVE, at the TUTORIAL tier: the first food purchase is a teaching moment, so it takes
	-- the hero lane ALONE. Nothing plays over it and nothing plays beside it -- arrival cards, event titles,
	-- friend/group promos, reward toasts and purchase confirmations all queue and get their turn after. It
	-- used to ride at ISLAND priority, which stopped it being buried but still let a bigger banner shove it
	-- off screen mid-read. The one thing that can still cut it short is the garden watering quest, which
	-- sits a tier above by design.
	--
	-- tutorial() is the shared call for exactly this (see NotifyCenter) -- push with the flag is the
	-- fallback for an older build of that file that never learned the newer entry point.
	local NC = _G.NotifyCenter
	if NC then
		local spec = {
			text  = "FIRST MEAL -- NOW FLY UP!",
			sub  = "Food IS fuel \xE2\x80\x94 the fuller the meter, the higher you climb",
			color = Color3.fromRGB(255, 206, 92),
			exclusive = true,
			priority = (NC.PRIORITY and NC.PRIORITY.TUTORIAL) or 150,
		}
		if NC.tutorial then pcall(NC.tutorial, spec)
		elseif NC.push then pcall(NC.push, spec) end
	end

	-- 4. THE FARMER TURNS AND WAVES. Reusing GardenerWave's own remote, the same one the intro cinematic
	-- calls -- its cooldown and already-waving guards still apply, so this cannot make him spasm.
	task.delay(0.5, function()
		local ev = ReplicatedStorage:FindFirstChild("GardenerWaveRequest")
		if ev then pcall(function() ev:FireServer("Farmer") end) end
	end)

	print("[FirstBuy] first meal celebrated")
end

--======================================================================
-- WATCH
--======================================================================
task.spawn(function()
	-- leaderstats is built on join and CoreClient republishes it as _G.leaderstats; wait for whichever
	-- arrives, rather than assuming an order between two scripts that have no dependency on each other.
	local ls
	for _ = 1, 60 do
		ls = _G.leaderstats or player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("CurrentPower") then break end
		task.wait(0.5)
	end
	if not (ls and ls:FindFirstChild("CurrentPower")) then
		warn("[FirstBuy] leaderstats/CurrentPower never arrived -- first-meal moment inactive")
		return
	end

	local cp    = ls:FindFirstChild("CurrentPower")
	local total = ls:FindFirstChild("TotalCoinsEarned")

	-- Already a veteran at join: never arm at all, so there is no per-frame cost and no chance of a stray fire.
	if total and total.Value > VETERAN_COINS then
		print(string.format("[FirstBuy] not armed -- %d lifetime coins is past the %d new-player mark",
			total.Value, VETERAN_COINS))
		return
	end

	local last, done = cp.Value, false
	local conn
	conn = cp:GetPropertyChangedSignal("Value"):Connect(function()
		local now = cp.Value
		-- RISING only. Power falls on flight, on landing and on every island unlock and stomach upgrade;
		-- only eating pushes it up, which is what makes this a purchase signal rather than a noise signal.
		if not done and now > last then
			-- re-check at the moment of the buy: they may have crossed the line while the script was armed
			if total and total.Value > VETERAN_COINS then
				done = true; conn:Disconnect(); return
			end
			done = true
			conn:Disconnect()
			celebrate()
		end
		last = now
	end)
	print("[FirstBuy] armed -- watching for this player's first meal")
end)
