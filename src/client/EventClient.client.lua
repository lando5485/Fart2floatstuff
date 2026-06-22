print("EVENTCLIENT STARTED")
repeat task.wait() until _G.CoreClientReady

local Players = game.Players
local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local PlayerGui = player.PlayerGui

-- ===== SPACE-JUNK HAZARD TUNABLES (easy to change) =====
local JUNK_PUSH_DOWN   = 30    -- small extra downward shove (studs/sec) on hit; the end-of-rise FALL is the main effect. Set 0 to rely on the natural fall only
local JUNK_ROCK_SIZE   = 14    -- boulder edge in studs (the rock is a JUNK_ROCK_SIZE cube, before +/-20% variation)
local JUNK_DEBRIS_SIZE = 10    -- reference scale (studs) for every OTHER debris type; their sizes are multiples of this
local JUNK_SPAWN_HEIGHT = 220  -- studs ABOVE the player each piece spawns (drops into view well before reaching them)
local JUNK_FALL_SPEED   = 55   -- downward studs/sec (slow enough to clearly see + dodge; raise for harder)
local JUNK_HOMING_CHANCE = 0.05 -- 5% of pieces AIM at the player's horizontal spot AT SPAWN, then fall straight (still dodgeable)
local JUNK_TEST_ON_ISLAND_1 = false -- junk spawns ONLY in JUNK_ZONES (islands 10+); no island-1 test spawn

-- ===== PROPELLER PLANE HAZARD TUNABLES (easy to change) =====
-- REBUILT (shooting-planes version): exactly 4 planes ROAM the island-gap airspace randomly and
-- occasionally CHASE each other. They are RANGED shooters — they never dive into the player (no
-- kamikaze; the plane body is harmless). They fire SPREAD/CLUSTER bursts (aimed + slight lead) that
-- the player dodges by maneuvering. No shooting while the player is LANDED (gated to airborne). At
-- most 2 planes shoot at once. A projectile HIT reuses the rainbow knockdown (_G.applyBeamHit) ->
-- knocked back to the most-recent island, EVERY hit, no grace.
local PLANE_COUNT = 4              -- EXACTLY 4 planes in the gap zone (was a ~24-plane swarm)
local PLANE_SIZE = 36              -- target wingspan in studs (base build is 16) — bigger = more imposing aircraft
local PLANE_SCALE = PLANE_SIZE / 16 -- derived uniform scale applied to the whole welded plane model
local PLANE_SPEED = 72             -- studs/sec cruising/roaming speed
local PLANE_TURN_RATE = 2.2        -- how fast velocity steers toward the desired heading (higher = snappier turns)
local PLANE_BANK = 0.5             -- max roll (radians) banked into a turn (visual)
local GAP_RADIUS = 175             -- horizontal radius (studs) of the roaming airspace, centered on X=0,Z=0
local GAP_VMARGIN = 90             -- studs kept clear of the band's lo/hi so planes stay inside the gap
-- Roaming wander
local WANDER_RETARGET_MIN = 2.0    -- seconds between picking a new random roam waypoint
local WANDER_RETARGET_MAX = 4.5
local WANDER_REACH_DIST = 40       -- studs: within this of the waypoint -> pick a new one (organic wandering)
-- Occasional mutual chasing (adds life)
local CHASE_CHANCE = 0.12          -- per-second chance an idle roaming plane starts chasing a peer
local CHASE_DURATION_MIN = 2.5     -- seconds a chase lasts before breaking off back to roaming
local CHASE_DURATION_MAX = 4.5
local CHASE_SPEED_MULT = 1.5       -- chasers fly a bit faster than cruise
-- Ranged spread shooting
local MAX_SHOOTERS = 2             -- HARD cap: never more than 2 planes shooting the player at once
local SHOOT_COOLDOWN_MIN = 3.5     -- seconds a plane rests between its OWN bursts (paced, not constant)
local SHOOT_COOLDOWN_MAX = 6.5
local SHOOT_RANGE = 280            -- studs: only lock on/shoot when the player is within this range
local TELEGRAPH_TIME = 0.8         -- seconds the shooter flashes / aims before firing (readable warning)
local SPREAD_COUNT = 5             -- projectiles per cluster (a fan toward the player)
local SPREAD_HALF_ANGLE = 0.26     -- radians: half-width of the fan (total spread ~2x this) — challenging-but-fair
local SPREAD_VJITTER = 6           -- studs of small random vertical scatter per projectile (cluster feel)
local LEAD_FACTOR = 0.5            -- how strongly aim leads the player's velocity (0 = aim where they ARE)
local BULLET_SPEED = 95            -- studs/sec: fast but still visibly dodgeable
local BULLET_SIZE = 1.8            -- bullet cross-section (studs) — chunky, clearly visible
local BULLET_RANGE = 360           -- studs a projectile travels before despawning
local BULLET_LIFETIME = 6          -- seconds hard-cap despawn (backup)
local BULLET_HIT_RADIUS = 5        -- studs: distance to the player that counts as a hit
local MAX_BULLETS = 90             -- perf cap on live projectiles (excess shots skipped — purely a part-count limit)

-- [BALANCE TESTING] While TRUE, no ambient/random birds spawn during flights (so they don't
-- interfere with balance testing). Set to false to re-enable birds. (Keep in sync with the matching
-- DISABLE_EVENTS in PlayerStats.server.lua, which gates the random server-wide events. The Bird
-- Nuke product is unaffected.)
local DISABLE_EVENTS = false

-- Thunderstorm screen blur. Single tunable constant; only enabled while the storm is active.
local THUNDERSTORM_BLUR = 18
local stormBlur = Instance.new("BlurEffect")
stormBlur.Name = "ThunderstormBlur"
stormBlur.Size = THUNDERSTORM_BLUR
stormBlur.Enabled = false
stormBlur.Parent = Lighting

-- Windstorm ambient loop. One reusable Looped sound: :Play() when the windstorm starts,
-- :Stop() when it ends. Single instance => never stacks; single tunable volume.
local SoundService = game:GetService("SoundService")
local WINDSTORM_VOLUME = 0.5
local windstormSound = Instance.new("Sound")
windstormSound.Name = "WindstormSound"
windstormSound.SoundId = "rbxassetid://101642229651469"
windstormSound.Looped = true
windstormSound.Volume = WINDSTORM_VOLUME
windstormSound.Parent = SoundService

-- Thunderstorm ambient. One reusable NON-looping sound: :Play() once when the thunderstorm
-- starts, :Stop() when it ends (even mid-playback). Single instance + IsPlaying guard =>
-- never stacks or replays on re-trigger. Separate from the windstorm sound above.
local THUNDERSTORM_VOLUME = 0.5
local thunderstormSound = Instance.new("Sound")
thunderstormSound.Name = "ThunderstormSound"
thunderstormSound.SoundId = "rbxassetid://97219963176654"
thunderstormSound.Looped = false
thunderstormSound.Volume = THUNDERSTORM_VOLUME
thunderstormSound.Parent = SoundService

local function mkCorner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=p; return c end
local function mkStroke(p,col,t) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=t; s.Parent=p; return s end
local function mkLabel(p,props) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; for k,v in pairs(props) do l[k]=v end; l.Parent=p; return l end
local function mkFrame(p,props) local f=Instance.new("Frame"); for k,v in pairs(props) do f[k]=v end; f.Parent=p; return f end

-- ensure no ScreenGui renders a visible background
for _, gui in ipairs(PlayerGui:GetChildren()) do
	if gui:IsA("ScreenGui") then pcall(function() gui.BackgroundTransparency=1 end) end
end

-- ===== SCREEN EDGE GLOW (left/right only — top/bottom caused full-width line artifact) =====
local glowSg=Instance.new("ScreenGui"); glowSg.Name="EventGlowGui"; glowSg.ResetOnSpawn=false; glowSg.ZIndexBehavior=Enum.ZIndexBehavior.Global; glowSg.Parent=PlayerGui
local glowLeft   = mkFrame(glowSg,{Size=UDim2.new(0,4,1,0),Position=UDim2.new(0,0,0,0),   BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Visible=false,ZIndex=15})
local glowRight  = mkFrame(glowSg,{Size=UDim2.new(0,4,1,0),Position=UDim2.new(1,-4,0,0), BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Visible=false,ZIndex=15})
local glowEdges  = {glowLeft,glowRight}

-- ===== COUNTDOWN PILL (top-middle) =====
-- Horizontally centered, just below the top edge. Y=80 keeps it clear of the top-center announcement
-- banner (which slides to Y=10, ~65px tall -> ends ~Y=75) so they never stack, and the coin counter is
-- top-RIGHT so there is no conflict there either. Size/style/text/show-hide timing are unchanged.
local countSg=Instance.new("ScreenGui"); countSg.Name="EventCountGui"; countSg.ResetOnSpawn=false; countSg.ZIndexBehavior=Enum.ZIndexBehavior.Global; countSg.Parent=PlayerGui
local countPill=mkFrame(countSg,{Size=UDim2.new(0,280,0,44),Position=UDim2.new(0.5,0,0,80),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(180,60,220),Visible=false,ZIndex=14,BorderSizePixel=0})
mkCorner(countPill,20); mkStroke(countPill,Color3.fromRGB(120,20,160),3)
local countLabel=mkLabel(countPill,{Text="",Font=Enum.Font.FredokaOne,TextScaled=true,TextColor3=Color3.fromRGB(255,255,255),Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0,5,0,0),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=15})
mkStroke(countLabel,Color3.fromRGB(0,0,0),2)

-- ===== LARGE EVENT BANNER (top-left, slides in) =====
local eventBannerSg=Instance.new("ScreenGui"); eventBannerSg.Name="EventBannerGui"; eventBannerSg.ResetOnSpawn=false; eventBannerSg.ZIndexBehavior=Enum.ZIndexBehavior.Global; eventBannerSg.Parent=PlayerGui
local eventBanner=mkFrame(eventBannerSg,{Size=UDim2.new(0,500,0,65),Position=UDim2.new(0.5,0,0,-100),AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(100,200,255),Visible=false,ZIndex=8,BorderSizePixel=0})
mkCorner(eventBanner,16); mkStroke(eventBanner,Color3.new(1,1,1),3)
local eventBannerTitle=mkLabel(eventBanner,{Text="SERVER EVENT!",Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,30),Position=UDim2.new(0,5,0,5),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=9}); mkStroke(eventBannerTitle,Color3.new(0,0,0),1.5)
local eventBannerDesc=mkLabel(eventBanner,{Text="",Font=Enum.Font.Gotham,TextSize=14,TextColor3=Color3.new(1,1,1),Size=UDim2.new(1,-10,0,40),Position=UDim2.new(0,5,0,36),TextXAlignment=Enum.TextXAlignment.Center,TextWrapped=true,ZIndex=9}); mkStroke(eventBannerDesc,Color3.new(0,0,0),1.5)

-- ===== FLASH + STORM OVERLAYS =====
local flashSg=Instance.new("ScreenGui"); flashSg.Name="EventFlashGui"; flashSg.ResetOnSpawn=false; flashSg.ZIndexBehavior=Enum.ZIndexBehavior.Global; flashSg.Parent=PlayerGui
local flashFrame=mkFrame(flashSg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ZIndex=20,BorderSizePixel=0})

local stormSg=Instance.new("ScreenGui"); stormSg.Name="StormGui"; stormSg.ResetOnSpawn=false; stormSg.ZIndexBehavior=Enum.ZIndexBehavior.Global; stormSg.IgnoreGuiInset=true; stormSg.Parent=PlayerGui
local darkOverlay=mkFrame(stormSg,{Size=UDim2.new(1,0,1,0),Position=UDim2.new(0,0,0,0),AnchorPoint=Vector2.new(0,0),BackgroundColor3=Color3.fromRGB(10,10,30),BackgroundTransparency=1,ZIndex=8,Visible=false,BorderSizePixel=0})
local lightningFlash=mkFrame(stormSg,{Size=UDim2.new(1,0,1,0),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=1,ZIndex=6,BorderSizePixel=0})

-- ===== SOUNDS =====
local thunderSound=Instance.new("Sound"); thunderSound.Name="ThunderSound"; thunderSound.SoundId="rbxassetid://1369158752"; thunderSound.Volume=0.8; thunderSound.Parent=workspace
local screechSound=Instance.new("Sound"); screechSound.Name="ScreechSound"; screechSound.SoundId="rbxassetid://3240498563"; screechSound.Volume=1; screechSound.Parent=workspace

