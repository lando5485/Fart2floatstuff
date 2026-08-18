-- ============================================================================================================
-- AMBIENT WILDLIFE  (client)
--
-- Butterflies and bees over the Community Garden, and birds circling Bean Farm. The garden is beautiful and
-- completely dead -- nothing in it moves except the gardener and his one songbird. A still scene reads as a
-- diorama; a scene with things drifting through it reads as a place.
--
-- ===== WHY CLIENT-SIDE =====
-- GardenBird runs on the server, which is right for it: it is ONE bird, it perches on a specific NPC, and every
-- player should see it in the same spot. This is the opposite case. Twenty small critters on the server would
-- replicate twenty CFrames per frame to every player, forever, and nobody would be able to tell whether your
-- butterfly and mine were in the same place -- because nobody is watching a butterfly that closely. So each client
-- grows its own. Zero replication, zero server cost.
--
-- Nothing here collides, is queryable, casts shadows, or can be touched. It is scenery that happens to move.
-- ============================================================================================================

local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")
local RunService   = game:GetService("RunService")
local SoundService = game:GetService("SoundService") -- birdsong reads the music's live loudness to balance against it

local BUTTERFLIES = 10
local BEES        = 7
local BIRDS       = 4

local GARDEN_R    = 42   -- studs: how far from the garden centre they wander
local FLY_LOW     = 3    -- height band above the garden floor they stay within
local FLY_HIGH    = 11
local BIRD_R      = 150  -- radius the birds circle the island at
local BIRD_H      = 60   -- how high above the island they circle
local DRAW_DIST   = 260  -- beyond this from the player, freeze everything. A butterfly you cannot see does not
                         -- need to be animated, and this is what keeps 21 critters free rather than merely cheap.

local player = Players.LocalPlayer
local rng = Random.new()

local folder = Instance.new("Folder")
folder.Name = "AmbientWildlife"
folder.Parent = Workspace

local function part(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p:SetAttribute("BaseT", 0) -- what the cull restores to; callers that want a see-through part re-stamp it
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A butterfly: two wings hinged either side of a body. The WINGS are what sell it -- a butterfly that glides with
-- fixed wings reads as a leaf, so the flap is the whole illusion and it has to be big and irregular.
local function buildButterfly(col1, col2)
	local m = Instance.new("Model"); m.Name = "Butterfly"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.12, 0.12, 0.42), Color3.fromRGB(40, 32, 28))
	m.PrimaryPart = body
	local wingL = part(m, "WingL", Vector3.new(0.06, 0.5, 0.62), col1)
	local wingR = part(m, "WingR", Vector3.new(0.06, 0.5, 0.62), col2)
	wingL.Transparency = 0.1; wingR.Transparency = 0.1
	wingL:SetAttribute("BaseT", 0.1); wingR:SetAttribute("BaseT", 0.1)
	return { model = m, body = body, wingL = wingL, wingR = wingR }
end

local function buildBee()
	local m = Instance.new("Model"); m.Name = "Bee"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.22, 0.22, 0.34), Color3.fromRGB(240, 200, 40))
	m.PrimaryPart = body
	part(m, "Stripe", Vector3.new(0.24, 0.24, 0.10), Color3.fromRGB(30, 26, 20)).CFrame = body.CFrame
	local wingL = part(m, "WingL", Vector3.new(0.03, 0.16, 0.30), Color3.fromRGB(230, 245, 255))
	local wingR = part(m, "WingR", Vector3.new(0.03, 0.16, 0.30), Color3.fromRGB(230, 245, 255))
	wingL.Transparency = 0.55; wingR.Transparency = 0.55
	wingL:SetAttribute("BaseT", 0.55); wingR:SetAttribute("BaseT", 0.55)
	return { model = m, body = body, wingL = wingL, wingR = wingR, stripe = m.Stripe }
end

