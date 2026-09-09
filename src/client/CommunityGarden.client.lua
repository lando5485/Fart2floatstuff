--======================================================================
-- CommunityGarden.client.lua  (LocalScript)  -- STAGE 1 community garden CLIENT side.
--======================================================================
-- Tracks the per-player watering cooldown, toasts its state ("Come back tomorrow!"), points the guide arrows
-- + banner at the WaterSpot, and plays the local watering SPLASH effect + sound when the server broadcasts a
-- water. Purely cosmetic -- it never touches flight/gameplay.
--
-- WATERING IS THE CAN, AND ONLY THE CAN. This script used to also put a "Water the Garden" hold-E
-- ProximityPrompt on the WaterSpot, which did exactly what swinging the Gardener's can does. Two controls for
-- one action taught nothing and made the can look optional, so the prompt is gone and the server enforces it
-- (CAN_REQUIRED in CommunityGarden.server.lua). The WaterSpot itself stays -- it anchors the arrows, the
-- banner and the server's range check.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local GardenWaterEvent = ReplicatedStorage:WaitForChild("GardenWaterEvent", 60)
if not GardenWaterEvent then return end

-- find the WaterSpot marker by name (inside Island_1_BeanFarm or anywhere in Workspace), after it exists
local function resolveWaterSpot()
	for _ = 1, 120 do
		local island
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") and string.find(m.Name, "Island_1_BeanFarm", 1, true) then island = m; break end
		end
		local p = (island and island:FindFirstChild("WaterSpot", true)) or Workspace:FindFirstChild("WaterSpot", true)
		if p and p:IsA("BasePart") then return p end
		task.wait(1)
	end
	return nil
end

-- THE "GardenToast" SCREENGUI IS GONE. It was a 420x54 label at y 0.68 in its own ScreenGui, gated by an
-- Enabled flag -- a private message box that had already caused one visible bug (it lingered over the
-- bottom HUD as a dark band, see the [TOASTFIX] note this replaces) and had already been moved once to
-- dodge the gas meter and MeteorIU's reward popup. Every message it carried is a banner now, so there is
-- no box to place, nothing to collide with, and no flag to get stuck.
--
-- Swept, because deleting the code that builds it does not delete one a stale baked-in copy already built.
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	for _ = 1, 5 do
		local old = pg:FindFirstChild("GardenToast")
		if old then
			old:Destroy()
			print("[Garden][client] removed a leftover GardenToast box -- garden replies are banners now")
		end
		task.wait(2)
	end
end)
--======================================================================
-- THE TOAST IS A BANNER NOW  (this file was half-migrated; this is the other half)
--======================================================================
-- The watering-can HINT already went to NotifyCenter as a pinned instruction (see showHint far below), but
-- these short REPLIES -- "come back tomorrow", "you can't water here" -- were left behind in a private
-- toast at y 0.68 with its own dark-green paint and its own Enabled flag. So one feature spoke to the
-- player in two different places depending on which thing it had to say.
--
-- They are the same class of message as the wormhole's "land on an island first" and the realm portals'
-- refusals: a short answer to something the player just tried. They belong in the hero lane with every
-- other answer -- same card, same size, same place, same priority order.
--
-- `toast()` keeps its name and signature so all four call sites below are unchanged; only where the words
-- appear has moved. EVENT priority: a refusal must not shove an island landing off screen, and it queues
-- behind the watering DIRECTIONS (QUEST rank) rather than covering the very instruction it is correcting.
--
-- NotifyCenter owns the hide, so the token guard and the Enabled flag are both gone -- and with them the
-- whole class of bug this file already had to fix once (see the [TOASTFIX] note above).
-- ===== THE SAME REPLY TWICE IN A ROW IS ONE REPLY =====
-- The server can fire the same refusal several times in under a second -- 'toofar' goes out on every swing
-- of the can, and a player holding the button gets two or three before they have let go. Each push restarts
-- the banner: it slides out, slides back in and re-tweens mid-sentence, which reads as the HUD stuttering.
-- (The boot log caught it: the same "You can't water here" line pushed twice, 0.5s apart.)
--
-- So an identical message inside REPEAT_WINDOW is dropped. Not a general banner rule -- NotifyCenter must
-- keep letting a genuine second thing through -- just this file refusing to say the same sentence twice in
-- the time it takes to read it once.
local REPEAT_WINDOW = 4
local lastText, lastAt = nil, 0