-- ===== BIRD SYSTEM =====
local function createBird()
	if #_G.activeBirds>=6 then return end
	local char=player.Character; local hrpTarget=char and char:FindFirstChild("HumanoidRootPart"); if not hrpTarget then return end
	local angle=math.random()*math.pi*2
	local spawnPos=hrpTarget.Position+Vector3.new(math.cos(angle)*50,0,math.sin(angle)*50)
	local birdModel=Instance.new("Model"); birdModel.Name="AggressiveBird"; birdModel.Parent=workspace
	local body=Instance.new("Part"); body.Name="Body"; body.Size=Vector3.new(3,1,1.5)
	body.Color=Color3.fromRGB(50,50,50); body.Material=Enum.Material.SmoothPlastic; body.CanCollide=false; body.Anchored=false; body.Position=spawnPos; body.Parent=birdModel
	birdModel.PrimaryPart=body
	local birdVel=Instance.new("BodyVelocity"); birdVel.MaxForce=Vector3.new(1e6,1e6,1e6); birdVel.Velocity=Vector3.new(0,0,0); birdVel.Parent=body
	local function makeWing(name,ox)
		local w=Instance.new("Part"); w.Name=name; w.Size=Vector3.new(3,0.2,0.8)
		w.Color=Color3.fromRGB(50,50,50); w.Material=Enum.Material.SmoothPlastic; w.CanCollide=false; w.Parent=birdModel
		local weld=Instance.new("Weld"); weld.Part0=body; weld.Part1=w; weld.C0=CFrame.new(ox,0,0); weld.Parent=body
		return weld
	end
	local weld1=makeWing("Wing1",-2.5); local weld2=makeWing("Wing2",2.5)
	local function makeEye(name,ox)
		local e=Instance.new("Part"); e.Name=name; e.Shape=Enum.PartType.Ball; e.Size=Vector3.new(0.35,0.35,0.35)
		e.Color=Color3.fromRGB(255,0,0); e.Material=Enum.Material.Neon; e.CanCollide=false; e.Parent=birdModel
		local ew=Instance.new("Weld"); ew.Part0=body; ew.Part1=e; ew.C0=CFrame.new(ox,0.3,0.6); ew.Parent=body
	end
	makeEye("Eye1",-0.4); makeEye("Eye2",0.4)
	_G.birdSpawnedThisFlight = true -- [BALANCE LOGGING] flag-only: a bird spawned during this flight (read by CoreClient FLIGHT DEBUG)
	local entry={model=birdModel,body=body}
	table.insert(_G.activeBirds,entry)
	task.delay(15,function() pcall(function() if birdModel.Parent then birdModel:Destroy() end end) end)
	task.spawn(function()
		local flapUp=true
		while birdModel.Parent do
			local a=flapUp and 0.6 or -0.4
			pcall(function() weld1.C0=CFrame.new(-2.5,0,0)*CFrame.Angles(0,0,a) end)
			pcall(function() weld2.C0=CFrame.new(2.5,0,0)*CFrame.Angles(0,0,-a) end)
			flapUp=not flapUp; task.wait(0.25)
		end
	end)
	task.spawn(function()
		while birdModel.Parent do
			local c=player.Character; local hrpNow=c and c:FindFirstChild("HumanoidRootPart")
			if not hrpNow then birdModel:Destroy(); break end
			local diff=hrpNow.Position-body.Position
			if diff.Magnitude<6 then
				birdModel:Destroy()
				_G.birdHitThisFlight = true -- [BALANCE LOGGING] flag-only: a bird hit the player this flight (read by CoreClient FLIGHT DEBUG)
				-- BIRD HAZARD HIT = ONLY DRAIN 20% of the player's CURRENT gas. NO kill, NO knockdown, NO teleport/
				-- respawn -- the player keeps flying with less gas. _G.applyBirdHalve (CoreClient) drains 20% of
				-- gasMeter (and keeps currentPower in sync) and enforces the brief hit cooldown so multiple
				-- birds can't drain you to nothing in one pass; it returns false when the hit is within that
				-- cooldown window, so we skip the feedback for ignored hits.
				local applied = _G.applyBirdHalve and _G.applyBirdHalve()
				if applied then
					pcall(function() screechSound:Play() end)
					if _G.showFloatingText then _G.showFloatingText("\xF0\x9F\x90\xA6 BIRD ATTACK! Gas drained!",Color3.fromRGB(255,80,0)) end
					pcall(function()
						local eff=_G.effectFlashFrame
						if eff then eff.BackgroundColor3=Color3.fromRGB(255,80,0); eff.BackgroundTransparency=0.6; TweenService:Create(eff,TweenInfo.new(0.2),{BackgroundTransparency=0.97}):Play() end
					end)
				end
				break
			elseif diff.Magnitude>150 then birdModel:Destroy(); break
			else
				-- Chase a BIT faster than the player's CURRENT speed so the bird can actually catch a
				-- rising player. Flight ascent speed varies by gut (~40-280), so a flat speed (was 60)
				-- couldn't catch bigger guts. +20 over the player's live speed = a fair-but-threatening
				-- margin; floored at 70 so it's never sluggish closing the initial gap.
				local pSpeed = hrpNow.AssemblyLinearVelocity.Magnitude
				pcall(function() birdVel.Velocity=diff.Unit*math.max(70, pSpeed + 20) end)
			end
			task.wait(0.05)
		end
		for i=#_G.activeBirds,1,-1 do if _G.activeBirds[i].model==birdModel then table.remove(_G.activeBirds,i); break end end
	end)
end

local function playBirdSound()
	local sound=Instance.new("Sound"); sound.SoundId="rbxassetid://121387867149574"
	sound.Volume=0.8; sound.Parent=workspace; sound:Play()
	game:GetService("Debris"):AddItem(sound,4)
end

-- ===== BIRD SPAWN — ONE FLAT ROLL PER FLIGHT =====
-- Roll ONCE at the start of each flight: ~1/15 (6.67%) chance that flight gets a bird. This is a flat
-- per-flight chance, independent of how long the flight lasts. If the flight rolled a bird, it spawns as
-- soon as the player is airborne — at ANY height, so the bird hazard attacks across the FULL climb
-- (islands 1 through 14, all heights). Single tunable constant.
local BIRD_CHANCE_PER_FLIGHT = 1/15
task.spawn(function()
	if DISABLE_EVENTS then print("BIRDS DISABLED (DISABLE_EVENTS) — no ambient birds will spawn") return end
	local wasFlying = false
	local birdThisFlight = false
	local spawnedThisFlight = false
	while true do
		task.wait(0.25)
		local flyingNow = _G.isFlying and true or false
		if flyingNow and not wasFlying then
			-- New flight started: roll ONCE for whether a bird appears this flight.
			birdThisFlight = (math.random() < BIRD_CHANCE_PER_FLIGHT)
			spawnedThisFlight = false
		elseif not flyingNow and wasFlying then
			birdThisFlight = false; spawnedThisFlight = false -- flight ended; reset for next time
		end
		if flyingNow and birdThisFlight and not spawnedThisFlight then
			local char=player.Character
			local hrp=char and char:FindFirstChild("HumanoidRootPart")
			if hrp then -- ANY height: birds now attack across all islands (1-14), no Y >= 600 gate
				spawnedThisFlight = true
				playBirdSound()
				createBird()
			end
		end
		wasFlying = flyingNow
	end
end)

-- ===== SPACE-JUNK HAZARD =====
-- Assorted falling debris (tires / car doors / rocks) that drops from ABOVE the flying player, ONLY in
-- the air gaps above island 6 (the 6->14 climb). Dodgeable medium trickle. On hit: END THE CURRENT RISE
-- (player falls under gravity, same as running out of power) with the fart meter FULLY PRESERVED — no
-- drain — plus an optional small downward shove (via _G.applyJunkHit in CoreClient). Each piece despawns
-- after falling past the player or JUNK_LIFETIME (so it never piles up — capped for mobile). Independent
-- of DISABLE_EVENTS.
-- ACTIVE SPAWN RANGE: junk ONLY falls on ISLANDS 10 AND UP (island 10 through island 14) — the upper
-- sky. Nowhere below island 10. Island 10 Y=11978, island 14 Y=24017 (hi has headroom above 14).
local JUNK_ZONES = {
	{lo = 11978, hi = 24500},  -- islands 10 -> 14 (and just above 14)
}
local function inJunkZone(y)
	for _, z in ipairs(JUNK_ZONES) do
		if y >= z.lo and y <= z.hi then return true end
	end
	return false
end
local JUNK_SPAWN_INTERVAL = 0.7   -- seconds between spawns (FASTER than before -> denser upper-sky debris)
local JUNK_LIFETIME       = 6     -- seconds before auto-despawn (>= 220/55 fall time so it reaches the player from the higher spawn)
local JUNK_MAX_ACTIVE     = 16    -- cap concurrent debris (raised for the denser upper sky; still mobile-safe)
local activeJunk = {}
-- Each debris type is built as ONE Model (2-5 parts welded to a PrimaryPart) so it falls/hits/despawns
-- as a single rigid unit. Sizes derive from the tunables (rock from JUNK_ROCK_SIZE, the rest from
-- JUNK_DEBRIS_SIZE), each spawn gets +/-20% variation, and the HIT RADIUS = half the type's largest
-- nominal dimension (scaled by the variation) so big junk hits at its visual edge — no phantom hits,
-- no pass-throughs. WeldConstraints hold the parts firmly together (no mid-air break-up).
local function jPart(model, sz, col, mat, shape, transp)
	local p = Instance.new("Part")
	p.Size = sz; p.Color = col; p.Material = mat
	p.CanCollide = false; p.CastShadow = false; p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	if transp then p.Transparency = transp end
	if shape then pcall(function() p.Shape = shape end) end
	p.Parent = model
	return p
end
local function jWeld(body, p) local w = Instance.new("WeldConstraint"); w.Part0 = body; w.Part1 = p; w.Parent = body end

