--======================================================================
-- AFKFarmClient.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- The voice of the AFK Token Farm. The server owns the machine, the hose and the tokens (it hands out real
-- currency, so it has to); this file does the one thing a server cannot -- tell YOU what just happened, in
-- the same lane every other message in this game uses.
--
-- ===== IT DOES NOT BUILD A SINGLE ScreenGui =====
-- NotifyCenter owns the top-centre banner lane and the top-left social lane, and the house rule is that
-- nothing else draws there: two banners overlapping is the exact bug that lane exists to prevent. So every
-- line below is a _G.NotifyCenter.push, at a priority that says how much it deserves to interrupt.
--
--   plugged in / unplugged  -> HERO lane at REWARD. News about you, not an instruction, and it must not
--                              outrank an island arrival or a purchase receipt.
--   +tokens                 -> SOCIAL lane (top-left). One of these lands every 90 seconds while you farm,
--                              and a running trickle of them in the middle of the screen would be a
--                              nuisance; the social lane is where quiet, repeating news belongs.
--
-- The counter in the HUD capsule needs nothing from this file -- SkinCrateService pushes the new balance
-- when the server credits the tokens, and TokenHud repaints itself off that. This is the narration only.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local evt = ReplicatedStorage:WaitForChild("AFKFarmEvent", 30)
if not evt then
	warn("[AFKFarm][client] AFKFarmEvent never arrived -- the farm still works, it just says nothing.")
	return
end

local LIME = Color3.fromRGB(126, 204, 60)
local GREY = Color3.fromRGB(96, 104, 122)

-- NotifyCenter can be a moment late (and a stale duplicate can hold the global for the first few seconds of
-- a session -- that file reclaims it on a loop). Read it at FIRE TIME, never cache it, and drop the message
-- rather than error if it genuinely is not there.
local function say(spec)
	local nc = _G.NotifyCenter
	if type(nc) ~= "table" or type(nc.push) ~= "function" then return end
	pcall(nc.push, spec)
end

-- WHY IT CAME OFF, in words a player can act on. The server sends its own short reason string; anything it
-- does not have a line for falls through to the generic one rather than printing a debug token at somebody.
local UNPLUG_REASON = {
	["walked out of range"] = "You walked too far from the tank",
	["pressed E again"]     = "You unplugged from the tank",
	["died"]                = "You died -- the hose came off",
	["respawned"]           = "You respawned -- the hose came off",
	["left the game"]       = "",
	["character gone"]      = "",
}

evt.OnClientEvent:Connect(function(kind, a, b)
	if kind == "connected" then
		local rate = tonumber(a) or 40
		-- ===== A PILL, NOT A BANNER =====
		-- The player walked to the farm and pressed E, and the hose is now visibly attached to them. A
		-- centre-screen card here is the game reading their own action back to them, and every one of those
		-- spends a little of the attention the arrival cards and reward banners need. Top-left says the same
		-- thing to anyone who looks and costs nothing to anyone who does not.
		say({
			text = "\xF0\x9F\x94\x8C  +" .. rate .. " TICKETS/HOUR",
			color = LIME,
			lane = "social",
			priority = 10,
			duration = 4,
		})

	elseif kind == "token" then
		local pay = tonumber(a) or 0
		local total = tonumber(b) or 0
		if pay <= 0 then return end
		say({
			text = "+" .. pay .. " Ticket" .. (pay == 1 and "" or "s"),
			sub = total .. " banked this session",
			color = LIME,
			lane = "social",         -- top-left: it repeats, so it must not sit in the middle of the screen
			priority = 10,
			duration = 3,
		})

	elseif kind == "away" then
		-- The welcome-back line. This one is worth interrupting for: it is the only place a player is ever
		-- told that LEAVING paid them, and at nudge priority it would lose to whatever arrival card happens
		-- to fire on the same join.
		local pay  = tonumber(a) or 0
		local secs = tonumber(b) or 0
		local hh, mm = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
		local spent = (hh > 0) and (hh .. "h " .. mm .. "m") or (mm .. "m")
		say({
			top = "\xE2\x9A\xA1 AFK TICKET FARM",
			text = "+" .. pay .. " TICKETS WHILE AWAY",
			sub = "Plugged in for " .. spent .. "  \xE2\x80\xA2  press E at the farm to start again",
			color = LIME,
			priority = 90,          -- PURCHASE tier: money landed, and it must not be swallowed
			duration = 7,
		})


	elseif kind == "disconnected" then
		local why = UNPLUG_REASON[tostring(a)]
		if why == "" then return end   -- they left or lost their character; there is nobody to tell
		local earned = tonumber(b) or 0
		-- A PILL for the same reason as "hooked up", plus one worse case of its own: this fires on DEATH and
		-- on RESPAWN (see UNPLUG_REASON above). A player who has just been knocked out of the sky does not
		-- need the centre of their screen taken by a notice about a hose.
		say({
			text = "\xF0\x9F\x94\x8C  UNPLUGGED" .. (earned > 0 and ("  \xE2\x80\xA2  " .. earned) or ""),
			color = GREY,
			lane = "social",
			priority = 10,
			duration = 4,
		})
	end
end)

print("[AFKFarm][client] ready -- hook-up, token and unplug banners routed through NotifyCenter")