-- A distant soaring bird. It is circling 150 studs out and 60-odd up, so nothing here is about detail -- at
-- that range the whole animal is a few pixels and only the SILHOUETTE survives. The old one was a body block
-- with two straight bars stuck out either side: a plus sign, which is the shape of a plane, not a bird.
-- Three changes, all silhouette:
--   * A TAIL. A bird's outline is a cross with a wedge behind it; without one the body just stops.
--   * A HEAD/neck bump out front, so the cross is not symmetrical front-to-back -- that asymmetry is what
--     tells you which way it is flying.
--   * SWEPT wings (see the pose code): angled back rather than square out, which is how a soaring bird holds
--     them and the difference between reading as a bird and reading as a paper dart.
local function buildBird()
	local m = Instance.new("Model"); m.Name = "SkyBird"; m.Parent = folder
	local body = part(m, "Body", Vector3.new(0.5, 0.4, 1.3), Color3.fromRGB(52, 48, 58))
	body.Shape = Enum.PartType.Ball   -- a rounded body loses the boxy corners the moment it catches the light
	m.PrimaryPart = body
	local head = part(m, "Head", Vector3.new(0.32, 0.30, 0.42), Color3.fromRGB(46, 42, 52))
	head.Shape = Enum.PartType.Ball
	-- Tail: wider than the body and thin, so it reads as a fan from below -- which is the angle the player
	-- almost always sees these from.
	local tail = part(m, "Tail", Vector3.new(0.62, 0.07, 0.78), Color3.fromRGB(58, 54, 66))
	local wingL = part(m, "WingL", Vector3.new(0.08, 0.18, 2.2), Color3.fromRGB(64, 60, 72))
	local wingR = part(m, "WingR", Vector3.new(0.08, 0.18, 2.2), Color3.fromRGB(64, 60, 72))
	return { model = m, body = body, head = head, tail = tail, wingL = wingL, wingR = wingR }
end

-- ===== FIND THE GARDEN + THE ISLAND (both build asynchronously, long after this script starts) =====
local gardenPos, islandPos
task.spawn(function()
	for _ = 1, 240 do
		if not gardenPos then
			local build = Workspace:FindFirstChild("CommunityGardenBuild", true)
			if build then
				local ok, cf = pcall(function() return build:GetPivot() end)
				if ok then gardenPos = cf.Position end
			end
		end
		if not islandPos then
			for _, m in ipairs(Workspace:GetChildren()) do
				if m:IsA("Model") and m.Name:match("^Island_1_") then
					local ok, cf = pcall(function() return m:GetPivot() end)
					if ok then islandPos = cf.Position end
					break
				end
			end
		end
		if gardenPos and islandPos then break end
		task.wait(0.5)
	end
	print(("[Wildlife] garden=%s island=%s"):format(tostring(gardenPos ~= nil), tostring(islandPos ~= nil)))
end)