local function buildJunk()
	local v = 0.8 + math.random() * 0.4          -- +/-20% size variation (whole piece)
	local D, R = JUNK_DEBRIS_SIZE, JUNK_ROCK_SIZE
	local model = Instance.new("Model"); model.Name = "SpaceJunk"
	local body, nominalMax
	local pick = math.random(8)
	if pick == 1 then            -- ROCK (7 parts): a craggy asteroid of clustered rough chunks
		body = jPart(model, Vector3.new(R*0.7, R*0.64, R*0.68)*v, Color3.fromRGB(96,88,76), Enum.Material.Slate, Enum.PartType.Block)
		body.CFrame = CFrame.Angles(math.random()*6, math.random()*6, math.random()*6)
		for _=1,6 do
			local cs = R*(0.3+math.random()*0.4)*v
			local c = jPart(model, Vector3.new(cs, cs*(0.7+math.random()*0.5), cs*(0.7+math.random()*0.5)), Color3.fromRGB(80+math.random(0,28),74+math.random(0,24),64+math.random(0,20)), Enum.Material.Slate, Enum.PartType.Block)
			c.CFrame = body.CFrame * CFrame.new((math.random()-0.5)*R*v*0.7,(math.random()-0.5)*R*v*0.7,(math.random()-0.5)*R*v*0.7) * CFrame.Angles(math.random()*6,math.random()*6,math.random()*6)
			jWeld(body, c)
		end
		nominalMax = R*v
	elseif pick == 2 then        -- TIRE (7 parts): treaded tire + metal rim/hub + 4 bolts
		body = jPart(model, Vector3.new(D*0.34, D, D)*v, Color3.fromRGB(28,28,30), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		body.CFrame = CFrame.new()
		local tread = jPart(model, Vector3.new(D*0.4, D*1.04, D*1.04)*v, Color3.fromRGB(18,18,20), Enum.Material.Slate, Enum.PartType.Cylinder)
		tread.CFrame = body.CFrame; jWeld(body, tread)
		local hub = jPart(model, Vector3.new(D*0.44, D*0.5, D*0.5)*v, Color3.fromRGB(150,150,160), Enum.Material.Metal, Enum.PartType.Cylinder)
		hub.CFrame = body.CFrame; jWeld(body, hub)
		for b=0,3 do
			local ang = b*math.pi/2
			local bolt = jPart(model, Vector3.new(D*0.12, D*0.1, D*0.1)*v, Color3.fromRGB(90,90,95), Enum.Material.Metal, Enum.PartType.Cylinder)
			bolt.CFrame = body.CFrame * CFrame.new(D*0.2*v, math.cos(ang)*D*0.22*v, math.sin(ang)*D*0.22*v); jWeld(body, bolt)
		end
		nominalMax = D*v
	elseif pick == 3 then        -- CAR DOOR (6 parts): painted panel + framed window + handle + side mirror
		body = jPart(model, Vector3.new(D*0.8, D*1.2, D*0.1)*v, Color3.fromRGB(150,45,45), Enum.Material.Metal, Enum.PartType.Block)
		body.CFrame = CFrame.new()
		local frame = jPart(model, Vector3.new(D*0.62, D*0.48, D*0.08)*v, Color3.fromRGB(40,40,45), Enum.Material.Metal, Enum.PartType.Block)
		frame.CFrame = body.CFrame * CFrame.new(0, D*0.32*v, D*0.04*v); jWeld(body, frame)
		local win = jPart(model, Vector3.new(D*0.54, D*0.4, D*0.06)*v, Color3.fromRGB(150,180,205), Enum.Material.Glass, Enum.PartType.Block, 0.4)
		win.CFrame = body.CFrame * CFrame.new(0, D*0.32*v, D*0.07*v); jWeld(body, win)
		local handle = jPart(model, Vector3.new(D*0.28, D*0.08, D*0.12)*v, Color3.fromRGB(215,215,220), Enum.Material.Metal, Enum.PartType.Block)
		handle.CFrame = body.CFrame * CFrame.new(-D*0.14*v, -D*0.06*v, D*0.1*v); jWeld(body, handle)
		local marm = jPart(model, Vector3.new(D*0.06, D*0.12, D*0.1)*v, Color3.fromRGB(150,45,45), Enum.Material.Metal, Enum.PartType.Block)
		marm.CFrame = body.CFrame * CFrame.new(D*0.42*v, D*0.42*v, D*0.05*v); jWeld(body, marm)
		local mirror = jPart(model, Vector3.new(D*0.16, D*0.18, D*0.05)*v, Color3.fromRGB(120,150,180), Enum.Material.Glass, Enum.PartType.Block, 0.3)
		mirror.CFrame = body.CFrame * CFrame.new(D*0.5*v, D*0.42*v, D*0.05*v); jWeld(body, mirror)
		nominalMax = D*1.2*v
	elseif pick == 4 then        -- SATELLITE (8 parts): body + 2 gridded solar wings + dish + 2 antenna rods
		body = jPart(model, Vector3.new(D*1.1, D*0.6, D*0.6)*v, Color3.fromRGB(185,190,210), Enum.Material.Metal, Enum.PartType.Block)
		body.CFrame = CFrame.new()
		for s=-1,1,2 do
			local wing = jPart(model, Vector3.new(D*0.7, D*0.5, D*0.05)*v, Color3.fromRGB(35,55,120), Enum.Material.SmoothPlastic, Enum.PartType.Block)
			wing.CFrame = body.CFrame * CFrame.new(s*D*0.9*v, 0, 0); jWeld(body, wing)
			local grid = jPart(model, Vector3.new(D*0.72, D*0.5, D*0.02)*v, Color3.fromRGB(120,140,200), Enum.Material.SmoothPlastic, Enum.PartType.Block)
			grid.CFrame = wing.CFrame * CFrame.new(0, 0, D*0.04*v); jWeld(body, grid)
		end
		local dish = jPart(model, Vector3.new(D*0.12, D*0.42, D*0.42)*v, Color3.fromRGB(225,225,230), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		dish.CFrame = body.CFrame * CFrame.new(0, D*0.46*v, 0); jWeld(body, dish)
		local antA = jPart(model, Vector3.new(D*0.03, D*0.6, D*0.03)*v, Color3.fromRGB(200,200,205), Enum.Material.Metal, Enum.PartType.Block)
		antA.CFrame = body.CFrame * CFrame.new(D*0.3*v, D*0.45*v, D*0.2*v); jWeld(body, antA)
		local antB = jPart(model, Vector3.new(D*0.03, D*0.45, D*0.03)*v, Color3.fromRGB(200,200,205), Enum.Material.Metal, Enum.PartType.Block)
		antB.CFrame = body.CFrame * CFrame.new(-D*0.3*v, D*0.4*v, -D*0.2*v); jWeld(body, antB)
		nominalMax = D*1.1*v
	elseif pick == 5 then        -- OIL DRUM (6 parts): ribbed rusty cylinder + top/bottom rims + bung cap
		body = jPart(model, Vector3.new(D*0.9, D*0.6, D*0.6)*v, Color3.fromRGB(120,72,46), Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
		body.CFrame = CFrame.new()
		for s=-1,1,2 do
			local rim = jPart(model, Vector3.new(D*0.06, D*0.66, D*0.66)*v, Color3.fromRGB(82,50,32), Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
			rim.CFrame = body.CFrame * CFrame.new(s*D*0.42*v, 0, 0); jWeld(body, rim)
		end
		for _,rx in ipairs({-0.18, 0.18}) do
			local rib = jPart(model, Vector3.new(D*0.05, D*0.63, D*0.63)*v, Color3.fromRGB(100,62,40), Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
			rib.CFrame = body.CFrame * CFrame.new(rx*D*v, 0, 0); jWeld(body, rib)
		end
		local bung = jPart(model, Vector3.new(D*0.1, D*0.14, D*0.14)*v, Color3.fromRGB(70,44,28), Enum.Material.Metal, Enum.PartType.Cylinder)
		bung.CFrame = body.CFrame * CFrame.new(D*0.45*v, D*0.18*v, 0); jWeld(body, bung)
		nominalMax = D*0.9*v
	elseif pick == 6 then        -- OLD TV (7 parts): worn casing + recessed screen + 2 antennae + 2 knobs
		body = jPart(model, Vector3.new(D*0.7, D*0.7, D*0.7)*v, Color3.fromRGB(66,60,50), Enum.Material.Plastic, Enum.PartType.Block)
		body.CFrame = CFrame.new()
		local bezel = jPart(model, Vector3.new(D*0.6, D*0.56, D*0.04)*v, Color3.fromRGB(45,42,36), Enum.Material.Plastic, Enum.PartType.Block)
		bezel.CFrame = body.CFrame * CFrame.new(-D*0.06*v, D*0.04*v, D*0.34*v); jWeld(body, bezel)
		local screen = jPart(model, Vector3.new(D*0.48, D*0.44, D*0.05)*v, Color3.fromRGB(28,30,40), Enum.Material.Glass, Enum.PartType.Block, 0.15)
		screen.CFrame = body.CFrame * CFrame.new(-D*0.06*v, D*0.04*v, D*0.37*v); jWeld(body, screen)
		for s=-1,1,2 do
			local ant = jPart(model, Vector3.new(D*0.035, D*0.5, D*0.035)*v, Color3.fromRGB(185,185,190), Enum.Material.Metal, Enum.PartType.Block)
			ant.CFrame = body.CFrame * CFrame.new(s*D*0.16*v, D*0.5*v, 0) * CFrame.Angles(0,0,s*0.35); jWeld(body, ant)
		end
		for kk=0,1 do
			local knob = jPart(model, Vector3.new(D*0.08, D*0.08, D*0.08)*v, Color3.fromRGB(30,28,24), Enum.Material.Plastic, Enum.PartType.Cylinder)
			knob.CFrame = body.CFrame * CFrame.new(D*0.26*v, D*0.18*v - kk*D*0.2*v, D*0.36*v); jWeld(body, knob)
		end
		nominalMax = D*0.7*v
	elseif pick == 7 then        -- ROCKET BOOSTER (9 parts): tall body + nozzle + nose + 2 bands + 4 fins
		body = jPart(model, Vector3.new(D*1.8, D*0.9, D*0.9)*v, Color3.fromRGB(180,180,185), Enum.Material.Metal, Enum.PartType.Cylinder)
		body.CFrame = CFrame.new()
		local nozzle = jPart(model, Vector3.new(D*0.4, D*1.05, D*1.05)*v, Color3.fromRGB(40,38,36), Enum.Material.Metal, Enum.PartType.Cylinder)
		nozzle.CFrame = body.CFrame * CFrame.new(-D*1.0*v, 0, 0); jWeld(body, nozzle)
		local nose = jPart(model, Vector3.new(D*0.45, D*0.7, D*0.7)*v, Color3.fromRGB(200,80,70), Enum.Material.Metal, Enum.PartType.Cylinder)
		nose.CFrame = body.CFrame * CFrame.new(D*1.0*v, 0, 0); jWeld(body, nose)
		for _,bx in ipairs({-0.4, 0.4}) do
			local band = jPart(model, Vector3.new(D*0.12, D*0.98, D*0.98)*v, Color3.fromRGB(120,120,125), Enum.Material.Metal, Enum.PartType.Cylinder)
			band.CFrame = body.CFrame * CFrame.new(bx*D*v, 0, 0); jWeld(body, band)
		end
		for f=0,3 do
			local fin = jPart(model, Vector3.new(D*0.5, D*0.7, D*0.08)*v, Color3.fromRGB(150,60,55), Enum.Material.Metal, Enum.PartType.Block)
			fin.CFrame = body.CFrame * CFrame.new(-D*0.75*v, 0, 0) * CFrame.Angles(f*math.pi/2, 0, 0) * CFrame.new(0, D*0.6*v, 0); jWeld(body, fin)
		end
		nominalMax = D*1.8*v
	else                          -- WASHING MACHINE (9 parts): box + glass door + rim + handle + top panel + 4 feet
		body = jPart(model, Vector3.new(D*1.2, D*1.3, D*1.2)*v, Color3.fromRGB(150,120,95), Enum.Material.CorrodedMetal, Enum.PartType.Block)
		body.CFrame = CFrame.new()
		local rim = jPart(model, Vector3.new(D*0.1, D*0.95, D*0.95)*v, Color3.fromRGB(110,110,115), Enum.Material.Metal, Enum.PartType.Cylinder)
		rim.CFrame = body.CFrame * CFrame.new(0, -D*0.05*v, D*0.56*v) * CFrame.Angles(0, math.rad(90), 0); jWeld(body, rim)
		local door = jPart(model, Vector3.new(D*0.16, D*0.8, D*0.8)*v, Color3.fromRGB(30,32,42), Enum.Material.Glass, Enum.PartType.Cylinder, 0.25)
		door.CFrame = body.CFrame * CFrame.new(0, -D*0.05*v, D*0.6*v) * CFrame.Angles(0, math.rad(90), 0); jWeld(body, door)
		local panel = jPart(model, Vector3.new(D*1.1, D*0.18, D*0.5)*v, Color3.fromRGB(210,205,195), Enum.Material.Plastic, Enum.PartType.Block)
		panel.CFrame = body.CFrame * CFrame.new(0, D*0.62*v, -D*0.3*v); jWeld(body, panel)
		local handle = jPart(model, Vector3.new(D*0.08, D*0.28, D*0.1)*v, Color3.fromRGB(90,90,95), Enum.Material.Metal, Enum.PartType.Block)
		handle.CFrame = body.CFrame * CFrame.new(D*0.34*v, -D*0.05*v, D*0.62*v); jWeld(body, handle)
		for sx=-1,1,2 do for sz=-1,1,2 do
			local foot = jPart(model, Vector3.new(D*0.18, D*0.2, D*0.18)*v, Color3.fromRGB(60,60,62), Enum.Material.Metal, Enum.PartType.Block)
			foot.CFrame = body.CFrame * CFrame.new(sx*D*0.45*v, -D*0.72*v, sz*D*0.45*v); jWeld(body, foot)
		end end
		nominalMax = D*1.3*v
	end
	model.PrimaryPart = body
	return model, nominalMax / 2
end

local function createJunk()
	if #activeJunk >= JUNK_MAX_ACTIVE then return end
	local char=player.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if not (JUNK_TEST_ON_ISLAND_1 or inJunkZone(hrp.Position.Y)) then return end
	local model, hitRadius = buildJunk()
	-- HOMING: a small fraction AIM at the player's CURRENT horizontal spot, but still spawn at the SAME
	-- full JUNK_SPAWN_HEIGHT above and then fall STRAIGHT down (no continuous homing) — so the player has
	-- full reaction time and can step aside. The other 95% spawn at a random horizontal offset.
	local homing = math.random() < JUNK_HOMING_CHANCE
	local ox = homing and 0 or math.random(-22, 22)
	local oz = homing and 0 or math.random(-22, 22)
	local spawnPos = hrp.Position + Vector3.new(ox, JUNK_SPAWN_HEIGHT, oz)
	model:PivotTo(CFrame.new(spawnPos) * CFrame.Angles(math.random()*6, math.random()*6, math.random()*6))
	model.Parent = workspace
	local body = model.PrimaryPart
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(0, 1e6, 0)            -- fall straight DOWN only (no horizontal drift => dodgeable)
	bv.Velocity = Vector3.new(0, -JUNK_FALL_SPEED, 0); bv.Parent = body
	local av = Instance.new("BodyAngularVelocity")  -- slow tumble for flavor
	av.MaxTorque = Vector3.new(1e5,1e5,1e5); av.AngularVelocity = Vector3.new(math.random(-3,3),math.random(-3,3),math.random(-3,3)); av.Parent = body
	table.insert(activeJunk, model)
	local function cleanup()
		for i=#activeJunk,1,-1 do if activeJunk[i]==model then table.remove(activeJunk,i) end end
		pcall(function() if model.Parent then model:Destroy() end end)
	end
	task.delay(JUNK_LIFETIME, cleanup)
	task.spawn(function()
		while model.Parent and body and body.Parent do
			local c=player.Character; local h=c and c:FindFirstChild("HumanoidRootPart")
			if not h then break end
			if (h.Position - body.Position).Magnitude < hitRadius then
				-- LAUNCH-SNAPSHOT RULE (shared with the Rainbow Beams hazard): a junk hit UNDOES
				-- the flight -- _G.applyBeamHit() restores the meter to the LAUNCH amount and knocks
				-- the player back to the island they launched from (never higher; closest-below
				-- fallback), using the same _G.beamLaunchSnapshot the beams use. (Replaces the old
				-- "instant fall, keep current power" _G.applyJunkHit behavior for junk only.)
				if _G.applyBeamHit then _G.applyBeamHit() end
				if _G.showFloatingText then _G.showFloatingText("\xF0\x9F\x9B\xB0 JUNK HIT! Knocked back!", Color3.fromRGB(255,140,0)) end
				break
			elseif body.Position.Y < h.Position.Y - 30 then
				break -- fell past the player
			end
			task.wait(0.05)
		end
		cleanup()
	end)
end

task.spawn(function()
	while true do
		task.wait(JUNK_SPAWN_INTERVAL)
		if _G.isFlying then
			local c=player.Character; local h=c and c:FindFirstChild("HumanoidRootPart")
			-- test flag spawns anywhere (incl. island 1); otherwise ONLY inside the two junk zones (7-8, 12-13)
			if h and (JUNK_TEST_ON_ISLAND_1 or inJunkZone(h.Position.Y)) then createJunk() end
		end
	end
end)

-- ===== PROPELLER PLANE HAZARD (shooting-planes rebuild) =====
-- Exactly 4 propeller planes ROAM the island-gap airspace randomly (organic wandering, occasionally
-- chasing each other for a few seconds) and SHOOT spread-cluster bursts at the player from RANGE —
-- they NEVER dive into the player (no kamikaze; the plane body is harmless). The projectiles are the
-- danger: aimed with slight lead, fanned out, so flying straight gets hit and the player must change
-- direction to dodge. Planes only target/shoot while the player is AIRBORNE (gated on the landed
-- state); landed = they just roam. At most 2 planes shoot at once. A projectile hit reuses the
-- rainbow knockdown (_G.applyBeamHit) -> knocked back to the most-recent island, every hit, no grace.
-- Planes/bullets exist ONLY while the player is inside the plane band; cleared otherwise.
local PLANE_BANDS = { {lo=3580, hi=4820} }   -- ONLY between islands 5 and 6 (Y 3580 -> 4820)
local function planeBandFor(y)
	for _,b in ipairs(PLANE_BANDS) do
		if y >= b.lo and y <= b.hi then return b end
	end
	return nil
end

local function pPart(model, sz, col, mat, shape, transp)
	local p=Instance.new("Part")
	p.Size=sz; p.Color=col; p.Material=mat; p.Anchored=true; p.CanCollide=false; p.CastShadow=false
	p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
	if transp then p.Transparency=transp end
	if shape then pcall(function() p.Shape=shape end) end
	p.Parent=model; return p
end
local function pWeld(a,b) local w=Instance.new("WeldConstraint"); w.Part0=a; w.Part1=b; w.Parent=a end

-- One welded plane model (12 parts). Forward = local -Z (nose). Returns the model + the propeller blade
-- (kept UNwelded so it can be spun around the forward axis each frame).
local function buildPlane()
	local model=Instance.new("Model"); model.Name="HazardPlane"
	local paint=Color3.fromRGB(178,58,52)
	local metal=Color3.fromRGB(120,124,134)
	local fus=pPart(model, Vector3.new(3.6,3.6,16), paint, Enum.Material.Metal, Enum.PartType.Block)
	fus.CFrame=CFrame.new(); model.PrimaryPart=fus
	local nose=pPart(model, Vector3.new(3,3.4,3.4), metal, Enum.Material.Metal, Enum.PartType.Cylinder)
	nose.CFrame=fus.CFrame*CFrame.new(0,0,-8.5)*CFrame.Angles(0,math.rad(90),0); pWeld(fus,nose)
	local wing=pPart(model, Vector3.new(16,0.7,4.5), paint, Enum.Material.Metal, Enum.PartType.Block)
	wing.CFrame=fus.CFrame*CFrame.new(0,-0.3,-0.5); pWeld(fus,wing)
	local fin=pPart(model, Vector3.new(0.5,3.5,3), paint, Enum.Material.Metal, Enum.PartType.Block)
	fin.CFrame=fus.CFrame*CFrame.new(0,2,7); pWeld(fus,fin)
	local stab=pPart(model, Vector3.new(7,0.5,2.5), paint, Enum.Material.Metal, Enum.PartType.Block)
	stab.CFrame=fus.CFrame*CFrame.new(0,0.3,7); pWeld(fus,stab)
	local cockpit=pPart(model, Vector3.new(3,1.8,4), Color3.fromRGB(120,170,200), Enum.Material.Glass, Enum.PartType.Block, 0.35)
	cockpit.CFrame=fus.CFrame*CFrame.new(0,2.2,-1); pWeld(fus,cockpit)
	for s=-1,1,2 do
		local strut=pPart(model, Vector3.new(0.4,3,0.4), metal, Enum.Material.Metal, Enum.PartType.Block)
		strut.CFrame=fus.CFrame*CFrame.new(s*2.5,-3,-2); pWeld(fus,strut)
		local wheel=pPart(model, Vector3.new(0.6,2,2), Color3.fromRGB(25,25,28), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		wheel.CFrame=fus.CFrame*CFrame.new(s*2.5,-4.4,-2); pWeld(fus,wheel)
	end
	local hub=pPart(model, Vector3.new(1.2,1.4,1.4), metal, Enum.Material.Metal, Enum.PartType.Cylinder)
	hub.CFrame=fus.CFrame*CFrame.new(0,0,-9)*CFrame.Angles(0,math.rad(90),0); pWeld(fus,hub)
	local blade=pPart(model, Vector3.new(0.5,10,1.4), Color3.fromRGB(45,45,50), Enum.Material.SmoothPlastic, Enum.PartType.Block)
	blade.Name="Prop"; blade.CFrame=fus.CFrame*CFrame.new(0,0,-9.2)  -- NOT welded; spun each frame
	model:ScaleTo(PLANE_SCALE)  -- uniformly scale the whole plane (parts + welded offsets + blade) to PLANE_SIZE
	return model, blade
end

local planes = {}
local bullets = {}
local activeBand = nil          -- the PLANE_BANDS entry currently active (nil = player not in a band)
local shooterCount = 0          -- how many planes are CURRENTLY mid-shoot (telegraph+fire); capped at MAX_SHOOTERS
local lastAirborne = nil        -- last known airborne state (for the landed/flying transition diagnostics)

local function clearBullets()
	for _,bl in ipairs(bullets) do pcall(function() if bl.part then bl.part:Destroy() end end) end
	bullets = {}
end
local function clearPlanes()
	for _,pl in ipairs(planes) do pcall(function() pl.model:Destroy() end) end
	planes = {}; activeBand = nil; shooterCount = 0
end

-- Yaw a vector around the vertical (Y) axis by `ang` radians, PRESERVING its Y component (so aimed
-- shots that point up/down keep their vertical aim while fanning horizontally).
local function yawDir(v, ang)
	local c, s = math.cos(ang), math.sin(ang)
	return Vector3.new(v.X*c - v.Z*s, v.Y, v.X*s + v.Z*c)
end

-- A random point inside the gap airspace cylinder (radius GAP_RADIUS around X=0,Z=0, height between
-- the band's padded lo/hi). sqrt() makes the points area-uniform so they don't bunch at the centre.
local function randomGapPoint(band)
	local r = GAP_RADIUS * math.sqrt(math.random())
	local a = math.random() * 2 * math.pi
	local y = (band.lo + GAP_VMARGIN) + math.random() * ((band.hi - GAP_VMARGIN) - (band.lo + GAP_VMARGIN))
	return Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
end

local function spawnPlanes(band)
	clearPlanes(); activeBand = band
	for i=1,PLANE_COUNT do
		local model, blade = buildPlane()
		model.Parent = workspace
		local pos = randomGapPoint(band)
		model:PivotTo(CFrame.new(pos))
		planes[i] = {
			model = model, blade = blade, spin = 0,
			pos = pos,
			vel = Vector3.new((math.random()-0.5), 0, (math.random()-0.5) + 0.01).Unit * PLANE_SPEED,
			target = randomGapPoint(band),
			retargetTimer = WANDER_RETARGET_MIN + math.random() * (WANDER_RETARGET_MAX - WANDER_RETARGET_MIN),
			mode = "roam",          -- "roam" | "chase"
			chaseTarget = nil,      -- index of the plane being chased
			chaseTimer = 0,
			shootCooldown = 1.5 + math.random() * 3,  -- stagger initial shots so they don't all fire at once
			shooting = false,       -- true while this plane is mid telegraph+fire (counts toward the cap)
			highlight = nil,        -- telegraph flash highlight (created on demand)
		}
	end
	print("[Planes] spawned " .. PLANE_COUNT .. " planes in gap zone")
end

-- Fire ONE spread/cluster of projectiles from a plane at the player: SPREAD_COUNT shots fanned around
-- an aim point that LEADS the player's current velocity, so flying straight gets hit and the player
-- must change direction to thread the fan.
local function fireSpread(pl, hrp)
	if not pl.model.PrimaryPart then return end
	local origin = (pl.model:GetPivot() * CFrame.new(0,0,-9.5*PLANE_SCALE)).Position
	-- Aim point = where the player IS + a slight lead along their velocity (scaled by travel time).
	local pv = hrp.AssemblyLinearVelocity
	local dist = (hrp.Position - origin).Magnitude
	local travel = (BULLET_SPEED > 0) and (dist / BULLET_SPEED) or 0
	local aimPos = hrp.Position + pv * travel * LEAD_FACTOR
	local baseDir = (aimPos - origin)
	if baseDir.Magnitude < 1 then return end
	baseDir = baseDir.Unit
	for k=1,SPREAD_COUNT do
		if #bullets >= MAX_BULLETS then break end
		-- Evenly fan across [-SPREAD_HALF_ANGLE, +SPREAD_HALF_ANGLE].
		local frac = (SPREAD_COUNT > 1) and ((k-1)/(SPREAD_COUNT-1) - 0.5) or 0
		local dir = yawDir(baseDir, frac * 2 * SPREAD_HALF_ANGLE)
		dir = (dir + Vector3.new(0, (math.random()-0.5) * (SPREAD_VJITTER/40), 0)).Unit  -- small cluster scatter
		local b=Instance.new("Part")
		b.Name="PlaneTracer"; b.Size=Vector3.new(BULLET_SIZE,BULLET_SIZE,BULLET_SIZE*2.5); b.Color=Color3.fromRGB(255,90,60)
		b.Material=Enum.Material.Neon; b.CanCollide=false; b.Anchored=true; b.CastShadow=false
		b.CFrame=CFrame.lookAt(origin, origin+dir)
		local a0=Instance.new("Attachment"); a0.Position=Vector3.new(0,0,1.6); a0.Parent=b
		local a1=Instance.new("Attachment"); a1.Position=Vector3.new(0,0,-1.6); a1.Parent=b
		local tr=Instance.new("Trail"); tr.Attachment0=a0; tr.Attachment1=a1; tr.Lifetime=0.35
		tr.Color=ColorSequence.new(Color3.fromRGB(255,120,40)); tr.LightEmission=1
		tr.WidthScale=NumberSequence.new(1,0); tr.Parent=b
		b.Parent=workspace
		task.delay(BULLET_LIFETIME, function() pcall(function() if b.Parent then b:Destroy() end end) end)
		table.insert(bullets, {part=b, dir=dir, dist=0})
	end
end

-- Run a single shoot sequence for plane `pl` (index `idx`): telegraph (flash) -> fire the spread ->
-- re-roam + cooldown. Gated so it ABORTS if the player lands mid-telegraph. Counts toward shooterCount
-- for its whole duration so the MAX_SHOOTERS cap holds.
local function startShoot(pl, idx)
	pl.shooting = true
	shooterCount = shooterCount + 1
	print(string.format("[Planes] shooters active: %d (max %d)", shooterCount, MAX_SHOOTERS))
	task.spawn(function()
		-- Telegraph: bright outline so the burst is readable.
		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(255,60,40); hl.FillTransparency = 0.55
		hl.OutlineColor = Color3.fromRGB(255,230,120); hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		pcall(function() hl.Parent = pl.model end)
		pl.highlight = hl
		task.wait(TELEGRAPH_TIME)
		pcall(function() hl:Destroy() end); pl.highlight = nil
		-- Re-check: only fire if the player is still AIRBORNE (don't shoot someone who just landed).
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local airborne = hum and hum.FloorMaterial == Enum.Material.Air
		if hrp and airborne and pl.model and pl.model.Parent then
			fireSpread(pl, hrp)
			print(string.format("[Planes] plane %d fired spread cluster at %s (aimed/lead)", idx, player.Name))
		end
		pl.shootCooldown = SHOOT_COOLDOWN_MIN + math.random() * (SHOOT_COOLDOWN_MAX - SHOOT_COOLDOWN_MIN)
		pl.shooting = false
		shooterCount = math.max(0, shooterCount - 1)
	end)
end

RunService.Heartbeat:Connect(function(dt)
	local char=player.Character
	local hrp=char and char:FindFirstChild("HumanoidRootPart")
	local band = hrp and planeBandFor(hrp.Position.Y) or nil
	if not band then
		if #planes>0 then clearPlanes(); clearBullets() end
		lastAirborne = nil
		return
	end
	if band ~= activeBand then spawnPlanes(band) end

	-- LANDED-vs-FLYING GATE: planes only target/shoot while the player is AIRBORNE (FloorMaterial Air).
	-- Landed (standing on an island) = they just roam, no targeting/projectiles at the player.
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local airborne = (hum ~= nil) and (hum.FloorMaterial == Enum.Material.Air)
	if airborne ~= lastAirborne then
		if airborne then print("[Planes] player flying -> targeting allowed")
		else print("[Planes] player landed -> planes stop targeting") end
		lastAirborne = airborne
	end

	for idx,pl in ipairs(planes) do
		-- ---- DECIDE DESTINATION (roam waypoint, or the chased plane) ----
		pl.retargetTimer = pl.retargetTimer - dt
		if pl.mode == "chase" then
			pl.chaseTimer = pl.chaseTimer - dt
			local tgt = planes[pl.chaseTarget]
			if pl.chaseTimer <= 0 or not tgt or not tgt.model.Parent then
				pl.mode = "roam"; pl.chaseTarget = nil
				pl.target = randomGapPoint(band)
				pl.retargetTimer = WANDER_RETARGET_MIN + math.random() * (WANDER_RETARGET_MAX - WANDER_RETARGET_MIN)
				print(string.format("[Planes] plane %d roaming", idx))
			else
				pl.target = tgt.pos
			end
		else
			-- Roaming: pick a fresh waypoint on the timer or once we arrive (organic wandering).
			if pl.retargetTimer <= 0 or (pl.pos - pl.target).Magnitude < WANDER_REACH_DIST then
				pl.target = randomGapPoint(band)
				pl.retargetTimer = WANDER_RETARGET_MIN + math.random() * (WANDER_RETARGET_MAX - WANDER_RETARGET_MIN)
			end
			-- Occasionally start chasing another (currently roaming) plane for a few seconds.
			if not pl.shooting and math.random() < CHASE_CHANCE * dt and PLANE_COUNT > 1 then
				local m = 1 + math.floor(math.random() * PLANE_COUNT)
				if m ~= idx and planes[m] and planes[m].mode == "roam" then
					pl.mode = "chase"; pl.chaseTarget = m
					pl.chaseTimer = CHASE_DURATION_MIN + math.random() * (CHASE_DURATION_MAX - CHASE_DURATION_MIN)
					print(string.format("[Planes] plane %d chasing plane %d", idx, m))
				end
			end
		end

		-- ---- STEER + MOVE (smooth velocity lerp -> organic banking flight) ----
		local desired = pl.target - pl.pos
		local desiredDir = (desired.Magnitude > 1) and desired.Unit or (pl.vel.Magnitude > 0.1 and pl.vel.Unit or Vector3.new(0,0,-1))
		local speed = PLANE_SPEED * (pl.mode == "chase" and CHASE_SPEED_MULT or 1)
		local desiredVel = desiredDir * speed
		pl.vel = pl.vel:Lerp(desiredVel, math.clamp(PLANE_TURN_RATE * dt, 0, 1))
		pl.pos = pl.pos + pl.vel * dt

		-- Clamp inside the gap airspace (cylinder radius + padded vertical band); bounce the heading
		-- back inward and retarget so planes never wander off into irrelevant areas.
		local flat = Vector3.new(pl.pos.X, 0, pl.pos.Z)
		if flat.Magnitude > GAP_RADIUS then
			flat = flat.Unit * GAP_RADIUS
			pl.pos = Vector3.new(flat.X, pl.pos.Y, flat.Z)
			pl.target = randomGapPoint(band); pl.retargetTimer = 1.0
			pl.vel = Vector3.new(pl.vel.X * -0.3, pl.vel.Y, pl.vel.Z * -0.3)
		end
		local loY, hiY = band.lo + GAP_VMARGIN, band.hi - GAP_VMARGIN
		if pl.pos.Y < loY or pl.pos.Y > hiY then
			pl.pos = Vector3.new(pl.pos.X, math.clamp(pl.pos.Y, loY, hiY), pl.pos.Z)
			pl.target = randomGapPoint(band); pl.retargetTimer = 1.0
			pl.vel = Vector3.new(pl.vel.X, pl.vel.Y * -0.3, pl.vel.Z)
		end

		-- ---- ORIENT (look along velocity, bank into the horizontal turn) ----
		local look = (pl.vel.Magnitude > 0.1) and pl.vel.Unit or Vector3.new(0,0,-1)
		local flatVel = Vector3.new(pl.vel.X, 0, pl.vel.Z)
		local flatDes = Vector3.new(desiredVel.X, 0, desiredVel.Z)
		local turnSign = flatVel:Cross(flatDes).Y
		local bank = -math.clamp(turnSign / (speed * speed + 1) * 6, -1, 1) * PLANE_BANK
		local fullCF = CFrame.lookAt(pl.pos, pl.pos + look) * CFrame.Angles(0, 0, bank)
		pl.model:PivotTo(fullCF)
		pl.spin = pl.spin + dt*22
		pl.blade.CFrame = fullCF * CFrame.new(0,0,-9.2*PLANE_SCALE) * CFrame.Angles(0,0,pl.spin)

		-- ---- SHOOT (only while airborne; respect per-plane cooldown + the global 2-shooter cap) ----
		pl.shootCooldown = pl.shootCooldown - dt
		if airborne and not pl.shooting and pl.mode == "roam" and pl.shootCooldown <= 0
			and shooterCount < MAX_SHOOTERS and hrp
			and (hrp.Position - pl.pos).Magnitude <= SHOOT_RANGE then
			startShoot(pl, idx)
		end
	end

	-- ---- PROJECTILES ----
	for i=#bullets,1,-1 do
		local bl=bullets[i]
		if not bl.part or not bl.part.Parent then table.remove(bullets,i)
		else
			local step=BULLET_SPEED*dt
			bl.part.CFrame = bl.part.CFrame + bl.dir*step
			bl.dist = bl.dist + step
			if hrp and (hrp.Position - bl.part.Position).Magnitude < BULLET_HIT_RADIUS then
				-- HIT: reuse the EXACT rainbow knockdown (knock back to the most-recent island). Harsh:
				-- every hit, no grace period. _G.applyBeamHit already chooses the launch/last island.
				local snap = _G.beamLaunchSnapshot
				local nm = (snap and snap.islandIndex and _G.ISLAND_DISPLAY_NAMES and _G.ISLAND_DISPLAY_NAMES[snap.islandIndex]) or "last island"
				print(string.format("[Planes] %s HIT by projectile -> knockdown to last island %s", player.Name, nm))
				if _G.applyBeamHit then _G.applyBeamHit() elseif _G.applyJunkHit then _G.applyJunkHit(JUNK_PUSH_DOWN) end
				if _G.showFloatingText then _G.showFloatingText("\xE2\x9C\x88 SHOT DOWN! Knocked back!", Color3.fromRGB(255,120,40)) end
				bl.part:Destroy(); table.remove(bullets,i)
			elseif bl.dist > BULLET_RANGE then
				bl.part:Destroy(); table.remove(bullets,i)
			end
		end
	end
end)

-- ===== MILESTONE SYSTEM =====
local function showMilestonePills(milestones)
	for i,m in ipairs(milestones) do
		task.delay((i-1)*0.35,function()
			local mSg=Instance.new("ScreenGui"); mSg.ResetOnSpawn=false; mSg.Parent=PlayerGui
			local pill=Instance.new("Frame"); pill.Size=UDim2.new(0,280,0,42); pill.Position=UDim2.new(0.5,-140,0.45,(i-1)*52); pill.BackgroundColor3=Color3.fromRGB(40,190,40); pill.Parent=mSg
			local co=Instance.new("UICorner"); co.CornerRadius=UDim.new(0,21); co.Parent=pill
			local st=Instance.new("UIStroke"); st.Color=Color3.fromRGB(0,140,0); st.Thickness=2; st.Parent=pill
			local lbl=Instance.new("TextLabel"); lbl.Text=m; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=16; lbl.TextColor3=Color3.new(1,1,1); lbl.Size=UDim2.new(1,-10,1,0); lbl.Position=UDim2.new(0,5,0,0); lbl.BackgroundTransparency=1; lbl.TextXAlignment=Enum.TextXAlignment.Center; lbl.Parent=pill
			pill.BackgroundTransparency=1; pill.Position=UDim2.new(0.5,-140,0.42,(i-1)*52)
			TweenService:Create(pill,TweenInfo.new(0.3,Enum.EasingStyle.Back),{BackgroundTransparency=0,Position=UDim2.new(0.5,-140,0.45,(i-1)*52)}):Play()
			task.delay(2.5,function()
				TweenService:Create(pill,TweenInfo.new(0.4),{BackgroundTransparency=1}):Play()
				task.delay(0.4,function() mSg:Destroy() end)
			end)
		end)
	end
end

-- Per-flight milestone coin bonus REMOVED entirely — both the height tiers (peak >500/2000/5000)
-- and the ring-count tiers (>=3 / >=6 rings). The only normal-play coin sources are now flight
-- coins (height*0.0044 per tick) and the in-flight ring bonus (left untouched in CoreClient).
-- Stub kept so stopFlying's _G.checkMilestones() call stays safe; it grants nothing.
local function checkMilestones() end
_G.checkMilestones=checkMilestones

-- ===== EVENT HELPERS =====
local glowPulseActive=false

local function setGlowColor(col)
	for _,f in ipairs(glowEdges) do f.BackgroundColor3=col; f.Visible=true; f.BackgroundTransparency=0.2 end
end

local function hideGlow()
	glowPulseActive=false
	for _,f in ipairs(glowEdges) do f.Visible=false end
end

local function startGlowPulse(col)
	setGlowColor(col); glowPulseActive=true
	task.spawn(function()
		while glowPulseActive do
			for _,f in ipairs(glowEdges) do TweenService:Create(f,TweenInfo.new(0.5,Enum.EasingStyle.Sine),{BackgroundTransparency=0.6}):Play() end
			task.wait(0.5); if not glowPulseActive then break end
			for _,f in ipairs(glowEdges) do TweenService:Create(f,TweenInfo.new(0.5,Enum.EasingStyle.Sine),{BackgroundTransparency=0.2}):Play() end
			task.wait(0.5)
		end
		hideGlow()
	end)
end

local function screenFlash(col,transp,dur)
	flashFrame.BackgroundColor3=col; flashFrame.BackgroundTransparency=transp
	TweenService:Create(flashFrame,TweenInfo.new(dur),{BackgroundTransparency=1}):Play()
end

local function showEventBanner(dispName,msg,color)
	eventBanner.BackgroundColor3=color; eventBannerTitle.Text=tostring(dispName); eventBannerDesc.Text=tostring(msg)
	eventBanner.AnchorPoint=Vector2.new(0.5,0); eventBanner.Position=UDim2.new(0.5,0,0,-100); eventBanner.Visible=true
	TweenService:Create(eventBanner,TweenInfo.new(0.4,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,0,0,10)}):Play()
	task.delay(5,function()
		TweenService:Create(eventBanner,TweenInfo.new(0.3),{Position=UDim2.new(0.5,0,0,-100)}):Play()
		task.delay(0.35,function() eventBanner.Visible=false end)
	end)
end

local activeEventSgs={}
local function addEventSg(sg2) table.insert(activeEventSgs,sg2) end

-- ===== THUNDERSTORM SKY + WEATHER (rebuilt) -- DARK storm-cloud look while FLYING, island visible when LANDED.
-- All world/Lighting + 3D particles (no GUI overlay, so the HUD stays bright). Base Lighting is snapshotted and
-- fully restored on storm end. Lightning = a 3D Lighting spike. Wind = _G.thunderWindVec (CoreClient applies it). =====
local stormCC = nil
local savedStormLighting = nil
local stormApplied = nil            -- the active Lighting target (FLY or LAND) -- a lightning flash returns to it
local stormClouds = nil
local savedClouds = nil
local stormCloudsOurs = false
local stormAtmos = nil              -- the Atmosphere we DRIVE during the storm (an existing one, or a temp one we add)
local stormAtmosOurs = false        -- true if WE created stormAtmos (remove it on end) vs an existing one (restore its props)
local savedAtmos = nil              -- saved ORIGINAL Atmosphere props, restored on end (nil when we created a temp one)
local stormFogConn = nil            -- per-frame enforcer: HARD-PINS the dense flying fog + thick Atmosphere so nothing can override it
local stormFXFolder = nil
local stormFXConn = nil
local stormMist = nil               -- enveloping dark-cloud emitter (ON while flying, OFF while landed)
local stormRain = nil               -- heavy-rain emitter (on the whole storm)
local stormState = nil              -- true=flying / false=landed (only tween Lighting on a transition)
local STORM_WIND_FORCE = 90         -- STRONG storm wind -- buffets the player hard (steering ~48; still recoverable)
-- FLYING = FULLY ENGULFED in a dark thundercloud: dark storm gray, only a tiny immediate bubble is
-- visible -- every island and everything beyond ~FogEnd studs is swallowed by solid murk. This fog is
-- HARD-PINNED every frame by the enforcer below (an Atmosphere or any per-frame lighting setter would
-- otherwise make legacy Fog do nothing), so these values are what actually renders while flying.
local STORM_FLY = {
	ClockTime = 14, Brightness = 0.6, ExposureCompensation = -0.6,
	FogColor = Color3.fromRGB(60,60,70), FogStart = 0, FogEnd = 60,  -- ~60 studs: islands fully invisible
	OutdoorAmbient = Color3.fromRGB(45,47,55), Ambient = Color3.fromRGB(48,50,58),
}
-- LANDED = on an island: cloud eases WAY back so the island is clearly visible (stormy but visible).
local STORM_LAND = {
	ClockTime = 14, Brightness = 1.6, ExposureCompensation = -0.1,
	FogColor = Color3.fromRGB(150,156,166), FogStart = 50, FogEnd = 650,
	OutdoorAmbient = Color3.fromRGB(150,156,166), Ambient = Color3.fromRGB(150,156,166),
}
-- HARD-CULL APPROACH. An Atmosphere maxes out at Density 1.0 / Haze 10 and even then only WASHES OUT
-- distant objects (light scattering) -- it never fully occludes, so islands stayed faintly visible.
-- The only thing that produces a SOLID wall (everything beyond N studs = 100% FogColor) is classic
-- Fog -- but classic Fog is DISABLED whenever an Atmosphere exists. So while flying we REMOVE the
-- Atmosphere every frame and pin a short dense classic Fog (STORM_FLY.FogEnd ~60, dark gray) = a true
-- engulfing wall. On landed/end we re-attach the Atmosphere (saved props) so the island is visible again.
local function startStormParticles()
	if stormFXFolder then return end
	stormFXFolder = Instance.new("Folder"); stormFXFolder.Name="ThunderstormFX"; stormFXFolder.Parent=workspace
	local anchor = Instance.new("Part"); anchor.Name="StormFXAnchor"
	anchor.Size=Vector3.new(46,30,46); anchor.Transparency=1
	anchor.Anchored=true; anchor.CanCollide=false; anchor.CanQuery=false; anchor.CanTouch=false; anchor.CastShadow=false
	anchor.Parent=stormFXFolder
	local mist=Instance.new("ParticleEmitter"); mist.Name="StormMist"; mist.Texture="rbxasset://textures/particles/smoke_main.dds"
	mist.Rate=44; mist.Lifetime=NumberRange.new(2.5,4.5); mist.Speed=NumberRange.new(3,9); mist.SpreadAngle=Vector2.new(180,180)
	mist.Rotation=NumberRange.new(0,360); mist.RotSpeed=NumberRange.new(-28,28)
	mist.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,22),NumberSequenceKeypoint.new(1,44)})
	mist.Color=ColorSequence.new(Color3.fromRGB(92,96,104),Color3.fromRGB(70,74,82)) -- DARK storm gray cloud
	mist.LightEmission=0.1; mist.LightInfluence=0.8
	mist.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.18,0.3),NumberSequenceKeypoint.new(0.8,0.34),NumberSequenceKeypoint.new(1,1)})
	mist.Enabled=false; mist.Parent=anchor; stormMist=mist
	local rain=Instance.new("ParticleEmitter"); rain.Name="StormRain"; rain.Texture="rbxasset://textures/particles/smoke_main.dds"
	rain.Rate=340; rain.Lifetime=NumberRange.new(0.45,0.75); rain.Speed=NumberRange.new(0,0); rain.Acceleration=Vector3.new(0,-230,0)
	rain.EmissionDirection=Enum.NormalId.Top; rain.SpreadAngle=Vector2.new(10,10)
	rain.Size=NumberSequence.new(0.5); rain.Color=ColorSequence.new(Color3.fromRGB(150,170,205))
	rain.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.25),NumberSequenceKeypoint.new(1,0.5)})
	rain.LightEmission=0.2; rain.LightInfluence=0.5; rain.Parent=anchor; stormRain=rain
	stormFXConn=RunService.RenderStepped:Connect(function()
		local c=workspace.CurrentCamera
		if c and anchor and anchor.Parent then anchor.CFrame=c.CFrame*CFrame.new(0,4,-6) end
	end)
