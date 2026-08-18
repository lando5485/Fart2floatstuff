--======================================================================
-- RareAnnounce.client.lua  (LocalScript)
--======================================================================
-- "SAM JUST HATCHED A GOLDEN DUCK -- 1 IN 10,000!" across everyone's screen.
--
-- Rare SKINS already announced server-wide (SkinCrateService fires GoldAnnounce:FireAllClients on a Gold
-- pull). Rare PETS did not -- PetRareEvent went only to the person who hatched it -- so the single rarest,
-- most exciting event in the game was invisible to every other player in the server.
--
-- That gap mattered more than it sounds. A kid who has never SEEN a rare has no reason to believe the odds
-- are real; a kid who watches three of them scroll past in an hour will chase them all week. This is the
-- cheapest social proof the game has, and the plumbing for it already existed on the skin side.
--
-- ===== THE ODDS ARE THE POINT =====
-- "Got a rare" is a shrug. "1 IN 10,000" is a number kids repeat to each other, and repeating it is the
-- entire value of the feature. The server sends the BASE odds -- not the hatcher's rebirth-luck-adjusted
-- odds, which would be both confusing and a quiet way of broadcasting how many rebirths they have.
--
-- ===== THE HATCHER DOES NOT GET THIS BANNER =====
-- They are, at that exact moment, watching PetFollow's full-screen rare hatch fanfare. Dropping a banner on
-- top of their own celebration is noise -- they already know. This is a deliberate difference from the skin
-- announcement, which shows to everyone including the puller; a skin reveal happens inside a panel and has
-- room beside it, a rare hatch takes the whole screen.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

if _G.__RareAnnounceClient then
	warn("[RareAnnounce] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__RareAnnounceClient = true

local GOLD   = Color3.fromRGB(255, 206, 92)
local MYTHIC = Color3.fromRGB(255, 132, 190)   -- the duck's tier gets its own colour; it is 13x rarer

-- "10000" -> "10,000". A number with separators reads as big; the same digits in a run read as a code.
local function commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

task.spawn(function()
	local ev = ReplicatedStorage:WaitForChild("PetRareAnnounceEvent", 60)
	if not ev then
		warn("[RareAnnounce] PetRareAnnounceEvent never arrived -- server-wide rare callouts inactive")
		return
	end

	ev.OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then return end

		-- Skip our own -- see the header. Compared on UserId rather than name: display names are not unique
		-- and two players called the same thing would silently suppress each other's announcements.
		if info.userId == player.UserId then return end

		local odds = tonumber(info.odds) or 0
		local name = tostring(info.playerName or "Someone")
		local what = tostring(info.rareName or "a rare pet")
		local mythic = odds >= 5000

		local text
		if odds > 0 then
			text = string.format("\xE2\xAD\x90  %s HATCHED %s  \xE2\x80\x94  1 IN %s!",
				string.upper(name), string.upper(what), commas(odds))
		else
			text = string.format("\xE2\xAD\x90  %s HATCHED %s!", string.upper(name), string.upper(what))
		end

		if _G.NotifyCenter and _G.NotifyCenter.push then
			pcall(_G.NotifyCenter.push, {
				text = text,
				color = mythic and MYTHIC or GOLD,
				-- EVENT, not REWARD. This is somebody ELSE'S win: it should be impossible to miss, but it must
				-- never sit on top of this player's own island landing or crate reveal.
				priority = (_G.NotifyCenter.PRIORITY and _G.NotifyCenter.PRIORITY.EVENT) or 80,
			})
		elseif _G.showHudBanner then
			_G.showHudBanner(text, mythic and MYTHIC or GOLD, 6)
		else
			print("[RareAnnounce] " .. text)
		end

		if _G.Sfx then pcall(_G.Sfx.play, "levelup") end -- silent while the sound set is off; harmless
		print("[RareAnnounce] " .. text)
	end)

	print("[RareAnnounce] ready -- rare pet hatches now announce to the whole server")
end)