-- ============================================================================================================
-- ISLAND BIRDSONG: a looping ambience heard ANYWHERE on Bean Farm, fading out only once you leave it.
-- ============================================================================================================
-- It started life as a garden-only sound (full inside the garden, silent 240 studs out). It now covers the
-- whole island at one steady level, because that is what birds on an island actually sound like -- you don't
-- walk out of the birdsong when you leave the flowerbeds, and the six birds circling overhead are everywhere.
--
-- STILL POSITIONAL, not a proximity check. The Sound lives on an invisible part parked over the island's
-- centre, so Roblox itself does the distance falloff every frame on the audio thread: flat at MIN_DIST (a
-- radius big enough to swallow the island whole), then fading to nothing by MAX_DIST as you fly away or
-- climb. No Heartbeat work, no "am I close enough" polling, and no hard cut at a boundary line -- which is
-- what a scripted enter/leave check always ends up sounding like.
--
-- CENTRED ON THE ISLAND, NOT THE GARDEN: the garden sits off to one side, so a falloff centred there is
-- lopsided -- quieter on the far side of the island than the near. X/Z come from the island, but Y comes
-- from the GARDEN, because the island model's pivot is ~90 studs below the surface you stand on (the same
-- trap the island birds fell into) and a sound buried under the island is 90 studs of distance away for free.
--
-- CLIENT-SIDE for the same reason the critters are: it's ambience, every player hears their own, and a server
-- Sound would have to fight StreamingEnabled to exist for a player who is nowhere near the island yet.
--
-- It deliberately has NO SoundGroup: SettingsMenu's SFX toggle adopts every ungrouped Sound under Workspace,
-- so this obeys the Sound Effects switch like everything else.
do
	local BIRD_SOUND = "rbxassetid://9119383479"
	local MIN_DIST   = 280  -- flat, full volume within this -- comfortably the whole island
	local MAX_DIST   = 700  -- gone by here: leaving the island or flying up out of it fades it away
	local VOLUME     = 0.45 -- the level it holds anywhere on the island

	task.spawn(function()
		while not gardenPos do task.wait(0.5) end -- the garden builds long after this script starts

		-- Island X/Z + garden Y (see the note above). islandPos may still be nil if the model never resolved;
		-- the garden is on the island either way, so it's a safe fallback.
		local function emitterPos()
			local ground = gardenPos + Vector3.new(0, 6, 0)
			if islandPos then return Vector3.new(islandPos.X, ground.Y, islandPos.Z) end
			return ground
		end

		local emitter, song
		local function build()
			if folder.Parent == nil then folder.Parent = Workspace end -- our whole folder can go with a sweep too
			emitter = part(folder, "IslandBirdsong", Vector3.new(1, 1, 1), Color3.new(1, 1, 1))
			emitter.Transparency = 1
			emitter.Position = emitterPos()
			song = Instance.new("Sound")
			song.Name = "IslandBirdsongLoop"
			song.SoundId = BIRD_SOUND
			song.Looped = true            -- on repeat, forever
			song.Volume = VOLUME
			song.RollOffMode = Enum.RollOffMode.InverseTapered -- smooth swell rather than a linear ramp
			song.RollOffMinDistance = MIN_DIST
			song.RollOffMaxDistance = MAX_DIST
			song.Parent = emitter
			song:Play()
		end
		build()
		print(("[Wildlife] island birdsong looping at vol %.2f (flat within %d studs, silent past %d)")
			:format(VOLUME, MIN_DIST, MAX_DIST))

		-- ===== RIDE THE MUSIC =====================================================================
		-- The four background tracks are not mastered to the same level -- some are noticeably louder than
		-- others -- so ONE fixed birdsong volume is either buried under the loud tracks or sitting on top of
		-- the quiet ones. This measures how loud the music ACTUALLY is right now and moves the birdsong with
		-- it, so it keeps the same relationship to the music whichever track is playing.
		--
		-- It reads Sound.PlaybackLoudness, not Sound.Volume. Every track plays at the same configured Volume
		-- (MusicClient sets each voice to gain 1 and never varies it) -- the difference is in the ASSETS
		-- themselves, which only a real-time loudness read can see. Loudness is per-frame jittery, so it's
		-- smoothed with a running average and the volume is eased toward the target rather than snapped, or
		-- the birdsong would pump on every drum hit.
		--
		-- MUSIC OFF is not "music at zero" -- when the player mutes music (or an event ducks it), the birds
		-- go back to their normal standalone volume rather than dropping to the quiet-track floor.
		task.spawn(function()
			local REF_LOUD = 120     -- a "normal" music loudness; at this the birds sit at exactly VOLUME
			local MIN_VOL, MAX_VOL = VOLUME * 0.62, VOLUME * 1.55
			local smoothLoud, applied = 0, VOLUME
			while true do
				task.wait(0.25)
				if song and song.Parent then
					-- Loudest currently-playing music voice. They live in the BackgroundMusic group, which is
					-- also what MusicDucking mutes -- so a muted group reads as silence and we fall back.
					local loud, groupVol = 0, 1
					for _, s in ipairs(SoundService:GetDescendants()) do
						if s:IsA("Sound") and s.IsPlaying and s.SoundGroup and s.SoundGroup.Name == "BackgroundMusic" then
							loud = math.max(loud, s.PlaybackLoudness)
							groupVol = s.SoundGroup.Volume
						end
					end
					smoothLoud = smoothLoud + (loud - smoothLoud) * 0.35
					local target
					if smoothLoud < 5 or groupVol <= 0.01 or _G.musicEnabled == false then
						target = VOLUME                                  -- no music to balance against
					else
						-- ^0.6 rather than a straight ratio: loudness differences between tracks should nudge
						-- the birds, not track them 1:1 (that would make a loud track shout the birds over it).
						target = math.clamp(VOLUME * (smoothLoud / REF_LOUD) ^ 0.6, MIN_VOL, MAX_VOL)
					end
					applied = applied + (target - applied) * 0.25         -- ease, never snap
					song.Volume = applied
				end
			end
		end)

		-- KEEP IT ALIVE. A garden stage-rebuild, a world reset or anything else sweeping Workspace can take our
		-- emitter with it, and a one-shot :Play() that got stopped leaves the garden silent for the rest of the
		-- session with nothing in the log to say so. Re-park it on the garden centre (the pivot settles as the
		-- build finishes), rebuild it if it's gone, and restart the loop if something stopped it.
		while true do
			task.wait(3)
			if not (emitter and emitter.Parent) then
				warn("[Wildlife] garden birdsong emitter was removed -- rebuilding it")
				build()
			else
				if gardenPos then emitter.Position = gardenPos + Vector3.new(0, 6, 0) end
				if song and not song.IsPlaying then song:Play() end
			end
		end
	end)