end
local function stopStormParticles()
	if stormFXConn then stormFXConn:Disconnect(); stormFXConn=nil end
	stormMist=nil; stormRain=nil
	if stormFXFolder then
		local fdr=stormFXFolder; stormFXFolder=nil
		for _,d in ipairs(fdr:GetDescendants()) do if d:IsA("ParticleEmitter") then d.Enabled=false end end
		task.delay(5,function() pcall(function() if fdr then fdr:Destroy() end end) end)
	end
end
local function isPlayerFlying()
	if _G.isFlying==true then return true end
	local ch=player.Character; local hum=ch and ch:FindFirstChildOfClass("Humanoid")
	return (hum~=nil) and (hum.FloorMaterial==Enum.Material.Air)
end
local function applyStormState(flying, t)
	local target = flying and STORM_FLY or STORM_LAND
	stormApplied = target
	-- DIAGNOSTICS: print the state we think the player is in + the exact fog values we are applying, so we
	-- can SEE whether the dense FLYING fog is actually being applied (or if the state is stuck on LANDED).
	local fc = target.FogColor
	if flying then
		print("[Storm] player state: FLYING -> applying FLYING fog")
		print(string.format("[Storm] FLYING fog applied: FogStart=%d FogEnd=%d FogColor=(%d,%d,%d) Brightness=%.2f",
			target.FogStart, target.FogEnd, math.round(fc.R*255), math.round(fc.G*255), math.round(fc.B*255), target.Brightness))
	else
		print("[Storm] player state: LANDED -> applying LANDED fog")
		print(string.format("[Storm] LANDED fog applied: FogStart=%d FogEnd=%d", target.FogStart, target.FogEnd))
	end
	TweenService:Create(Lighting, TweenInfo.new(t or 1.1, Enum.EasingStyle.Sine), {
		ClockTime=target.ClockTime, Brightness=target.Brightness, ExposureCompensation=target.ExposureCompensation,
		FogColor=target.FogColor, FogStart=target.FogStart, FogEnd=target.FogEnd,
		OutdoorAmbient=target.OutdoorAmbient, Ambient=target.Ambient,
	}):Play()
	-- HARD-CULL atmosphere handling.
	if flying then
		-- The enforcer below REMOVES any Atmosphere + pins the dense classic-fog wall every frame, so just
		-- report the actual values that make the solid wall (everything beyond FogEnd = 100% FogColor).
		local fc2 = STORM_FLY.FogColor
		print(string.format("[Storm] FLYING hard-cull: Atmosphere REMOVED + classic Fog FogStart=%d FogEnd=%d FogColor=(%d,%d,%d) (solid wall, islands fully hidden)",
			STORM_FLY.FogStart, STORM_FLY.FogEnd, math.round(fc2.R*255), math.round(fc2.G*255), math.round(fc2.B*255)))
	else
		-- LANDED: re-attach the Atmosphere (saved original props) so the world looks normal-stormy and the
		-- island is VISIBLE again. Classic fog also eases back via the Lighting tween above.
		if stormAtmos then
			if not stormAtmos.Parent then stormAtmos.Parent = Lighting end
			if savedAtmos then
				local s = savedAtmos
				TweenService:Create(stormAtmos, TweenInfo.new(t or 1.1, Enum.EasingStyle.Sine), {
					Density=s.Density, Offset=s.Offset, Color=s.Color, Decay=s.Decay, Glare=s.Glare, Haze=s.Haze,
				}):Play()
			end
			print(string.format("[Storm] LANDED: Atmosphere restored (Density=%.2f) -> island visible", savedAtmos and savedAtmos.Density or 0))
		else
			print("[Storm] LANDED: no Atmosphere -> classic Fog eased back, island visible")
		end
	end
	if stormMist then stormMist.Enabled = flying end -- thick enveloping cloud only while flying
