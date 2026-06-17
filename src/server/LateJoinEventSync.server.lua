--======================================================================
-- LateJoinEventSync.server.lua  (Script)
--======================================================================
-- LATE-JOINER CATCH-UP for the server-wide BIG EVENTS (Rocket / Meteor).
-- (UFO / Ice Age / Mutation were removed from the game.)
--
-- When a big event is already in progress and a NEW player joins, this re-sends that event's EXACT
-- current state to ONLY that player (FireClient): the recorded "start" payload (sky + variant + the
-- client ambient SOUND + particle/snow volume + "Go to Island 1" button) followed by the recorded
-- CURRENT phase + payload (current snow density, construction sound, banner). So a late-joiner sees AND
-- hears the same thing existing players do, instead of just the looping sound.
--   * EXACT phase/payload is read from _G.BigEvents[key].currentPhase / .currentPayload / .startPayload,
--     which each manager now records as it broadcasts (purely additive recording in the managers).
--   * SOUND rides along with the visuals: Rocket's construction loop is client-played on
--     "constructionStart" (recreated by the phases we replay). The server-made Sounds (Meteor intro,
--     Rocket countdown, all in Workspace) already replicate to late-joiners on their own, so no separate
--     sound mechanism was needed.
--   * 3D content: the Rocket build is ModelStreamingMode.Persistent (replicates regardless of join time).
--
-- ADDITIVE + READ-ONLY by design:
--   * It only READS the existing _G.BigEvents[key].isRunning() active flags (set by the five managers)
--     and REUSES each event's existing sync RemoteEvent. It maintains no event state of its own.
--   * It NEVER FireAllClients, never starts/stops/retimes any event, never touches the 7-min scheduler,
--     sounds, music, hazards, or any mechanic. It targets ONLY the newly-joined player via FireClient.
--   * It does nothing when no event is active.
--
-- One central script — the catch-up logic is NOT buried inside the individual event files.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The SAME sync RemoteEvents the event managers broadcast on (keyed to match _G.BigEvents keys).
local syncs = {
	rocket   = ReplicatedStorage:WaitForChild("RocketEventSync", 30),
	meteor   = ReplicatedStorage:WaitForChild("MeteorSync", 30),
}

-- FALLBACK CATCH-UP RECIPE: used ONLY if a manager hasn't recorded its phase yet (the tiny window right
-- at event start, before the first broadcast). Best-effort phase(s) sent with nil payload; every
-- "start"/"main" client handler guards its payload (payload and ... / typeof(payload)=="table"), so nil
-- safely falls back to defaults. Normally catchUp() replays the EXACT recorded phase/payload instead.
local CATCHUP = {
	rocket   = { "start" },          -- banner + "Go to Island 1" button (3D build is Persistent-streamed)
	meteor   = { "start", "main" },  -- dark-red storm sky
}

-- Re-establish every CURRENTLY-active big event for ONE player. For each active event we replay the
-- EXACT recorded state: "start" with the recorded START payload (re-applies the sky + variant + client
-- ambient SOUND + particle/snow volume + teleport button), then the recorded CURRENT phase + its payload
-- (current snow density / construction sound / banner). If a manager hasn't recorded a phase yet (the
-- tiny window right at event start), we fall back to the best-effort CATCHUP recipe with nil payload.
-- Reads _G.BigEvents live at fire time, so an event that ended while we waited is simply skipped.
local function catchUp(player)
	local reg = _G.BigEvents
	if not reg then return end -- managers haven't registered yet (or none exist) -> nothing to do
	for key, entry in pairs(reg) do
		local sync = syncs[key]
		if sync and entry and entry.isRunning and entry.isRunning() then
			if entry.currentPhase then
				-- EXACT replay (state recorded by the manager): base "start" setup, then the live phase.
				pcall(function() sync:FireClient(player, "start", entry.startPayload) end) -- NEW player ONLY
				if entry.currentPhase ~= "start" then
					pcall(function() sync:FireClient(player, entry.currentPhase, entry.currentPayload) end)
				end
			else
				-- Fallback: phase not recorded yet -> best-effort recipe, nil payload (handlers default safely).
				for _, phase in ipairs(CATCHUP[key] or { "start" }) do
					pcall(function() sync:FireClient(player, phase) end)
				end
			end
		end
	end
end

-- TRIGGER: the client fires RequestPlayerState once its HUD + handlers are built (the same ready
-- handshake the gut-label / gamepass restore uses). We wait a short margin so the per-event UI LocalScripts
-- have finished connecting their sync handlers, then catch the player up. (No event active -> catchUp no-ops.)
local RequestPlayerState = ReplicatedStorage:WaitForChild("RequestPlayerState", 30)
if RequestPlayerState then
	RequestPlayerState.OnServerEvent:Connect(function(player)
		task.spawn(function()
			task.wait(2) -- let the parallel event-UI scripts finish :Connect-ing before we re-send
			if player and player.Parent then catchUp(player) end
		end)
	end)
end

print("[LateJoinEventSync] ready -- late-joiners will be caught up on any in-progress big event")
