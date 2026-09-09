--======================================================================
-- QuestDevGate.client.luau  (StarterPlayerScripts)  -- CandyRealm
--======================================================================
-- DECIDES WHO IS ALLOWED TO USE THE QUEST SKIP COMMANDS. Publishes one boolean,
-- `_G.questDevOK`, and every quest's chat handler now opens with:
--
--     if not _G.questDevOK then return end
--
-- ===== THE HOLE THIS CLOSES =====
-- Thirteen quests wired `/complete` (and `/blast`, `/fix`, `/warm`, `/start`, `/pancakewake`)
-- straight to TextChatService with no check at all beyond "did I type it myself", and
-- DoneCommand's `/done` completes every quest on whatever island you are standing on. Between
-- them, ANY player could walk the tower typing two words per island and collect the entire
-- realm: every coin reward (~12,350), every crate token, and every locked food stand on
-- islands 1, 3, 4, 9, 11 and 19 -- in about the time it takes to fly up. They read as debug
-- code because they are, but nothing marked them as devs-only, so they shipped as cheats.
--
-- ===== WHY A _G BOOLEAN AND NOT A REQUIRE =====
-- Read at COMMAND TIME, not at load time. A quest that boots before this file simply sees nil
-- and refuses, and the moment this file runs the flag is live -- so there is no load-order race
-- to get wrong across fourteen files. It also costs each quest exactly one line and ZERO new
-- top-level locals, which matters: BrokenTractor sits at 197 of Luau's 200-local ceiling and
-- PancakeMonster at 196, and a `local X = require(...)` in either is a compile failure that
-- silently kills the whole island (see tools/registers.py).
--
-- ===== IT IS NOT A SECURITY BOUNDARY, AND DOES NOT NEED TO BE =====
-- This is a LocalScript, so an exploiter with script execution can set `_G.questDevOK` itself.
-- That is fine and is not what this is for: the realm already grants coins on the client's word
-- through CoinEvent, so someone at that level was never going to need `/complete`. What this
-- stops is the ORDINARY player who reads the commands off a stream or a Discord post and types
-- them -- which, unguarded, was every player.
--======================================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ============================================================================
-- WHO COUNTS AS A DEV
-- ============================================================================
-- USER IDS ARE THE RELIABLE HALF. A username can be changed by its owner, at which point the
-- name check silently stops matching -- and worse, the freed name can be taken by a stranger who
-- would then inherit the skips. The names are kept only as a fallback for accounts whose id is
-- not written down yet; delete a name as soon as its id is filled in.
--
-- The two ids below are the ones the Food realm already has on file (PlayerStats.server.lua:330
-- and :380). itsmaddmax2's id is not recorded anywhere in either repo, so that one is still
-- name-only -- fill it in and drop the name.
local DEV_USER_IDS = {
	[1086836724] = true,  -- lando5485
	[1418148401] = true,  -- Broskie310111
}
local DEV_USERNAMES = {
	["itsmaddmax2"] = true,
}

-- STUDIO IS ALWAYS A DEV. Play-solo runs as whatever account is signed in, and a test build that
-- refuses its own test commands is worse than useless. This is client-side and Studio-only, so it
-- cannot leak into a live server.
local function resolve()
	if RunService:IsStudio() then return true, "Studio" end
	if DEV_USER_IDS[player.UserId] then return true, "user id" end
	if DEV_USERNAMES[string.lower(player.Name)] then return true, "username" end
	return false, nil
end

local ok, how = resolve()
_G.questDevOK = ok

if ok then
	print(("[QuestDevGate] quest skip commands ENABLED for %s (matched by %s) -- /done, /complete, "
		.. "/blast, /unlockcave, /mine, /fix, /freeze, /warm, /start, /pancakewake, "
		.. "/courier, /wood"):format(player.Name, how))
else
	print("[QuestDevGate] quest skip commands are off for this account (dev only).")
end