end

-- ENFORCER: while the storm is active AND the player is flying, REMOVE any Atmosphere (it disables
-- classic Fog) and HARD-PIN the dense classic fog every frame -> a SOLID wall, everything beyond
-- FogEnd is 100% FogColor, islands fully hidden. Doing it every RenderStepped means even if streaming
-- or another system re-adds an Atmosphere / restomps the fog, the storm wall wins. While LANDED the
-- enforcer does nothing, so applyStormState re-attaches the Atmosphere + eases fog back (island visible).
local function startStormFogEnforcer()
	if stormFogConn then return end
	stormFogConn = RunService.RenderStepped:Connect(function()
		if not _G.thunderstormActive then return end
		if not isPlayerFlying() then return end
		-- Remove any Atmosphere every frame (it would otherwise disable classic Fog). Keep the FIRST one
		-- captured (+ its saved props) so landed/end can re-attach and restore it.
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			if not stormAtmos then
				stormAtmos = atm
				if not savedAtmos then savedAtmos = { Density=atm.Density, Offset=atm.Offset, Color=atm.Color, Decay=atm.Decay, Glare=atm.Glare, Haze=atm.Haze } end
			end
			atm.Parent = nil
		end
		-- Pin the dense classic-fog HARD WALL (now actually rendered, since no Atmosphere is present).
		Lighting.FogStart = STORM_FLY.FogStart
		Lighting.FogEnd   = STORM_FLY.FogEnd
		Lighting.FogColor = STORM_FLY.FogColor
	end)