local function toast(text, colour, seconds)
	if text == lastText and (os.clock() - lastAt) < REPEAT_WINDOW then return end
	lastText, lastAt = text, os.clock()

	local NC = _G.NotifyCenter
	if NC and NC.push then
		pcall(NC.push, {
			text     = text,
			color    = colour or Color3.fromRGB(46, 120, 60), -- the garden's green, not the generic banner green
			priority = (NC.PRIORITY and NC.PRIORITY.EVENT) or 80,
			duration = seconds or 3.5,
		})
		return
	end
	warn("[Garden][client] " .. text .. "  (NotifyCenter unavailable -- not shown on screen)")
end

-- the watering splash: a quick burst of blue droplet sparkles over the field + a sound
local function playSplash(pos, soundId)
	local host = Instance.new("Part"); host.Anchored = true; host.CanCollide = false; host.CanQuery = false; host.Transparency = 1
	host.Size = Vector3.new(1,1,1); host.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)); host.Parent = Workspace
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(Color3.fromRGB(120,200,255), Color3.fromRGB(80,150,255))
	em.Lifetime = NumberRange.new(0.6, 1.1); em.Rate = 0; em.Speed = NumberRange.new(6, 14); em.SpreadAngle = Vector2.new(60, 60)
	em.Acceleration = Vector3.new(0, -40, 0); em.Size = NumberSequence.new(0.7); em.LightEmission = 0.6
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.1), NumberSequenceKeypoint.new(1,1) })
	em.Parent = host; em:Emit(60)
	if soundId and soundId ~= "" then
		local s = Instance.new("Sound"); s.SoundId = soundId; s.Volume = 0.6; s.Parent = host -- \xE2\x9A\xA0 REPLACE WITH WATERING SOUND (server-supplied placeholder)
		pcall(function() s:Play() end)
	end
	Debris:AddItem(host, 2)
end

-- ===== wire everything =====
-- THE WATERSPOT HOLD-E PROMPT IS GONE. Watering the global garden used to have two routes that did the exact
-- same thing: hold E on the WaterSpot, or take the Gardener's can and swing it. The can is the one that reads
-- as an action and the one all the guidance (arrows, banner, Gardener dialogue) is built around, so it is now
-- the only route -- the server backs this with CAN_REQUIRED = true.
--
-- We still resolve the WaterSpot: it is the ANCHOR for the guide arrows and the proximity banner below, and
-- the server measures WATER_RANGE from it. Only the prompt is removed.
local waterSpot = resolveWaterSpot()
if not waterSpot then warn("[Garden][client] WaterSpot not found -- no arrows/banner anchor"); return end

-- SWEEP AN OLD PROMPT. The WaterSpot persists across garden rebuilds, and a baked-in copy of an older version
-- of this script (or an older session) may have parented a "WaterGardenPrompt" to it. Simply not creating one
-- here would leave that stale prompt sitting on the spot, still holdable and now answered with "needcan".
for _, d in ipairs(waterSpot:GetDescendants()) do
	if d:IsA("ProximityPrompt") and d.Name == "WaterGardenPrompt" then
		d:Destroy()
		print("[Garden][client] removed a leftover WaterGardenPrompt -- the watering can is the only way to water now")
	end
end

