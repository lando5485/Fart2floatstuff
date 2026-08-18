--[[
	DevArrivalBanner.client.luau  (StarterPlayerScripts.DevArrivalBanner)

	The banner half of the dev-arrival moment. DevArrival.server fires DevArrivalEvent to every client with
	the dev's name; this pushes it through NotifyCenter's HERO lane.

	NO NEW UI. NotifyCenter already owns every transient banner in this game, with a priority queue that shows
	one HERO banner at a time and lets a bigger moment preempt a smaller one. Building a separate ScreenGui
	here is exactly the bug NotifyCenter was written to fix -- five banners all resting at the same spot,
	drawing through each other.

	PRIORITY: PURCHASE (90). Above EVENT (80) because the dev-arrival banner and the DEV ONLINE event banner
	fire in the same instant and the arrival is the headline -- the event pill announces the buff on its own
	anyway. Below ISLAND (100), because a player physically landing on a new island is still the biggest thing
	that can happen to them and must never be swallowed by someone else's news.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 210, 74)

local ev = ReplicatedStorage:WaitForChild("DevArrivalEvent", 30)
if not ev then
	warn("[DevArrival] DevArrivalEvent never appeared -- dev arrival banners inactive")
	return
end

-- Chime. 4612378364 is the id the crate reveal already uses in this place, so it is known-good here.
local chime = Instance.new("Sound")
chime.Name = "DevArrivalChime"
chime.SoundId = "rbxassetid://4612378364"
chime.Volume = 0.55
chime.Parent = SoundService
task.spawn(function()
	local grp = SoundService:FindFirstChild("SFXGroup") or SoundService:WaitForChild("SFXGroup", 30)
	if grp and grp:IsA("SoundGroup") then chime.SoundGroup = grp end
end)

ev.OnClientEvent:Connect(function(devName, islandName, islandNum)
	devName = tostring(devName or "A developer")
	islandName = (type(islandName) == "string" and islandName ~= "") and islandName or nil

	-- Wait for NotifyCenter rather than assuming it: both are StarterPlayerScripts and load order between
	-- them is not guaranteed, and a dev could join before this client has finished booting.
	local NC = _G.NotifyCenter
	if not NC then
		local t0 = os.clock()
		while not NC and (os.clock() - t0) < 10 do
			task.wait(0.2)
			NC = _G.NotifyCenter
		end
	end
	if not NC or type(NC.push) ~= "function" then
		warn("[DevArrival] NotifyCenter unavailable -- banner skipped for " .. devName)
		return
	end

	local isMe = (devName == player.Name)

	-- The island is the useful half of this: the whole point of announcing a dev is so players can go and
	-- find them, and "joined the server" doesn't tell you which of 14 islands to fly to. It falls back to the
	-- plain line if the leaderstat wasn't readable rather than printing "on nil".
	local line
	if isMe then
		line = islandName and ("You're on " .. islandName .. " \xE2\x80\x94 the server knows.")
			or (devName .. " \xE2\x80\x94 the server knows.")
	else
		line = islandName and (devName .. " is on " .. islandName .. "!")
			or (devName .. " joined the server!")
	end

	NC.push({
		top = isMe and "WELCOME BACK" or "\xF0\x9F\x91\x91 DEVELOPER ONLINE",
		text = line,
		color = GOLD,
		priority = NC.PRIORITY.PURCHASE,
		duration = 5,
		sound = function() pcall(function() chime.TimePosition = 0; chime:Play() end) end,
	})
end)

-- ===== DEV CRATE REVEAL =====
-- The server grants the crate and sends the result here; this plays the SAME reel a paid open plays, via
-- SkinCrateClient's own _G.skinCrateShowReveal. Nothing about the crate UI is reimplemented.
task.spawn(function()
	local reveal = ReplicatedStorage:WaitForChild("DevCrateReveal", 30)
	if not reveal then
		warn("[DevArrival] DevCrateReveal missing -- dev crates will grant silently")
		return
	end

	reveal.OnClientEvent:Connect(function(crateId, result)
		-- SkinCrateClient publishes this global once it has finished building; a player who taps the crate
		-- within a second of joining can beat it, so wait rather than dropping the reveal.
		local show = _G.skinCrateShowReveal
		if not show then
			local t0 = os.clock()
			while not show and (os.clock() - t0) < 10 do
				task.wait(0.2)
				show = _G.skinCrateShowReveal
			end
		end
		if type(show) ~= "function" then
			warn("[DevArrival] skinCrateShowReveal unavailable -- the item is still granted, it is in the Collection Book")
			return
		end

		-- Returns false when a reel is ALREADY running (it refuses rather than stacking two spins). The item
		-- is granted either way, so say where it went instead of leaving the player thinking nothing happened.
		local ok, played = pcall(show, crateId, result)
		if not ok or played ~= true then
			if _G.showHudBanner then
				pcall(_G.showHudBanner, "Dev crate opened \xE2\x80\x94 check your Collection Book!", GOLD, 4)
			end
		end
	end)
	print("[DevArrival] dev-crate reveal wired to the normal crate reel")
end)

print("[DevArrival] banner client ready -- listening for developer arrivals")