end
local function stopStormFogEnforcer()
	if stormFogConn then stormFogConn:Disconnect(); stormFogConn = nil end
end
local function startStormSky()
	if not savedStormLighting then
		savedStormLighting={ ClockTime=Lighting.ClockTime, Brightness=Lighting.Brightness, ExposureCompensation=Lighting.ExposureCompensation,
			FogColor=Lighting.FogColor, FogStart=Lighting.FogStart, FogEnd=Lighting.FogEnd,
			OutdoorAmbient=Lighting.OutdoorAmbient, Ambient=Lighting.Ambient }
	end
	-- ATMOSPHERE: classic Fog is DISABLED whenever an Atmosphere exists, so to make the classic-fog wall
	-- show while flying we REMOVE the Atmosphere (in the enforcer, every frame). Capture the existing one
	-- + SAVE its original props now so landed/end can re-attach and restore it. If none exists, classic
	-- Fog already works directly -- nothing to remove.
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		stormAtmos = atm; stormAtmosOurs = false
		if not savedAtmos then
			savedAtmos = { Density=atm.Density, Offset=atm.Offset, Color=atm.Color, Decay=atm.Decay, Glare=atm.Glare, Haze=atm.Haze }
		end
		print(string.format("[Storm] Lighting.Atmosphere FOUND (it disables classic Fog) -- will REMOVE it while flying so the classic-fog wall renders. orig Density=%.2f", atm.Density))
	else
		stormAtmos = nil; stormAtmosOurs = false; savedAtmos = nil
		print("[Storm] No Lighting.Atmosphere present -- classic Fog wall renders directly.")
	end
	-- NOTE: if islands STILL show with the classic-fog wall (FogEnd~60, no Atmosphere), the remaining
	-- cause is render distance -- with StreamingEnabled the engine can draw distant islands past the fog.
	print("[Storm] workspace.StreamingEnabled = "..tostring(workspace.StreamingEnabled)..
		" (if true and islands still show through the classic-fog wall, render distance is drawing them -- needs a render-distance fix)")
	if not stormCC then stormCC=Instance.new("ColorCorrectionEffect"); stormCC.Name="ThunderstormCC"; stormCC.Parent=Lighting end
	stormCC.Brightness=0; stormCC.Contrast=0; stormCC.Saturation=0; stormCC.TintColor=Color3.fromRGB(255,255,255)
	TweenService:Create(stormCC, TweenInfo.new(1.5), {Brightness=0, Contrast=-0.03, Saturation=-0.35, TintColor=Color3.fromRGB(244,246,250)}):Play()
	startStormParticles()
	stormState = isPlayerFlying()
	applyStormState(stormState, 1.5)
	startStormFogEnforcer()   -- hard-pin the dense flying fog every frame so nothing can override it
	local terrain=workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local c=terrain:FindFirstChildOfClass("Clouds")
		if c then if not savedClouds then savedClouds={Cover=c.Cover,Density=c.Density,Color=c.Color,Enabled=c.Enabled} end stormClouds=c; stormCloudsOurs=false
		else stormClouds=Instance.new("Clouds"); stormClouds.Parent=terrain; stormCloudsOurs=true end
		stormClouds.Enabled=true
		TweenService:Create(stormClouds, TweenInfo.new(1.5), {Cover=0.92,Density=0.62,Color=Color3.fromRGB(90,94,102)}):Play()
	end
end
local function triggerLightning()
	if not stormApplied then return end
	Lighting.Brightness=5; Lighting.ExposureCompensation=1.6
	Lighting.OutdoorAmbient=Color3.fromRGB(248,250,255); Lighting.Ambient=Color3.fromRGB(238,242,250)
	TweenService:Create(Lighting, TweenInfo.new(0.3), {
		Brightness=stormApplied.Brightness, ExposureCompensation=stormApplied.ExposureCompensation,
		OutdoorAmbient=stormApplied.OutdoorAmbient, Ambient=stormApplied.Ambient,
	}):Play()
end
local function stopStormSky()
	stormApplied=nil; stormState=nil
	stopStormFogEnforcer()   -- STOP pinning fog BEFORE restoring, so the restore tween isn't re-stomped each frame
	stopStormParticles()
	if savedStormLighting then
		TweenService:Create(Lighting, TweenInfo.new(1.5), {
			ClockTime=savedStormLighting.ClockTime, Brightness=savedStormLighting.Brightness, ExposureCompensation=savedStormLighting.ExposureCompensation,
			FogColor=savedStormLighting.FogColor, FogStart=savedStormLighting.FogStart, FogEnd=savedStormLighting.FogEnd,
			OutdoorAmbient=savedStormLighting.OutdoorAmbient, Ambient=savedStormLighting.Ambient,
		}):Play()
		savedStormLighting=nil
	end
	if stormCC then local cc=stormCC; stormCC=nil
		local fd=TweenService:Create(cc, TweenInfo.new(1.5), {Brightness=0,Contrast=0,Saturation=0,TintColor=Color3.fromRGB(255,255,255)})
		fd:Play(); fd.Completed:Connect(function() pcall(function() cc:Destroy() end) end)
	end
	if stormClouds then local cl=stormClouds; stormClouds=nil
		if stormCloudsOurs then stormCloudsOurs=false
			local t=TweenService:Create(cl, TweenInfo.new(1.5), {Cover=0,Density=0}); t:Play(); t.Completed:Connect(function() pcall(function() cl:Destroy() end) end)
		elseif savedClouds then local s=savedClouds; savedClouds=nil
			TweenService:Create(cl, TweenInfo.new(1.5), {Cover=s.Cover,Density=s.Density,Color=s.Color}):Play(); cl.Enabled=s.Enabled
		end
	end
	-- ATMOSPHERE RESTORE: the enforcer leaves the Atmosphere DETACHED while flying, so on end RE-ATTACH
	-- it and tween its saved original props back -> normal clear visibility returns.
	if stormAtmos then
		local a = stormAtmos; stormAtmos = nil
		pcall(function()
			if not a.Parent then a.Parent = Lighting end
			if savedAtmos then
				local s = savedAtmos
				TweenService:Create(a, TweenInfo.new(1.5), {
					Density=s.Density, Offset=s.Offset, Color=s.Color, Decay=s.Decay, Glare=s.Glare, Haze=s.Haze,
				}):Play()
			end
		end)
		print(string.format("[Storm] Atmosphere RE-ATTACHED + RESTORED to original Density=%.2f", savedAtmos and savedAtmos.Density or 0))
	end
	savedAtmos = nil; stormAtmosOurs = false