-- COOLDOWN STATE. The daily cooldown is still owned and enforced by the SERVER; this is only a local mirror of
-- it. It used to drive the prompt's label ("Come back tomorrow!"); with the prompt gone the player learns their
-- cooldown from the toast below and from the Gardener simply not offering a can, so this is now bookkeeping
-- only -- kept because the server still pushes `cooldown` payloads and they have to land somewhere sane.
local waterReady = true
local cdToken = 0 -- cancels a stale re-ready timer when a newer cooldown state arrives
local function setReady()
	cdToken = cdToken + 1
	waterReady = true
end
local function setOnCooldown(secs)
	cdToken = cdToken + 1; local mine = cdToken
	waterReady = false
	task.delay(secs, function() if cdToken == mine then setReady() end end) -- auto-ready when the day passes
end

GardenWaterEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.kind == "splash" then
		pcall(playSplash, Vector3.new(payload.x or 0, payload.y or 0, payload.z or 0), payload.sound)
		-- Only for OUR pour: this event is broadcast to everyone near the garden, and buzzing every player
		-- each time anybody waters would make a busy garden unbearable.
		if payload.who == nil or payload.who == game:GetService("Players").LocalPlayer.Name then
			if _G.hapticPulse then pcall(_G.hapticPulse, "bump") end
		end
	elseif payload.kind == "cooldown" then
		if (payload.secs or 0) > 0 then setOnCooldown(payload.secs) else setReady() end
	elseif payload.kind == "denied" then
		toast("\xF0\x9F\x92\xA7 Come back tomorrow!")
		setOnCooldown(payload.secs or 0)
	elseif payload.kind == "needcan" then
		-- Only reachable from a stale client now that the WaterSpot prompt is gone. Name the real fix rather
		-- than reusing "Come back tomorrow!", which would send someone away who could water right now.
		toast("\xF0\x9F\x92\xA7  GET A CAN FIRST!")
	elseif payload.kind == "toofar" then
		-- They swung the can somewhere that isn't the water spot. Say so plainly and immediately -- the arrows
		-- are already pointing at the right place, so the toast only has to name the mistake.
		toast("\xE2\x9D\x8C  CAN'T WATER HERE!")   -- the arrows already say where; four words is the rule
	elseif payload.kind == "celebrate" then
		-- STAGE 2 harvest celebration: gold, and held a little longer than an ordinary reply.
		--
		-- This branch used to hand-drive the old label: repaint it gold, set `Visible`, enable the
		-- ScreenGui, take a token, then repaint it back to green on the way out. It was ALSO the branch
		-- that had the worst bug in the file -- it originally set only `toastLbl.Visible` and not
		-- `toastGui.Enabled`, so unless an ordinary toast happened to have fired moments earlier the
		-- server-wide harvest celebration NEVER APPEARED AT ALL.
		--
		-- As a banner there is nothing to repaint and nothing to restore: the colour is a field on the
		-- message, so gold-for-this-one cannot leak into the next message the way a mutated shared label
		-- could. EVENT priority, like everything else in this file.
		local txt = payload.text or "\xF0\x9F\x8C\xBB The garden bloomed! Everyone gets 2x coins!"
		toast(txt, Color3.fromRGB(210, 160, 40), 5)
	end
end)

-- ask the server for our current cooldown so the local mirror is right on join
task.spawn(function() task.wait(1); pcall(function() GardenWaterEvent:FireServer("query") end) end)

--======================================================================
-- WATERING CAN GUIDANCE -- arrows to the water spot + a "what do I press?" banner.
--======================================================================
-- The can has no hotbar slot (CoreClient hides the Backpack CoreGui), it is auto-equipped, and Tool.Activated
-- is a plain tap -- so without this a player is handed an object with no stated purpose and no stated control.
-- Three things fix that, and all three are driven by ONE attribute the server already sets when it hands the
-- can over (CarryingWateringCan):
--   1. the existing green chevron trail is pointed at the WaterSpot (via _G.guideTrailTo -- we never build a
--      second trail; GardenGuideTrail owns the arrows and its override beats its own tutorial route),
--   2. a banner names the control: "TAP ANYWHERE to pour" once they're in range, "follow the arrows" before,
--   3. the Gardener says the same thing out loud when he hands it over (server side).
-- Everything here is display-only: the server still decides whether a swing actually waters anything.
local RunService = game:GetService("RunService")
local CARRY_ATTR = "CarryingWateringCan"
local POUR_RANGE = 26   -- a shade under the server's WATER_RANGE (28) so the banner never says "tap" a step
                        -- before a tap would actually be accepted

