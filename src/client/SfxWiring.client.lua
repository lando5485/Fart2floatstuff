--======================================================================
-- SfxWiring.client.lua  (LocalScript)
--======================================================================
-- Connects the Sfx module to the game. The module is just a speaker; this is what decides when it talks.
--
-- Right now you can tap every button in this game and hear nothing. That is the loudest missing thing in the
-- whole HUD -- a button that makes no noise reads as a button that might not have worked, so kids tap it
-- again, which is how a UI ends up feeling broken when it is functioning perfectly.
--
-- ===== IT DOES NOT TOUCH ANY EXISTING SCRIPT =====
-- It sweeps PlayerGui and wires buttons from the outside, and it watches signals that already exist. Nothing
-- in CoreClient, ShopClient or PetFollow has to change -- which matters because PetFollow is at Luau's 200-local
-- ceiling and cannot be edited at all, and PlayerStats runs as two copies.
--
-- ===== WHAT IT DELIBERATELY DOES NOT PLAY =====
-- No purchase sound. ShopClient already owns that one -- it logs "crunch sound armed -- plays on CurrentPower
-- RISING only" -- and a second sound on the same signal is not twice as satisfying, it is a bug you can hear.
-- The rule for this whole file: if something already makes a noise, leave it alone.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

if _G.__SfxWiringClient then
	warn("[SfxWiring] a SECOND copy is running -- this one is bailing out.")
	return
end
_G.__SfxWiringClient = true

--======================================================================
-- OFF BY DEFAULT
--======================================================================
-- Reverted at your request: the game makes no more noise than it did before this script existed.
--
-- WHY IT WAS TURNED OFF RATHER THAN DELETED. The wiring was fine; the SOUND was not. Every cue is currently
-- the same recording at a different pitch, because six of this place's sound ids are broken and only one
-- loads -- so a click was a chipmunk-pitched version of a chime, on every single tap. That is worse than
-- silence, and no amount of wiring fixes it.
--
-- TO TURN IT BACK ON: put real asset ids into CUES in Shared/Sfx.luau, then set ENABLED = true here. The
-- fallback exists so a missing id degrades instead of erroring -- it was never meant to BE the sound set.
local ENABLED = false

local WIRE_BUTTON_CLICKS = true  -- only consulted when ENABLED is true
local WIRE_EVENT_CUES    = true  -- deny / reward / level-up; likewise gated by ENABLED

local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))
_G.Sfx = Sfx   -- published so any other script can call _G.Sfx.play("reward") without a require

--======================================================================
-- 1. EVERY BUTTON CLICKS
--======================================================================
-- Sfx.button() sets a "SfxWired" attribute and refuses to wire the same button twice, so the boot sweep and
-- the live DescendantAdded watcher cannot double up on a button that existed before this script ran.
--
-- SOME BUTTONS ARE NOT BUTTONS. Several full-screen backdrops in this game are TextButtons used purely to
-- swallow clicks (WormholeMenu.Backdrop, SettingsPanelGui.Backdrop, the PetHouse dimmer). Those must stay
-- silent: a click sound when you tap dead space tells the player something happened when nothing did.
local SILENT_NAMES = {
	Backdrop = true, Dim = true, Dimmer = true, Shade = true, Blocker = true, Catcher = true,
}
local function isSilent(btn)
	if SILENT_NAMES[btn.Name] then return true end
	-- a transparent button covering most of the screen is a click-catcher whatever it is called
	local sz = btn.AbsoluteSize
	if btn.BackgroundTransparency >= 0.99 and sz.X > 600 and sz.Y > 400 then return true end
	return false
end

local function wire(inst)
	if inst:IsA("GuiButton") and not isSilent(inst) then
		Sfx.button(inst, "click")
	end
end

local function sweep()
	for _, d in ipairs(PlayerGui:GetDescendants()) do wire(d) end
end

if ENABLED and WIRE_BUTTON_CLICKS then
	task.spawn(function()
		-- The HUD is built over several seconds by a dozen scripts (CoreClient, RailGuard, TokenHud,
		-- SkinCrateClient all add buttons well after join), so one sweep at boot would miss most of them. A few
		-- spaced sweeps catch the build-out; DescendantAdded below catches everything after that.
		for _ = 1, 6 do
			sweep()
			task.wait(2)
		end
	end)
	PlayerGui.DescendantAdded:Connect(function(d)
		-- one frame of grace: AbsoluteSize is 0 until the instance has been laid out, and isSilent() reads it
		task.defer(function() if d.Parent then wire(d) end end)
	end)
end

--======================================================================
-- 2. REFUSALS SAY NO
--======================================================================
-- The one place the game actively tells you "that didn't work" and currently does it in total silence.
task.spawn(function()
	if not (ENABLED and WIRE_EVENT_CUES) then return end
	local ev = ReplicatedStorage:WaitForChild("StomachFullEvent", 30)
	if not ev then return end
	ev.OnClientEvent:Connect(function() Sfx.play("deny") end)
	print("[SfxWiring] refusals wired -- StomachFullEvent plays the deny cue")
end)

--======================================================================
-- 3. TOKENS ARRIVING SOUND LIKE A REWARD
--======================================================================
-- Crate tokens are granted from half a dozen places (island tasks, daily tasks, streaks, the secret trader).
-- Rather than hooking each of them, watch the balance TokenHud already keeps live in _G.crateTokenBalance --
-- one watcher covers every source, including sources added later.
task.spawn(function()
	if not (ENABLED and WIRE_EVENT_CUES) then return end
	local last = tonumber(_G.crateTokenBalance)
	while true do
		task.wait(0.35)
		local now = tonumber(_G.crateTokenBalance)
		if now and last and now > last then Sfx.play("reward") end
		if now then last = now end
	end
end)

--======================================================================
-- 4. PET LEVEL-UPS
--======================================================================
-- The pet is the thing kids are most attached to and it levels constantly during a flight.
--
-- The signal is PetEquipBroadcast, which the server already fires with reason="levelup" every time a pet
-- gains a level -- carrying {userId, petId, level, ...}. RemotePets listens to the same remote and explicitly
-- ignores the local player ("own pet is PetFollow's job"), so hooking OUR entry here steps on nothing.
-- Reading the level off this covers every route to it -- XP from gas, coins, distance, islands -- without
-- touching PetSystem or PetFollow.
task.spawn(function()
	if not (ENABLED and WIRE_EVENT_CUES) then return end
	local ev = ReplicatedStorage:WaitForChild("PetEquipBroadcast", 30)
	if not ev then return end
	local last
	ev.OnClientEvent:Connect(function(info)
		if type(info) ~= "table" or info.userId ~= player.UserId then return end
		local lvl = tonumber(info.level)
		if not lvl then return end
		-- Only a RISE. The same remote fires on equip, respawn and the join catch-up, and swapping to a
		-- lower-level pet must not sound like an achievement.
		if last and lvl > last then Sfx.play("levelup") end
		last = lvl
	end)
	print("[SfxWiring] pet level-ups wired via PetEquipBroadcast")
end)

if ENABLED then
	print("[SfxWiring] ready -- every button clicks, refusals deny, tokens reward, pets level up")
else
	print("[SfxWiring] OFF -- no sounds are played. Put real ids in Shared/Sfx.luau CUES, then set ENABLED = true.")
end