end

local function cleanupWeather()
	for _,obj in ipairs(workspace:GetChildren()) do
		if obj.Name=="RainDrop" or obj.Name=="WindStreak" or obj.Name=="AggressiveBird" or obj.Name=="SpaceJunk" or obj.Name=="HazardPlane" or obj.Name=="PlaneTracer" then
			pcall(function() obj:Destroy() end)
		end
	end
	-- Restore the storm Lighting/fog/particles to normal + kill the wind (the dark look is world/Lighting-based now).
	pcall(stopStormSky)
	_G.thunderWindVec=Vector3.new(0,0,0)
	-- cleanup 2D rain frames in stormSg
	for _,obj in ipairs(stormSg:GetChildren()) do
		if obj.Name=="RainDrop2D" then pcall(function() obj:Destroy() end) end
	end
end

local function endEvent()
	eventBanner.Visible=false; glowPulseActive=false; hideGlow()
	_G.serverEventActive=false; _G.serverEventDisplayName=""
	_G.serverEventSpeedMult=1; _G.serverEventCoinMult=1; _G.serverEventGasDrainMult=1
	_G.serverEventHeightMult=1; _G.serverEventRingMult=1
	_G.thunderstormActive=false; _G.windstormActive=false
	windstormSound:Stop() -- ensure the windstorm loop stops on any forced event end
	thunderstormSound:Stop() -- ensure the thunderstorm sound stops on any forced event end
	stormBlur.Enabled=false -- ensure the storm blur clears on any forced event end
	-- Clear any full-screen flash/lightning overlays INSTANTLY so no screen tint lingers past the event.
	lightningFlash.BackgroundTransparency=1
	flashFrame.BackgroundTransparency=1
	countPill.Visible=false
	for _,sg2 in ipairs(activeEventSgs) do pcall(function() sg2:Destroy() end) end; activeEventSgs={}
	cleanupWeather()
end

-- LOAD-TIME CLEAN SLATE: guarantee no leftover medium-event UI is showing when this client starts
-- (e.g. rejoining). All event UI elements already construct hidden; this is a belt-and-suspenders clear.
pcall(endEvent)

local function pulseRings()
	for _,entry in ipairs(_G.activeRings) do
		if entry.part and entry.part.Parent then
			pcall(function()
				entry.part.Transparency=0
				TweenService:Create(entry.part,TweenInfo.new(0.5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Size=Vector3.new(1.5,30,30)}):Play()
			end)
		end
	end
end

-- ===== PARTICLE SPAWNERS =====
local function spawnRain2D()
	for _=1,5 do
		task.spawn(function()
			local drop=Instance.new("Frame"); drop.Name="RainDrop2D"
			drop.Size=UDim2.new(0,2,0,14); drop.Position=UDim2.new(math.random(0,98)/100,0,-0.02,0)
			drop.BackgroundColor3=Color3.fromRGB(150,180,255); drop.BackgroundTransparency=0.3
			drop.BorderSizePixel=0; drop.ZIndex=5; drop.Parent=stormSg
			TweenService:Create(drop,TweenInfo.new(0.5,Enum.EasingStyle.Linear),{Position=UDim2.new(drop.Position.X.Scale,0,1.05,0)}):Play()
			task.delay(0.55,function() pcall(function() drop:Destroy() end) end)
		end)
	end
end

local function spawnRainBatch()
	local char=player.Character; local hrpNow=char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	for _=1,30 do
		task.spawn(function()
			local drop=Instance.new("Part"); drop.Name="RainDrop"; drop.Size=Vector3.new(0.05,2,0.05); drop.Color=Color3.fromRGB(200,220,255)
			drop.Material=Enum.Material.Neon; drop.Transparency=0.5; drop.CanCollide=false; drop.CastShadow=false; drop.Anchored=false
			drop.Position=hrpNow.Position+Vector3.new(math.random(-30,30),math.random(5,20),math.random(-30,30)); drop.Parent=workspace
			local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(0,1e6,0); bv.Velocity=Vector3.new(0,-60,0); bv.Parent=drop
			task.delay(1.5,function() pcall(function() if drop.Parent then drop:Destroy() end end) end)
		end)
	end
end

local function spawnWindStreak(dir,speed,col)
	local char=player.Character; local hrpNow=char and char:FindFirstChild("HumanoidRootPart"); if not hrpNow then return end
	local streak=Instance.new("Part"); streak.Name="WindStreak"; streak.Size=Vector3.new(0.1,0.1,4); streak.Color=col or Color3.new(1,1,1)
	streak.Material=Enum.Material.Neon; streak.Transparency=0.4; streak.CanCollide=false; streak.CastShadow=false; streak.Anchored=false
	streak.Position=hrpNow.Position+Vector3.new(math.random(-20,20),math.random(-5,15),math.random(-20,20)); streak.Parent=workspace
	local bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(1e6,1e6,1e6); bv.Velocity=(dir or Vector3.new(1,0,0))*speed; bv.Parent=streak
	task.delay(1,function() pcall(function() if streak.Parent then streak:Destroy() end end) end)
end

local function spawnFloatingCoinEmoji()
	if not _G.serverEventActive then return end
	local sg2=Instance.new("ScreenGui"); sg2.ResetOnSpawn=false; sg2.ZIndexBehavior=Enum.ZIndexBehavior.Global; sg2.Parent=PlayerGui
	addEventSg(sg2)
	local lbl=Instance.new("TextLabel"); lbl.Text="\xF0\x9F\xAA\x99"; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=24
	lbl.BackgroundTransparency=1; lbl.TextColor3=Color3.fromRGB(255,215,0)
	lbl.Size=UDim2.new(0,40,0,40); lbl.Position=UDim2.new(math.random(5,90)/100,0,1.05,0); lbl.ZIndex=6; lbl.Parent=sg2
	TweenService:Create(lbl,TweenInfo.new(3,Enum.EasingStyle.Linear),{Position=UDim2.new(math.random(5,90)/100,0,-0.1,0)}):Play()
	task.delay(3,function() pcall(function() sg2:Destroy() end) end)
end

local function spawnFloatingRingEmoji()
	if not _G.serverEventActive then return end
	local sg2=Instance.new("ScreenGui"); sg2.ResetOnSpawn=false; sg2.ZIndexBehavior=Enum.ZIndexBehavior.Global; sg2.Parent=PlayerGui
	addEventSg(sg2)
	local sx=math.random(5,90)/100
	local lbl=Instance.new("TextLabel"); lbl.Text="\xF0\x9F\x8E\xAF"; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=22
	lbl.BackgroundTransparency=1; lbl.TextColor3=Color3.fromRGB(255,100,200)
	lbl.Size=UDim2.new(0,40,0,40); lbl.Position=UDim2.new(sx,0,math.random(20,80)/100,0); lbl.ZIndex=6; lbl.Parent=sg2
	TweenService:Create(lbl,TweenInfo.new(3,Enum.EasingStyle.Linear),{Position=UDim2.new(sx+math.random(-10,10)/100,0,math.random(10,70)/100,0),TextTransparency=1}):Play()
	task.delay(3,function() pcall(function() sg2:Destroy() end) end)
end

local function spawnLightningStrike()
	local char=player.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	local strikeX=hrp.Position.X+math.random(-150,150)
	local strikeZ=hrp.Position.Z+math.random(-150,150)
	local boltHeight=hrp.Position.Y+200
	local segments=8
	local prevPos=Vector3.new(strikeX,boltHeight,strikeZ)
	for i=1,segments do
		local bolt=Instance.new("Part"); bolt.Name="LightningBolt"
		bolt.Size=Vector3.new(0.3,boltHeight/segments,0.3)
		bolt.Material=Enum.Material.Neon; bolt.Color=Color3.fromRGB(255,255,200)
		bolt.Anchored=true; bolt.CanCollide=false; bolt.CastShadow=false
		local segPos=Vector3.new(prevPos.X+math.random(-15,15),boltHeight-(i*boltHeight/segments),prevPos.Z+math.random(-15,15))
		bolt.Position=segPos; prevPos=segPos; bolt.Parent=workspace
		game:GetService("Debris"):AddItem(bolt,0.15)
	end
	local flash=Instance.new("Frame"); flash.Size=UDim2.new(1,0,1,0); flash.Position=UDim2.new(0,0,0,0)
	flash.BackgroundColor3=Color3.fromRGB(255,255,255); flash.BackgroundTransparency=0.2
	flash.ZIndex=15; flash.Parent=stormSg
	TweenService:Create(flash,TweenInfo.new(0.15),{BackgroundTransparency=1}):Play()
	game:GetService("Debris"):AddItem(flash,0.2)
	local dist=(hrp.Position-Vector3.new(strikeX,hrp.Position.Y,strikeZ)).Magnitude
	if dist<50 then
		pcall(function() hrp.Velocity=Vector3.new(math.random(-20,20),5,math.random(-20,20)) end)
		if _G.showFloatingText then _G.showFloatingText("\xe2\x9a\xa1 Near miss!",Color3.fromRGB(255,255,0)) end
	end
end

-- ===== THUNDERSTORM =====
local function startThunderstorm(dur)
	_G.thunderstormActive=true
	if not thunderstormSound.IsPlaying then thunderstormSound:Play() end -- once; don't replay on re-trigger
	stormBlur.Enabled=false -- NO screen blur: the storm look is real 3D fog + cloud particles (HUD stays bright)
	startStormSky()           -- dark thundercloud while flying / island visible when landed + cloud/rain particles
	_G.thunderWindVec=Vector3.new(0,0,0) -- STRONG storm wind ON (the loop evolves it; CoreClient adds it to flight)
	startGlowPulse(Color3.fromRGB(50,50,80))
	showEventBanner("\xe2\x9b\x88 THUNDERSTORM","\xe2\x9b\x88\xef\xb8\x8f Hold on tight!",Color3.fromRGB(50,50,80))
	countPill.BackgroundColor3=Color3.fromRGB(50,50,80); countPill.Visible=true
	local endT=tick()+(dur or 25)
	task.spawn(function()
		local lightTimer=math.random(40,100)*0.1
		local rainTimer=0; local rain2DTimer=0; local windChangeTimer=0; local strikeTimer=math.random(200,400)*0.01
		local windTarget=Vector3.new(0,0,0)
		while tick()<endT and _G.thunderstormActive do
			local dt2=task.wait(0.05); if not dt2 then dt2=0.05 end
			rainTimer=rainTimer+dt2; rain2DTimer=rain2DTimer+dt2; lightTimer=lightTimer-dt2; windChangeTimer=windChangeTimer-dt2; strikeTimer=strikeTimer-dt2
			if rainTimer>=0.5 then rainTimer=0; pcall(spawnRainBatch) end
			if rain2DTimer>=0.3 then rain2DTimer=0; pcall(spawnRain2D) end
			if lightTimer<=0 then
				lightTimer=math.random(40,100)*0.1
				triggerLightning() -- 3D lighting SPIKE lights up the cloud (no 2D frame -> GUI stays bright)
				task.delay(math.random(15,70)*0.01,function() pcall(function() thunderSound:Play() end) end)
			end
			if strikeTimer<=0 then
				strikeTimer=math.random(200,400)*0.01
				pcall(spawnLightningStrike)
			end
			-- STRONG VARYING WIND: re-pick a hard gust from a random direction every 2-4s, then ease toward it
			if windChangeTimer<=0 then
				windChangeTimer=math.random(20,40)*0.1
				local a=math.random()*math.pi*2
				local mag=STORM_WIND_FORCE*(0.55+math.random()*0.45)   -- 55-100% of the (strong) force
				windTarget=Vector3.new(math.cos(a)*mag,0,math.sin(a)*mag)
			end
			local cur=_G.thunderWindVec or Vector3.new(0,0,0)
			_G.thunderWindVec=cur+(windTarget-cur)*math.clamp(dt2*1.4,0,1)
			-- FLYING = dark blinding cloud (islands gone); LANDED = fog eased so the island is visible
			local nowFly=isPlayerFlying()
			if nowFly~=stormState then stormState=nowFly; applyStormState(nowFly, 1.0) end
			local rem=math.max(0,math.ceil(endT-tick()))
			countLabel.Text="\xe2\x9b\x88 THUNDERSTORM: "..rem.."s"
			if rem<=0 then break end
		end
		_G.thunderstormActive=false; glowPulseActive=false
		_G.thunderWindVec=Vector3.new(0,0,0) -- wind off (CoreClient reads zero -> normal flight)
		thunderstormSound:Stop() -- stop the storm sound when the event ends, even mid-playback
		stormBlur.Enabled=false
		stopStormSky()           -- restore Lighting/fog/particles to normal
		lightningFlash.BackgroundTransparency=1
		countPill.Visible=false; hideGlow()
	end)
