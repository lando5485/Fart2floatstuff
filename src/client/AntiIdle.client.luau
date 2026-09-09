--======================================================================
-- AntiIdle.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- KEEPS PLAYERS FROM BEING DISCONNECTED FOR SITTING STILL.
--
-- Roblox disconnects a client after about twenty minutes with no input. That is fine for most games and
-- wrong for this one: the AFK Token Farm is a feature built around standing still, the campfire is a place
-- to sit and do nothing, and a player watching the blimp go round is not doing anything either. Twenty
-- minutes in, all three of them get thrown out.
--
-- ===== HOW IT WORKS =====
-- The timeout is a CLIENT thing and no server code can prevent it -- the only signal is Player.Idled, which
-- fires when Roblox has decided you are idle and is about to act on it. Feeding the input system one
-- synthetic click at that moment resets the timer. ClickButton2 is a RIGHT-click on nothing: it cannot
-- press a button, cannot fire a ClickDetector, cannot move the camera, and cannot be felt by the player.
--
-- ===== WHAT THIS IS AND IS NOT =====
-- It is not an exploit and nothing is being bypassed: this is our own LocalScript, in our own experience,
-- calling a documented Roblox API, and it affects nothing outside this session. What it IS is a use that
-- Roblox's own VirtualUser documentation discourages -- their stated intent for the service is their
-- internal test automation. It is extremely widely shipped in live simulator and idle games. That trade was
-- put to the owner of this game explicitly, several times, and this is the decision: on, for everybody.
--
-- If that call is ever revisited, this is the ONE file to change and there are two switches to do it with:
--     ENABLED = false            -> off entirely; every player times out normally again
--     ONLY_WHILE_FARMING = true  -> narrowed to players actually plugged into an AFK farm (the server sets
--                                   the AFKFarming attribute in AFKTokenFarm.server.lua), so idling
--                                   anywhere else in the game kicks as usual
-- Nothing else in the codebase reaches in here, so flipping either one cannot break another system.
--
-- WORTH KNOWING EITHER WAY: the token farm does NOT depend on this. Away-time is paid from a saved
-- timestamp (see claimAway in AFKTokenFarm.server.lua), so a player who is disconnected still earns up to
-- the 24-hour cap. This keeps them visibly IN the server -- hose on show, leaderboard slot held -- it does
-- not keep them earning.
--======================================================================

local ENABLED            = true
local ONLY_WHILE_FARMING = false   -- true = suppress the kick only for players plugged into a farm

local Players     = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer

-- Rojo ADDS, it never overwrites, so a stale copy baked into the place would run alongside this one and
-- connect Idled twice. Harmless in effect, but the log would lie about how often it fired.
if _G.__AntiIdle then return end
_G.__AntiIdle = true

if not ENABLED then
	print("[AntiIdle] OFF (ENABLED = false) -- players will be disconnected after the usual ~20 idle minutes")
	return
end

local fired = 0

player.Idled:Connect(function()
	if ONLY_WHILE_FARMING and player:GetAttribute("AFKFarming") ~= true then
		return   -- not plugged into a farm: let Roblox take them
	end
	-- pcall because VirtualUser is refused in some contexts (and every future one we cannot see from here).
	-- A failure must cost this player their session, not their client: an error thrown inside Idled would
	-- break the connection and silently stop suppressing from then on.
	local ok, err = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
	fired += 1
	if not ok then
		warn("[AntiIdle] VirtualUser refused (" .. tostring(err) .. ") -- this player will time out normally")
		return
	end
	if fired == 1 then
		print("[AntiIdle] idle timeout suppressed for the first time this session (fires about every 20 minutes)")
	end
end)

print(("[AntiIdle] active for every player%s -- the ~20-minute idle disconnect is suppressed")
	:format(ONLY_WHILE_FARMING and " plugged into an AFK farm" or ""))
