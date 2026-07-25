-- ============================================================================================================
-- PUSH-NOTIFICATION OPT-IN  (client)
--
-- Roblox will NOT deliver a push notification to anyone who has not opted in to THIS experience. So this prompt
-- is not a nice-to-have around the comeback nudge -- it is the whole thing. No opt-in, no notification, ever.
--
-- WHEN WE ASK is the entire design. The temptation is to prompt on join; that is also the worst possible moment,
-- because the player has no idea what your game is yet and the honest answer to "can we notify you?" is "no".
-- A permission prompt is a one-shot: if they decline, Roblox will not let you ask again, and that player is
-- permanently unreachable. So we spend it carefully -- we ask ONLY after the player has done something that made
-- them feel good, and only after they have seen enough of the game to want to come back to it:
--
--   TRIGGER: they have collected 2+ pets AND have been playing for 10+ minutes.
--
-- Both conditions matter. The pets prove they are engaged with the thing the notification is ABOUT (their pets
-- earning coins while away). The 10 minutes filters out the bounce -- someone who quits at minute 3 was never
-- coming back and burning the prompt on them costs a real opt-in from someone who would have.
--
-- Everything here is pcall-guarded and feature-detected. ExperienceNotificationService is relatively new; on an
-- old client, or in Studio where the prompt cannot show, this script simply does nothing rather than erroring.
-- ============================================================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local MIN_PETS     = 2    -- pets collected before we are allowed to ask
local MIN_MINUTES  = 10   -- minutes played this session before we are allowed to ask
local RECHECK_SECS = 30   -- how often to re-test the trigger

-- The service is new enough that a client can lack it entirely. Feature-detect, never assume.
local notifSvc = nil
pcall(function() notifSvc = game:GetService("ExperienceNotificationService") end)
if not notifSvc then
	print("[NotifyOptIn] ExperienceNotificationService unavailable on this client -- opt-in prompt skipped")
	return
end

-- Studio cannot show the real opt-in menu, so asking there tells us nothing and just spams the output.
if RunService:IsStudio() then
	print("[NotifyOptIn] Studio -- opt-in prompt suppressed (it only renders on a live client)")
	return
end

local asked = false

-- The real API is CanPromptOptInAsync() / PromptOptIn(), per the ExperienceNotificationService docs.
-- (An earlier version of this file guessed at CanPromptOptInMenuAsync() / PromptOptInMenu(). Neither exists, so
-- every call threw "not a valid member" inside the pcall and the prompt silently never appeared -- which looked
-- exactly like the player being ineligible. Hence the very loud logging below: a wrong method name and a genuine
-- "you may not prompt" must never again be indistinguishable.)
local function tryPrompt()
	if asked then return end

	-- Roblox decides whether we may prompt at all. It returns false if the player has already opted in, has already
	-- declined, or is otherwise ineligible -- and respecting that is what stops us nagging people.
	local ok, canPrompt = pcall(function()
		return notifSvc:CanPromptOptInAsync()
	end)
	if not ok then
		warn("[NotifyOptIn] CanPromptOptInAsync ERRORED: " .. tostring(canPrompt))
		warn("[NotifyOptIn] ^ that is an API problem on OUR side, not a 'player said no'. Nothing was shown.")
		asked = true -- do not hammer a failing API every 30s
		return
	end
	if not canPrompt then
		print("[NotifyOptIn] Roblox says we may not prompt. That means one of:")
		print("[NotifyOptIn]   * you are ALREADY opted in  -> nothing to accept; /nudge should work right now")
		print("[NotifyOptIn]   * you already DECLINED once -> Roblox will never ask again on this account")
		asked = true
		return
	end

	asked = true
	local okPrompt, err = pcall(function()
		notifSvc:PromptOptIn()
	end)
	if okPrompt then
		print("[NotifyOptIn] opt-in prompt SHOWN -- accept it, then run /nudge")
	else
		warn("[NotifyOptIn] PromptOptIn failed: " .. tostring(err))
	end
end

-- Tells us what the player actually chose, so a "nothing happened" is never ambiguous again.
pcall(function()
	notifSvc.OptInPromptClosed:Connect(function()
		print("[NotifyOptIn] opt-in prompt closed. If you accepted, /nudge will now deliver; if you dismissed it,"
			.. " Roblox will not let us ask this account again.")
	end)
end)

-- ===== THE TRIGGER =====
-- Pet count comes from the same inventory payload the Pet Hub renders, so "collected" here means exactly what the
-- Pet Hub's "2 / 10" counter means -- there is no second, subtly different definition of the number.
local petsCollected = 0
task.spawn(function()
	local invEvent = ReplicatedStorage:WaitForChild("PetInventoryEvent", 30)
	if not invEvent then return end
	invEvent.OnClientEvent:Connect(function(inv)
		if type(inv) == "table" and type(inv.collected) == "number" then
			petsCollected = inv.collected
		end
	end)
end)

task.spawn(function()
	local started = os.clock()
	while not asked do
		task.wait(RECHECK_SECS)
		local minutes = (os.clock() - started) / 60
		if petsCollected >= MIN_PETS and minutes >= MIN_MINUTES then
			tryPrompt()
		end
	end
end)

-- ===== /optin -- THE TEST COMMAND =====
-- Waiting 10 minutes and hatching 2 pets to see whether a prompt appears is not a test loop, so /optin skips the
-- trigger and asks immediately.
--
-- The command is heard by the SERVER, which then fires this remote at us. It is NOT a player.Chatted listener in
-- here, and that is the whole reason /optin appeared to do nothing before: with TextChatService (Roblox's current
-- default) the CLIENT-side Chatted event routinely never fires, so a listener here is dead code. The server always
-- hears the chat; only the client can raise the menu; so the server tells the client. See ComebackNudge.
--
-- This still does NOT skip Roblox's own CanPromptOptInMenuAsync check, and that is deliberate: if it now prints
-- "Roblox says we may not prompt", that is a real answer -- the account has either already opted in (so /nudge
-- will work) or already DECLINED at some point, in which case Roblox will never ask again and you need a
-- different account to test with.
local promptRemote = ReplicatedStorage:WaitForChild("PromptNotifyOptIn", 30)
if promptRemote then
	promptRemote.OnClientEvent:Connect(function()
		print("[NotifyOptIn][TEST] /optin -- forcing the prompt, ignoring the 2-pets/10-minutes trigger")
		asked = false -- clear the once-guard so a repeat /optin can re-ask, if Roblox still allows it
		tryPrompt()
	end)
else
	warn("[NotifyOptIn] PromptNotifyOptIn remote missing -- /optin will not work (is ComebackNudge running?)")
end

print(("[NotifyOptIn] armed -- will ask once the player has %d+ pets and %d+ minutes played (or type /optin)")
	:format(MIN_PETS, MIN_MINUTES))