end

-- ===== WINDSTORM =====
local function startWindstorm()
	_G.windstormActive=true
	windstormSound:Play() -- looping ambient; same instance, so a re-trigger restarts (never stacks)
	local rx=math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
	local rz=math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
	_G.windstormDir=Vector3.new(rx,0,rz).Unit
	startGlowPulse(Color3.fromRGB(0,200,220))
	showEventBanner("\xF0\x9F\x8C\xAA WINDSTORM","\xF0\x9F\x8C\xAA The wind is insane!",Color3.fromRGB(0,200,220))
	countPill.BackgroundColor3=Color3.fromRGB(0,200,220); countPill.Visible=true
	local endT=tick()+20
	task.spawn(function()
		local dirChangeTimer=0; local streakTimer=0
		while tick()<endT and _G.windstormActive do
			local dt2=task.wait(0.05); if not dt2 then dt2=0.05 end
			dirChangeTimer=dirChangeTimer+dt2; streakTimer=streakTimer+dt2
			if dirChangeTimer>=4 then
				dirChangeTimer=0
				local rx2=math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
				local rz2=math.random(1,2)==1 and math.random(-10,-3) or math.random(3,10)
				local newDir=Vector3.new(rx2,0,rz2).Unit
				_G.windstormDir=(_G.windstormDir+newDir).Unit
			end
			if streakTimer>=0.1 then
				streakTimer=0
				pcall(function() spawnWindStreak(_G.windstormDir,60,Color3.new(1,1,1)) end)
			end
			local rem=math.max(0,math.ceil(endT-tick()))
			countLabel.Text="\xF0\x9F\x8C\xAA WINDSTORM: "..rem.."s"
			if rem<=0 then break end
		end
		_G.windstormActive=false; glowPulseActive=false
		windstormSound:Stop() -- stop the loop cleanly when the windstorm ends
		countPill.Visible=false; hideGlow()
	end)
end

-- ===== SERVER EVENT HANDLER =====
local ServerEventNotify=_G.ServerEventNotify
if ServerEventNotify then
	ServerEventNotify.OnClientEvent:Connect(function(eventName,dispName,duration,msg,color)
		pcall(function()
			if eventName=="THUNDERSTORM" then pcall(startThunderstorm, tonumber(duration) or 25); return end
			if eventName=="WINDSTORM" then pcall(startWindstorm); return end
			if eventName=="END" then endEvent(); return end
			endEvent()
			_G.serverEventActive=true
			local dur=tonumber(duration) or 30
			_G.serverEventEndTime=os.time()+dur
			_G.serverEventDisplayName=tostring(dispName)
			local eventColor=color or Color3.fromRGB(100,200,255)

			showEventBanner(dispName,msg,eventColor)
			startGlowPulse(eventColor)
			countPill.BackgroundColor3=eventColor; countPill.Visible=true

			if eventName=="FART_STORM" then
				_G.serverEventSpeedMult=1.3
				task.spawn(function()
					while _G.serverEventActive do
						task.wait(0.2)
						pcall(function()
							local d=Vector3.new(math.random(-10,10),0,math.random(-10,10))
							if d.Magnitude>0 then spawnWindStreak(d.Unit,80,Color3.fromRGB(200,230,255)) end
						end)
					end
				end)
				task.spawn(function()
					while _G.serverEventActive do
						task.wait(5); if not _G.serverEventActive then break end
						local char=player.Character; local hrpNow=char and char:FindFirstChild("HumanoidRootPart")
						if hrpNow then local sa=hrpNow:FindFirstChild("FartAmbientSound"); if sa then pcall(function() sa:Play() end) end end
					end
				end)
				task.spawn(function()
					while _G.serverEventActive do
						task.wait(3); if not _G.serverEventActive then break end
						local char=player.Character; local hrpNow=char and char:FindFirstChild("HumanoidRootPart")
						if hrpNow then pcall(function() hrpNow.CFrame=hrpNow.CFrame*CFrame.new(math.random(-2,2)/10,0,math.random(-2,2)/10) end) end
					end
				end)

			elseif eventName=="COIN_RUSH" then
				_G.serverEventCoinMult=2
				task.spawn(function()
					while _G.serverEventActive do task.wait(0.5); pcall(spawnFloatingCoinEmoji) end
				end)

			elseif eventName=="LOW_GRAVITY" then
				_G.serverEventSpeedMult=0.5; _G.serverEventGasDrainMult=0.1

			elseif eventName=="POWER_SURGE" then
				_G.serverEventHeightMult=1.5; _G.serverEventSpeedMult=1.5
				task.spawn(function()
					for _=1,3 do screenFlash(Color3.fromRGB(255,255,0),0.3,0.15); task.wait(0.4) end
				end)
				task.spawn(function()
					while _G.serverEventActive do
						task.wait(0.05+math.random()*0.1)
						for _,f in ipairs(glowEdges) do
							if f.Visible then pcall(function() f.BackgroundTransparency=math.random()*0.6 end) end
						end
					end
				end)
				task.spawn(function()
					while _G.serverEventActive do
						task.wait(1); if not _G.serverEventActive then break end
						screenFlash(Color3.new(1,1,1),0.85,0.1)
					end
				end)

			elseif eventName=="RING_FEVER" then
				_G.serverEventRingMult=10
				pulseRings()
				task.spawn(function()
					while _G.serverEventActive do task.wait(0.8); pcall(spawnFloatingRingEmoji) end
				end)
			end

			-- countdown update
			task.spawn(function()
				local endT=os.time()+dur
				while _G.serverEventActive do
					local rem=math.max(0,endT-os.time())
					countLabel.Text=tostring(dispName)..": "..rem.."s"
					if rem<=0 then break end
					task.wait(1)
				end
			end)
		end)
	end)
end

print("EVENTCLIENT READY")
print("ALL FIXES DONE")

-- ===== BIRD NUKE EVENT =====
task.spawn(function()
	local RS2=game:GetService("ReplicatedStorage")
	local BirdNukeEvent2=RS2:WaitForChild("BirdNukeEvent",30)
	if not BirdNukeEvent2 then return end
	local Debris=game:GetService("Debris")
	-- Bird Nuke boom SFX, played IMMEDIATELY when the nuke fires (server-wide; each client plays its
	-- own one-shot and lets it play out normally). If it fails to load, the effect still runs — the
	-- teleport is server-driven. NUKE_BOOM_VOLUME is the single adjustable volume.
	local NUKE_BOOM_SOUND_ID = "rbxassetid://89988274755984"
	local NUKE_BOOM_VOLUME = 0.8
	local function playBoomSound()
		local boom = Instance.new("Sound")
		boom.Name = "BirdNukeBoom"
		boom.SoundId = NUKE_BOOM_SOUND_ID
		boom.Volume = NUKE_BOOM_VOLUME
		boom.Parent = SoundService
		boom:Play()
		boom.Ended:Connect(function() boom:Destroy() end)
		Debris:AddItem(boom, 30) -- safety cleanup if it never finishes/loads
	end
	-- Short camera shake that decays over `duration`. Applied in RenderStepped (after the default
	-- camera update) and self-disconnects, so it leaves no permanent camera offset.
	local function screenShake(duration, magnitude)
		if not workspace.CurrentCamera then return end
		local t0 = tick(); local conn
		conn = RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			local e = tick() - t0
			if e >= duration or not cam then conn:Disconnect(); return end
			local m = magnitude * (1 - e/duration)
			cam.CFrame = cam.CFrame * CFrame.new((math.random()-0.5)*2*m, (math.random()-0.5)*2*m, 0)
		end)
	end
	-- Server-wide nuke explosion, shown to EVERYONE (incl. the buyer): boom sound + orange screen
	-- flash + screen shake, all fired immediately when the nuke goes off.
	local function nukeExplosion()
		playBoomSound()
		local nukeFlash=mkFrame(stormSg,{
			Size=UDim2.new(1,0,1,0),Position=UDim2.new(0,0,0,0),
			BackgroundColor3=Color3.fromRGB(255,80,0),BackgroundTransparency=0.4,ZIndex=18
		})
		TweenService:Create(nukeFlash,TweenInfo.new(0.5),{BackgroundTransparency=1}):Play()
		Debris:AddItem(nukeFlash,0.6)
		screenShake(0.6, 2.5)
	end
	BirdNukeEvent2.OnClientEvent:Connect(function(buyerName)
		pcall(function()
			showEventBanner("\xF0\x9F\x90\xA6\xF0\x9F\x92\xA5 BIRD NUKE",buyerName.." launched a BIRD NUKE!",Color3.fromRGB(255,80,0))
			local isBuyer=(buyerName==player.Name)
			-- Everyone (incl. the buyer) sees the explosion immediately: boom sound + flash + shake.
			nukeExplosion()
			if isBuyer then
				-- Buyer is spared the swarm and is NOT teleported; they just enjoy the payoff.
				if _G.showFloatingText then _G.showFloatingText("\xF0\x9F\x90\xA6\xF0\x9F\x92\xA5 BIRD NUKE launched! Everyone else got sent home!",Color3.fromRGB(255,215,0)) end
				startGlowPulse(Color3.fromRGB(255,215,0))
				task.delay(5,function()
					if not _G.thunderstormActive and not _G.windstormActive and not _G.serverEventActive then hideGlow() end
				end)
			else
				playBirdSound()
				if _G.showFloatingText then _G.showFloatingText("\xF0\x9F\x90\xA6\xF0\x9F\x92\xA5 BIRD NUKE INCOMING!",Color3.fromRGB(255,80,0)) end
				for i=1,30 do
					task.delay((i-1)*0.1,function()
						pcall(function()
							local char2=player.Character; local hrp2=char2 and char2:FindFirstChild("HumanoidRootPart"); if not hrp2 then return end
							local ang=math.random()*math.pi*2
							local spawnPos=hrp2.Position+Vector3.new(math.cos(ang)*40,math.random(-5,5),math.sin(ang)*40)
							local nukeBird=Instance.new("Model"); nukeBird.Name="NukeBird"; nukeBird.Parent=workspace
							_G.birdSpawnedThisFlight = true -- [BALANCE LOGGING] flag-only: a (nuke) bird spawned this flight
							local nbBody=Instance.new("Part"); nbBody.Name="Body"; nbBody.Size=Vector3.new(4,1.5,2)
							nbBody.Color=Color3.fromRGB(180,0,0); nbBody.Material=Enum.Material.SmoothPlastic
							nbBody.CanCollide=false; nbBody.Anchored=false; nbBody.Position=spawnPos; nbBody.Parent=nukeBird
							nukeBird.PrimaryPart=nbBody
							local nbEye=Instance.new("Part"); nbEye.Name="Eye"; nbEye.Shape=Enum.PartType.Ball; nbEye.Size=Vector3.new(0.4,0.4,0.4)
							nbEye.Color=Color3.fromRGB(255,220,0); nbEye.Material=Enum.Material.Neon; nbEye.CanCollide=false; nbEye.Parent=nukeBird
							local eyeWeld=Instance.new("Weld"); eyeWeld.Part0=nbBody; eyeWeld.Part1=nbEye; eyeWeld.C0=CFrame.new(0,0.5,0.9); eyeWeld.Parent=nbBody
							local nbVel=Instance.new("BodyVelocity"); nbVel.MaxForce=Vector3.new(1e6,1e6,1e6); nbVel.Velocity=Vector3.new(0,0,0); nbVel.Parent=nbBody
							Debris:AddItem(nukeBird,25)
							task.spawn(function()
								while nukeBird.Parent do
									local c2=player.Character; local hrpNow2=c2 and c2:FindFirstChild("HumanoidRootPart")
									if not hrpNow2 then nukeBird:Destroy(); break end
									local diff2=hrpNow2.Position-nbBody.Position
									if diff2.Magnitude<5 then
										nukeBird:Destroy()
										_G.birdHitThisFlight = true -- [BALANCE LOGGING] flag-only: a (nuke) bird hit the player this flight
										if _G.applyBirdDrain then _G.applyBirdDrain() end
										pcall(function()
											local px2=math.random(1,2)==1 and math.random(-40,-15) or math.random(15,40)
											local pz2=math.random(1,2)==1 and math.random(-40,-15) or math.random(15,40)
											local pushBV2=Instance.new("BodyVelocity"); pushBV2.MaxForce=Vector3.new(1e6,0,1e6); pushBV2.Velocity=Vector3.new(px2,0,pz2); pushBV2.Parent=hrpNow2
											task.delay(0.3,function() pcall(function() pushBV2:Destroy() end) end)
										end)
										pcall(function()
											local eff=_G.effectFlashFrame
											if eff then eff.BackgroundColor3=Color3.fromRGB(255,0,0); eff.BackgroundTransparency=0.5; TweenService:Create(eff,TweenInfo.new(0.25),{BackgroundTransparency=0.97}):Play() end
										end)
										if _G.showFloatingText then _G.showFloatingText("\xF0\x9F\x90\xA6 NUKE BIRD HIT! -80% gas!",Color3.fromRGB(255,0,0)) end
										break
									elseif diff2.Magnitude>150 then nukeBird:Destroy(); break
									else pcall(function() nbVel.Velocity=diff2.Unit*80 end) end
									task.wait(0.05)
								end
							end)
						end)
					end)
				end
			end
		end)
	end)
end)

print("CHUNK 2 DONE")