--======================================================================
-- THE HINT IS A PINNED BANNER NOW, NOT A PANEL OF ITS OWN
--======================================================================
-- This used to be a bespoke TextLabel floating at y=0.60, in its own ScreenGui, with its own colours, its own
-- stroke rules and its own breathing pulse. Three problems with that, all fixed by handing the job to
-- NotifyCenter:
--
--   1. IT WAS IN THE MIDDLE OF THE SCREEN, which is where this game puts nothing else. Every other piece of
--      "here is what is happening" text in the game arrives as a banner at the top, so the one that mattered
--      most to a confused player was the one in the least familiar place.
--   2. IT COMPETED. Being its own ScreenGui meant it could sit on screen at the same time as a hero banner,
--      so a player could be told two things at once and read neither.
--   3. IT WAS A FOURTH SET OF COLOURS. Its own blue, its own corner radius, its own stroke -- all carefully
--      tuned (see the git history for the legibility fight), and all of it duplicated work that the hero card
--      already does correctly.
--
-- As a PIN it is the same 500x65 card, in the same place, with the same paint as every other banner -- and
-- because it is pinned rather than pushed, it holds the slot until the watering is actually done instead of
-- expiring on a timer while somebody is still walking over. Everything else queues behind it and plays after.
local HINT_PIN = "WateringCan"   -- our pin id; unpin(HINT_PIN) can only ever release OUR banner

-- Tracks whether we currently believe the pin is up, so we only call unpin on the transition. unpin is
-- id-guarded and cheap, but calling it every Heartbeat would fight anything else that took the slot.
local hintPinned = false

-- ===== A PIN NEEDS A CEILING =====
-- The can has NO server-side timeout: nothing takes it back if you simply never use it. So a player who
-- picks one up and then wanders off to fly for half an hour would hold the hero slot for that whole time --
-- and because a pin blocks the queue by design, every island banner, reward nudge and restock announcement
-- behind it would be stuck too. A standing instruction is only worth holding the screen while somebody might
-- still act on it; well past that it has stopped being an instruction and become furniture.
--
-- The arrows and the pulsing soil are NOT on this timer. They cost nobody anything and they still point at
-- the right place, so the guidance survives -- it just stops occupying the one slot everything else needs.
local HINT_MAX_SECONDS = 90
local hintSince    = 0
local hintExpired  = false     -- reset each time the can is picked up, so the next pickup gets a fresh 90s
local hintPushedAt = 0         -- fallback path only: last time we re-pushed a plain banner (see showHint)

-- Declared before showHint because the expiry path below releases the pin itself.
local function clearHint()
	if not hintPinned then return end
	hintPinned = false
	if _G.NotifyCenter and _G.NotifyCenter.unpin then
		_G.NotifyCenter.unpin(HINT_PIN)
	end
end