end

-- ===== SPAWN =====
-- Each critter gets its OWN random speed, radius, height and phase. Give them shared values and they move as a
-- flock of clones, which is instantly readable as fake -- the irregularity IS the realism.
local WING_COLORS = {
	{ Color3.fromRGB(255, 170, 60),  Color3.fromRGB(255, 140, 40)  }, -- monarch
	{ Color3.fromRGB(120, 190, 255), Color3.fromRGB(90, 160, 240)  }, -- blue
	{ Color3.fromRGB(255, 245, 250), Color3.fromRGB(240, 225, 240) }, -- white
	{ Color3.fromRGB(255, 210, 90),  Color3.fromRGB(250, 180, 70)  }, -- yellow
}

local critters = {}
for i = 1, BUTTERFLIES do
	local c = WING_COLORS[((i - 1) % #WING_COLORS) + 1]
	local b = buildButterfly(c[1], c[2])
	b.kind    = "butterfly"
	b.radius  = rng:NextNumber(8, GARDEN_R)
	b.speed   = rng:NextNumber(0.16, 0.34)        -- lazy
	b.height  = rng:NextNumber(FLY_LOW, FLY_HIGH)
	b.bobAmp  = rng:NextNumber(0.8, 2.2)          -- butterflies do not fly straight; they bob a lot
	b.bobFreq = rng:NextNumber(1.4, 2.6)
	b.flap    = rng:NextNumber(7, 11)
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
for _ = 1, BEES do
	local b = buildBee()
	b.kind    = "bee"
	b.radius  = rng:NextNumber(5, 22)             -- bees stay tighter to the flowers
	b.speed   = rng:NextNumber(0.5, 0.9)          -- and are much busier
	b.height  = rng:NextNumber(2, 6)
	b.bobAmp  = rng:NextNumber(0.3, 0.8)
	b.bobFreq = rng:NextNumber(3, 5)
	b.flap    = rng:NextNumber(28, 40)            -- a blur, as it should be
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
for _ = 1, BIRDS do
	local b = buildBird()
	b.kind    = "bird"
	b.radius  = rng:NextNumber(BIRD_R * 0.6, BIRD_R)
	b.speed   = rng:NextNumber(0.10, 0.18)        -- slow, wide, unhurried circles
	b.height  = rng:NextNumber(BIRD_H * 0.7, BIRD_H * 1.4)
	b.bobAmp  = rng:NextNumber(1.5, 4)
	b.bobFreq = rng:NextNumber(0.3, 0.7)
	b.flap    = rng:NextNumber(2, 3.5)            -- birds glide; the flap is occasional, not constant
	b.phase   = rng:NextNumber(0, math.pi * 2)
	critters[#critters + 1] = b
end
print(("[Wildlife] %d butterflies, %d bees, %d birds"):format(BUTTERFLIES, BEES, BIRDS))

-- ===== FLY =====
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	local me = hrp and hrp.Position

	for _, c in ipairs(critters) do
		local centre = (c.kind == "bird") and islandPos or gardenPos
		if centre and c.model.Parent then
			-- CULL: freeze anything the player is nowhere near. This is what makes 21 animated critters free.
			if me and (centre - me).Magnitude > DRAW_DIST + c.radius then
				if c.body.Transparency < 1 then
					for _, p in ipairs(c.model:GetChildren()) do
						if p:IsA("BasePart") then p.Transparency = 1 end
					end
				end
			else
				if c.body.Transparency >= 1 then
					-- RESTORE FROM EACH PART'S OWN BUILD-TIME VALUE. This used to name body/wings/stripe one by
					-- one, which meant any part added to a critter afterwards was hidden by the first cull and
					-- never came back -- and the cull loop above hides EVERY part, so the omission was silent.
					-- Reading the value back off the part cannot fall out of step with what was built.
					for _, p in ipairs(c.model:GetChildren()) do
						if p:IsA("BasePart") then p.Transparency = p:GetAttribute("BaseT") or 0 end
					end
				end

				local a = t * c.speed + c.phase
				-- a wobbling circle, not a clean one -- a perfect orbit is the tell that something is on rails
				local r = c.radius * (1 + 0.18 * math.sin(a * 1.7 + c.phase))
				local pos = centre + Vector3.new(
					math.cos(a) * r,
					c.height + math.sin(t * c.bobFreq + c.phase) * c.bobAmp,
					math.sin(a) * r
				)

				-- face the way we are going (the tangent of the circle)
				local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
				local cf = CFrame.lookAt(pos, pos + tangent)
				c.body.CFrame = cf
				if c.stripe then c.stripe.CFrame = cf * CFrame.new(0, 0, 0.02) end

				-- WINGS. Butterflies and bees flap about the body's LONG axis (they beat up and down at the sides);
				-- the bird's wings sweep from a shoulder further out. Same maths, different hinge.
				local beat = math.sin(t * c.flap + c.phase)
				if c.kind == "bird" then
					local sweep = math.rad(38) * beat
					-- SWEPT BACK ~16 degrees, and the wings sweep a little FURTHER back on the downstroke (when
					-- `beat` is negative and the wing is below the body) -- a soaring bird pulls its wings in as
					-- it drives down and spreads them again on the recovery. One extra term, and it is the
					-- difference between wings that flap and wings that row.
					local yaw = math.rad(16) + math.rad(7) * math.max(0, -beat)
					c.head.CFrame = cf * CFrame.new(0, 0.06, -0.72)
					c.tail.CFrame = cf * CFrame.new(0, 0.02, 0.86)
					c.wingL.CFrame = cf * CFrame.new(-0.9, 0.1, 0.16) * CFrame.Angles(0, -yaw, sweep)
					c.wingR.CFrame = cf * CFrame.new(0.9, 0.1, 0.16) * CFrame.Angles(0, yaw, -sweep)
				else
					local open = math.rad((c.kind == "bee") and 55 or 78) * (0.35 + 0.65 * ((beat + 1) / 2))
					c.wingL.CFrame = cf * CFrame.new(-0.06, 0.16, 0) * CFrame.Angles(0, 0, open)
					c.wingR.CFrame = cf * CFrame.new(0.06, 0.16, 0) * CFrame.Angles(0, 0, -open)
				end
			end
		end
	end
end)

print("[Wildlife] ready -- butterflies + bees over the garden, birds circling Bean Farm (client-side, no replication)")