local function showHint(text, color)
	if hintExpired then return end
	if not hintPinned then hintSince = os.clock() end
	if os.clock() - hintSince > HINT_MAX_SECONDS then
		hintExpired = true
		clearHint()
		return
	end
	hintPinned = true

	local NC = _G.NotifyCenter
	if NC and NC.pin then
		-- ===== RANK.QUEST -- THE TOP OF THE WHOLE BANNER ORDER =====
		-- While this quest is live and unfinished, its step directions outrank EVERYTHING, including the
		-- new-player tutorial directions and the exclusive milestone banners (first meal, first full tank,
		-- achievement unlocks). The player is holding a watering can right now and every other message can
		-- wait one beat -- so this pin simply covers whatever else was up.
		--
		-- It is a COVER, not a cancel: the tutorial pin underneath is untouched and reappears mid-sentence
		-- the moment clearHint() releases this one. And clearHint() is called the instant the quest is done
		-- (the can goes away -- used, dropped, or died), which is exactly the "as soon as the garden watering
		-- quest is completed, its directions drop back to normal priority" rule. There is nothing left at
		-- QUEST rank afterwards, so tutorial exclusivity resumes on its own with no second switch to flip.
		--
		-- No `priority` field: a pin is ranked against other PINS, not against pushes. Passing one would
		-- imply a contest that does not happen.
		NC.pin(HINT_PIN, {
			rank  = (NC.RANK and NC.RANK.QUEST) or 200,
			text  = text,
			color = color,
		})
		return
	end

	-- ===== FALLBACK: A NOTIFYCENTER WITHOUT pin =====
	-- Reaching here means _G.NotifyCenter is an OLDER build than this file expects -- in practice a stale
	-- duplicate of NotifyCenter that loaded after the Rojo one and replaced the global (NotifyCenter now
	-- reclaims it, but there is a boot window before that lands, and the other realms carry their own copies).
	--
	-- Without this branch the symptom is the worst possible one: the old mid-screen panel is gone, the pin
	-- call quietly no-ops, and the player is handed a watering can with NOTHING on screen telling them what
	-- to do. So fall back to an ordinary timed banner, re-pushed as it expires. It is a worse version of the
	-- feature -- it can be preempted and it blinks between pushes -- but it is the same words in the same
	-- place, and the instruction survives.
	if NC and NC.push and (os.clock() - hintPushedAt) > 2.5 then
		hintPushedAt = os.clock()
		pcall(NC.push, {
			text     = text,
			color    = color,
			-- QUEST, not EVENT. Even on the degraded path these directions have to sit above the tutorial
			-- and achievement banners, or a milestone toast talks over the one instruction the player is
			-- currently trying to follow.
			priority = (NC.PRIORITY and NC.PRIORITY.QUEST) or 200,
			duration = 3,
		})
	end
end

-- SWEEP THE OLD PANEL. This script used to build a "WateringCanHint" ScreenGui with ResetOnSpawn = false, so
-- one built by a previous session -- or by a stale copy of this script baked into the place, which is the
-- normal hazard here since Rojo only ever adds -- would hang around forever with nothing left to hide it.
-- Same treatment the leftover WaterGardenPrompt gets above.
task.spawn(function()
	for _ = 1, 5 do
		local old = player:FindFirstChild("PlayerGui")
		old = old and old:FindFirstChild("WateringCanHint")
		if old then
			old:Destroy()
			print("[Garden][client] removed a leftover WateringCanHint panel -- the hint is a pinned banner now")
		end
		task.wait(2)
	end
end)

-- ---------------------------------------------------------------------------------------------------
-- SHOW THEM THE SOIL UNTIL THEY WATER IT.
-- ---------------------------------------------------------------------------------------------------
-- Picking up the can answers "what do I do" and leaves "where" wide open. The arrows point at the WaterSpot,
-- but what a new player is hunting for is the GROUND, and a dark brown bed among dark brown stone is the
-- least findable object in the garden. So the beds say it themselves: they breathe green.
--
-- IT STOPS WHEN THE JOB IS DONE, not on a timer. A hint that fades after three pulses is a hint that expires
-- while somebody is still walking over -- and the one player who needs it most, the one taking longest to
-- find the spot, is the one it abandons. It runs until they have actually watered.
--
-- "ACTUALLY WATERED" IS waterReady, AND THAT CHOICE MATTERS. The obvious signal is the splash, and the
-- splash is wrong: it is FireAllClients, so ANY player watering anywhere would clear this player's hint and
-- leave them standing in a garden that just stopped explaining itself. The cooldown message is FireClient --
-- it is the only thing the server says to YOU about YOUR watering, so it is the only honest answer to "have
-- I done it yet". It also means somebody who already watered today never sees the pulse at all: the join
-- query comes back on cooldown, and the hint knows there is nothing to point at.
--
-- CLIENT-SIDE COLOUR. These parts belong to the server; writing Color here changes only what THIS player
-- sees, which is exactly right for a hint aimed at one person. Nobody else's garden blinks.
local SOIL_PARTS = { CenterBed = true, InnerBed = true, OuterBed = true }
local PULSE_GREEN = Color3.fromRGB(96, 210, 96)
local soilPulsing = false

local function pulseSoil()
	if soilPulsing then return end
	soilPulsing = true

	task.spawn(function()
		local beds = {}
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") and SOIL_PARTS[d.Name] then
				beds[#beds + 1] = { part = d, colour = d.Color }
			end
		end
		if #beds == 0 then soilPulsing = false; return end

		-- Carrying AND still owing a watering. Either going false ends it: they put the can away, or they
		-- did the thing the hint was asking for.
		while player:GetAttribute(CARRY_ATTR) == true and waterReady do
			for _, b in ipairs(beds) do
				if b.part.Parent then
					TweenService:Create(b.part, TweenInfo.new(0.45), { Color = PULSE_GREEN }):Play()
				end
			end
			task.wait(0.5)
			for _, b in ipairs(beds) do
				if b.part.Parent then
					TweenService:Create(b.part, TweenInfo.new(0.45), { Color = b.colour }):Play()
				end
			end
			task.wait(0.5)
		end

		-- Put the colour back by ASSIGNMENT as well as by tween. A tween still running when the loop exits
		-- -- or when the garden rebuilds underneath it -- leaves a bed stuck mid-green, and a permanently
		-- lime flowerbed is a far more noticeable bug than the hint was a feature.
		task.wait(0.5)
		for _, b in ipairs(beds) do
			if b.part.Parent then b.part.Color = b.colour end
		end
		soilPulsing = false
	end)
end

local wasCarrying = false
RunService.Heartbeat:Connect(function()
	local carrying = player:GetAttribute(CARRY_ATTR) == true
	if not carrying then
		if wasCarrying then
			-- put everything away the moment the can is gone (used, dropped, died) -- guideTrailClear only
			-- drops OUR override, so the trail's own tutorial route is untouched. Releasing the pin here is
			-- what lets everything that queued up behind it finally play.
			wasCarrying = false
			clearHint()
			if _G.guideTrailClear then _G.guideTrailClear() end
		end
		return
	end
	-- Start it on the transition into carrying, and re-start it if they pick the can back up still owing a
	-- watering. pulseSoil guards itself, so calling it while a pulse is already running does nothing.
	if not wasCarrying then
		if waterReady then pulseSoil() end
		-- Fresh can, fresh 90 seconds: somebody who timed out, went flying and came back for another go gets
		-- the banner again rather than being punished for the last attempt.
		hintExpired = false
		hintSince   = os.clock()
	end
	wasCarrying = true

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and waterSpot and waterSpot.Parent) then return end

	-- Point the shared trail at the spot. Called every frame on purpose: guideTrailTo is cheap and
	-- self-correcting, and it means the arrows follow the spot if the garden ever rebuilds it.
	if _G.guideTrailTo then _G.guideTrailTo(waterSpot.Position) end

	-- Re-pinning with the same id every frame is a REPAINT, not a re-announcement: NotifyCenter only
	-- animates a pin in when the id changes, so this costs two label writes and the banner never flaps.
	-- That is what lets the wording follow the player from "walk over there" to "you can do it now"
	-- inside one continuous banner, instead of two banners fighting for the same slot.
	local dist = (hrp.Position - waterSpot.Position).Magnitude
	if dist <= POUR_RANGE then
		showHint("\xF0\x9F\x92\xA7  TAP ANYWHERE TO POUR!", Color3.fromRGB(46, 150, 70)) -- green = do it now
	else
		showHint("\xF0\x9F\x92\xA7  FOLLOW THE GREEN ARROWS", Color3.fromRGB(26, 79, 214))
	end
end)
