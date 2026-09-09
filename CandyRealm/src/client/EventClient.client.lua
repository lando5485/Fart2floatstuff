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
local PLANE_COUNT = 6              -- planes per gap zone (was 4; a ~24-plane swarm before that)
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
local MAX_SHOOTERS = 3             -- HARD cap: never more than 3 planes shooting the player at once
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
-- Horizontally centered at the very top, out of the player's way. It now appears ONLY AFTER the announcement
-- banner has slid away (see showCountPillAfterBanner), so it can sit in the SAME prime top-center spot the banner
-- used (Y=12) without ever overlapping it. The coin counter is top-RIGHT, so there's no conflict there either.
local countSg=Instance.new("ScreenGui"); countSg.Name="EventCountGui"; countSg.ResetOnSpawn=false; countSg.ZIndexBehavior=Enum.ZIndexBehavior.Global; countSg.Parent=PlayerGui
-- TOP-RIGHT STATUS COLUMN (under the coin pill at y=10), NOT top-centre. It used to sit at
-- UDim2.new(0.5,0,0,12) -- the identical spot RocketUI's teleport button hard-codes, so an active
-- rocket event simply covered this countdown. Top-centre is now reserved for transient banners
-- (NotifyCenter's hero lane) and the objective card; persistent status lives down the right edge.
local countPill=mkFrame(countSg,{Size=UDim2.new(0,280,0,44),Position=UDim2.new(1,-10,0,66),AnchorPoint=Vector2.new(1,0),BackgroundColor3=Color3.fromRGB(180,60,220),Visible=false,ZIndex=14,BorderSizePixel=0})
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
-- THE LIGHTNING CRACK. This id is BROKEN, and it is broken in the Food realm too (same line, same id,
-- EventClient:239 over there) -- every boot logs "Failed to load sound rbxassetid://1369158752: Asset type
-- does not match requested type", which is what Roblox says when an id points at a MODEL or an IMAGE rather
-- than an audio asset. It has therefore never made a sound in either realm: the storm ambient plays, the
-- lightning flashes, and the crack that is supposed to land with it is silent.
--
-- Left in place rather than deleted, because the intent is right and the fix is one id. Behind it is the
-- same fallback Sfx.luau uses -- an asset this realm's own boot log confirms loads (AssetFetchStatus.Success)
-- -- so lightning makes a noise today instead of waiting on a replacement. Swap THUNDER_ID for a real
-- thunder-clap id and the fallback stops being used; nothing else has to change.
local THUNDER_ID    = "rbxassetid://1369158752"
local THUNDER_FALLBACK = "rbxassetid://4612378364"
local thunderSound=Instance.new("Sound"); thunderSound.Name="ThunderSound"; thunderSound.SoundId=THUNDER_ID; thunderSound.Volume=0.8; thunderSound.Parent=workspace
task.spawn(function()
	-- PreloadAsync yields until the asset resolves either way, so this is the only honest way to know.
	local ok = pcall(function() game:GetService("ContentProvider"):PreloadAsync({ thunderSound }) end)
	if not ok or thunderSound.TimeLength <= 0 then
		thunderSound.SoundId = THUNDER_FALLBACK
		thunderSound.PlaybackSpeed = 0.55   -- pitched down: the fallback is a short blip, this makes it a rumble
		thunderSound.Volume = 0.9
		warn(("[EventClient] thunder id %s did not load (it is not an audio asset) -- using the known-good "
			.. "fallback %s pitched down. Put a real thunder-clap id in THUNDER_ID.")
			:format(THUNDER_ID, THUNDER_FALLBACK))
	end
end)
local screechSound=Instance.new("Sound"); screechSound.Name="ScreechSound"; screechSound.SoundId="rbxassetid://3240498563"; screechSound.Volume=1; screechSound.Parent=workspace

-- ===== BIRD SYSTEM =====
_G.activeBirds = _G.activeBirds or {} -- nothing ever initialised this, so createBird threw on '#nil'

local function createBird()
	if #_G.activeBirds>=12 then return end   -- room for a 5-strong flock on top of 5 sightseers
	local char=player.Character; local hrpTarget=char and char:FindFirstChild("HumanoidRootPart"); if not hrpTarget then return end
	local angle=math.random()*math.pi*2
	local spawnPos=hrpTarget.Position+Vector3.new(math.cos(angle)*50,0,math.sin(angle)*50)
	-- A GINGERBREAD MAN GLIDER. The chase, the hit test, the despawn and the flap timing are all the
	-- bird's, unchanged -- only what you SEE changed, plus the two arms now do the flapping the wings
	-- used to. Body stays 3 x 1 x 1.5 because the 6-stud hit test below is tuned to it.
	local GINGER = Color3.fromRGB(186,120,62)
	local ICING  = Color3.fromRGB(252,248,244)
	local birdModel=Instance.new("Model"); birdModel.Name="GingerbreadGlider"; birdModel.Parent=workspace
	local body=Instance.new("Part"); body.Name="Body"; body.Size=Vector3.new(3,1,1.5)
	body.Color=GINGER; body.Material=Enum.Material.SmoothPlastic; body.CanCollide=false; body.Anchored=false; body.Position=spawnPos; body.Parent=birdModel
	birdModel.PrimaryPart=body
	local birdVel=Instance.new("BodyVelocity"); birdVel.MaxForce=Vector3.new(1e6,1e6,1e6); birdVel.Velocity=Vector3.new(0,0,0); birdVel.Parent=body

	local function bit(name, size, colour, c0, shape)
		local p=Instance.new("Part"); p.Name=name; p.Size=size; p.Color=colour
		p.Material=Enum.Material.SmoothPlastic; p.CanCollide=false; p.CastShadow=false; p.Parent=birdModel
		if shape then pcall(function() p.Shape=shape end) end
		local w=Instance.new("Weld"); w.Part0=body; w.Part1=p; w.C0=c0; w.Parent=body
		return p, w
	end

	bit("Head", Vector3.new(1.5,1.4,1.4), GINGER, CFrame.new(0,0,-1.3), Enum.PartType.Ball)
	for _, lx in ipairs({-0.55, 0.55}) do                                  -- legs
		bit("Leg", Vector3.new(0.7,0.6,1.6), GINGER, CFrame.new(lx,0,1.3))
	end
	-- ARMS: these are what flap. Same weld handles the bird's wing loop drove, so the animation
	-- below needs no change at all -- it just moves arms instead of wings now.
	local _, weld1 = bit("ArmL", Vector3.new(2.6,0.6,0.9), GINGER, CFrame.new(-2.2,0,-0.4))
	local _, weld2 = bit("ArmR", Vector3.new(2.6,0.6,0.9), GINGER, CFrame.new( 2.2,0,-0.4))
	-- icing: three buttons, a collar zigzag, and a piped smile
	for k=-1,1 do bit("Button", Vector3.new(0.4,0.4,0.4), ICING, CFrame.new(0,0.55,k*0.5), Enum.PartType.Ball) end
	bit("Collar", Vector3.new(1.6,0.25,0.3), ICING, CFrame.new(0,0.4,-0.7))
	bit("Smile",  Vector3.new(0.8,0.2,0.2),  ICING, CFrame.new(0,-0.1,-1.9))
	-- currant eyes, kept NEON so they still read as a threat closing on you from a distance
	local function makeEye(name,ox)
		local e=Instance.new("Part"); e.Name=name; e.Shape=Enum.PartType.Ball; e.Size=Vector3.new(0.35,0.35,0.35)
		e.Color=Color3.fromRGB(226,44,66); e.Material=Enum.Material.Neon; e.CanCollide=false; e.Parent=birdModel
		local ew=Instance.new("Weld"); ew.Part0=body; ew.Part1=e; ew.C0=CFrame.new(ox,0.35,-1.75); ew.Parent=body
	end
	makeEye("Eye1",-0.35); makeEye("Eye2",0.35)
	_G.birdSpawnedThisFlight = true -- [BALANCE LOGGING] flag-only: a bird spawned during this flight (read by CoreClient FLIGHT DEBUG)
	local entry={model=birdModel,body=body}
	table.insert(_G.activeBirds,entry)
	task.delay(15,function() pcall(function() if birdModel.Parent then birdModel:Destroy() end end) end)
	task.spawn(function()
		local flapUp=true
		while birdModel.Parent do
			local a=flapUp and 0.6 or -0.4
			pcall(function() weld1.C0=CFrame.new(-2.2,0,-0.4)*CFrame.Angles(0,0,a) end)
			pcall(function() weld2.C0=CFrame.new( 2.2,0,-0.4)*CFrame.Angles(0,0,-a) end)
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
					-- CRUMBLE. He does not survive the collision either: eight biscuit shards thrown
					-- out from the impact, gone in 1.2s. Built before the shove so the burst appears
					-- exactly where the two of you met, not where you get pushed to.
					pcall(function()
						for k=1,8 do
							local sh=Instance.new("Part")
							sh.Size=Vector3.new(0.5+math.random()*0.5, 0.4, 0.4+math.random()*0.4)
							sh.Color=Color3.fromRGB(186,120,62); sh.Material=Enum.Material.SmoothPlastic
							sh.CanCollide=false; sh.CastShadow=false
							sh.CFrame=CFrame.new(body.Position)*CFrame.Angles(math.random()*6,math.random()*6,math.random()*6)
							sh.AssemblyLinearVelocity=Vector3.new((math.random()-0.5)*70, math.random()*40, (math.random()-0.5)*70)
							sh.Parent=workspace
							game:GetService("Debris"):AddItem(sh, 1.2)
							if k==1 then                                   -- one white icing chip in the mix
								sh.Color=Color3.fromRGB(252,248,244)
							end
						end
					end)
					-- SIDEWAYS SHOVE. Horizontal only -- it knocks you off your line and costs you the
					-- steering to get back, but never touches your climb, so it cannot drop you out of
					-- the gap band the way a downward push would.
					pcall(function()
						local c2=player.Character; local h2=c2 and c2:FindFirstChild("HumanoidRootPart")
						if h2 then
							local away=Vector3.new(diff.X, 0, diff.Z)
							away = (away.Magnitude > 0.1) and -away.Unit or Vector3.new(1,0,0)
							h2.AssemblyLinearVelocity = h2.AssemblyLinearVelocity + away * 85
						end
					end)
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

-- ===== SPACE-JUNK HAZARD =====
-- Assorted falling CANDY (jawbreakers / peppermint wheels / candy canes) that drops from ABOVE the flying player, ONLY in
-- the air gaps above island 6 (the 6->14 climb). Dodgeable medium trickle. On hit: END THE CURRENT RISE
-- (player falls under gravity, same as running out of power) with the fart meter FULLY PRESERVED — no
-- drain — plus an optional small downward shove (via _G.applyJunkHit in CoreClient). Each piece despawns
-- after falling past the player or JUNK_LIFETIME (so it never piles up — capped for mobile). Independent
-- of DISABLE_EVENTS.
-- ACTIVE SPAWN RANGE: A DEBRIS FIELD IN THE GAP ABOVE EVERY 4th ISLAND.
--
-- WHAT WAS HERE, AND WHY IT NEVER FIRED. The band was
--       { lo = 11978, hi = 24500 }   -- "islands 10 -> 14"
-- and those are the FIRST REALM's heights, copied over with the rest of this file: Fart to Float's
-- island 10 sits at Y=11978 and its island 14 at Y=24017. Candy's tower is a completely different
-- shape -- slot 1 at 220 and the summit at 100,620. So on this realm that band lands somewhere
-- between slot 5 (10,220) and slot 7 (21,620): an arbitrary strip a fifth of the way up, with
-- nothing at all across the remaining ~79,000 studs of climb. The hazard was shipped, wired and
-- effectively invisible.
--
-- DERIVED, NOT TYPED. The bands are computed from IslandOrder.SLOT_POS at boot, so they cannot
-- drift the way the copied numbers did -- move an island and its debris field moves with it.
-- One field per JUNK_EVERY islands, sitting in the AIR GAP above that slot with an 18% margin at
-- each end: you get clear of the island you launched from before it starts, and it stops well
-- short of the one you are aiming for, so arrivals are never pelted.
local IslandOrder = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	:WaitForChild("IslandOrder"))

-- EVERY OTHER ISLAND, not every fourth. Three bands over a thirteen-island tower meant most of the
-- climb was empty sky; this puts something in six of the twelve gaps -- above slots 2, 4, 6, 8, 10
-- and 12 -- so you are never more than two islands from the next one.
--
-- The FIRST gap is deliberately still clear. Starting at slot 2 means island1 -> island9, which is
-- flown on a tier-2 gut with 28 seconds of tank and no idea what any of this is yet, stays a plain
-- climb. Everything after it is contested.
local JUNK_EVERY  = 2
local JUNK_MARGIN = 0.18   -- fraction of the gap left clear at each end

local JUNK_ZONES = {}
for slot = JUNK_EVERY, IslandOrder.COUNT - 1, JUNK_EVERY do
	local a, b = IslandOrder.SLOT_POS[slot], IslandOrder.SLOT_POS[slot + 1]
	if a and b and b.Y > a.Y then
		local gap = b.Y - a.Y
		JUNK_ZONES[#JUNK_ZONES + 1] = {
			lo   = a.Y + gap * JUNK_MARGIN,
			hi   = b.Y - gap * JUNK_MARGIN,
			slot = slot,
			-- THE GAP'S OWN CENTRE LINE. The tower zig-zags -- slot 12 sits at X 340 and slot 13 at
			-- X -360 -- so "the airspace between them" is nowhere near the world origin. The plane
			-- patrol used to be a cylinder around X=0,Z=0 (realm 1's comment says so outright),
			-- which on the top gap put it up to 350 studs off the line you actually fly.
			cx = (a.X + b.X) * 0.5,
			cz = (a.Z + b.Z) * 0.5,
			-- and the islands either side, so a hazard can be made visible FROM one of them.
			-- fromX/fromZ matter as much as fromY: the tower ZIG-ZAGS, so the gap's midpoint is
			-- nowhere near the island you are stood on. Slot 12 sits at X 340 and slot 13 at X -360,
			-- which puts their midpoint at X -10 -- 350 studs off the edge of Sugarbeet Farm.
			fromX = a.X, fromY = a.Y, fromZ = a.Z,
			toY   = b.Y,
		}
	end
end
do
	local parts = {}
	for _, z in ipairs(JUNK_ZONES) do
		parts[#parts + 1] = ("above slot %d: %d..%d"):format(z.slot, math.floor(z.lo), math.floor(z.hi))
	end
	print(("[Junk] %d debris field(s), one per %d islands -- %s"):format(
		#JUNK_ZONES, JUNK_EVERY, table.concat(parts, " | ")))
end
local function inJunkZone(y)
	for _, z in ipairs(JUNK_ZONES) do
		if y >= z.lo and y <= z.hi then return true end
	end
	return false
end

-- The band you are stood UNDER, if any. Used by the two hazards that otherwise only exist while you
-- are inside one, so that from the island you can see what is waiting up there rather than
-- launching into a surprise. Returns nil once you are actually in the band -- from that point the
-- real hazard takes over.
local function bandBelowMe(y)
	for _, z in ipairs(JUNK_ZONES) do
		if z.fromY and y >= z.fromY and y < z.lo then return z end
	end
	return nil
end

-- (Moved below inJunkZone on purpose: it is a LOCAL, so a reference to it from ABOVE this point
-- resolves to a nil GLOBAL instead -- the loop would run and throw on its first band test.)
--======================================================================
-- GINGERBREAD GLIDERS -- THE THIRD GAP HAZARD
--======================================================================
-- The bird this is built from rolled ONCE per flight at a flat 1/15 and could appear at ANY height,
-- and it was then switched off entirely (chance 0) so nothing ever spawned. Both of those are wrong
-- for what this is now: it is a GAP hazard, and it belongs to the same bands as the planes and the
-- falling candy. Something waits above every 4th island, and this is the part of it that comes to
-- find you.
--
-- A FLOCK, NOT A SINGLE: three arrive together, staggered so they close on you in sequence rather
-- than as one wall. createBird()'s own cap (6 alive) stops them stacking up if you linger.
--
-- ONE FLOCK PER VISIT. `armed` re-arms only when you leave the band, so hovering inside one cannot
-- farm an endless stream -- the same reason the plane band has hysteresis.
local GINGER_FLOCK     = 5   -- gliders per flock, once you are IN the band
local AMBIENT_GLIDERS  = 5   -- how many drift in the band while you watch from the island below
local GINGER_STAGGER = 0.7   -- seconds between them
-- ⚠ DECLARED HERE, NOT DOWN BY randomGapPoint WHERE THEY ARE DOCUMENTED. These used to live at
-- the plane-showcase section ~450 lines below -- AFTER the ambient-glider loop and createJunk
-- had already referenced them. A Lua local is invisible to code above its declaration, so both
-- call sites silently read nil GLOBALS instead and threw "attempt to perform arithmetic (mul)
-- on nil" every time a glider or band-junk spawn fired -- the one recurring runtime error in
-- every session log. The full story of what the showcase circuit IS stays with randomGapPoint.
local SHOWCASE_LO     = 300   -- studs above the island: nearest the patrol comes
local SHOWCASE_HI     = 700   -- ...and the top of the showcase slab
local SHOWCASE_RADIUS = 130   -- tighter than GAP_RADIUS so the circuit stays over the island
task.spawn(function()
	if DISABLE_EVENTS then print("[Ginger] disabled (DISABLE_EVENTS)") return end
	print(("[Ginger] gingerbread gliders armed -- %d per gap band, one flock per visit"):format(GINGER_FLOCK))
	local armed = true
	while true do
		task.wait(0.25)
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		local inBand = hrp and _G.isFlying and inJunkZone(hrp.Position.Y)
		if inBand and armed then
			armed = false
			-- CLEAR THE SIGHTSEERS. The ambient gliders you were watching from the island are still
			-- alive up here, and createBird() caps how many can exist at once -- leaving them would
			-- eat the slots the real flock needs. They have done their job the moment you arrive.
			for i = #_G.activeBirds, 1, -1 do
				local e = _G.activeBirds[i]
				if e and e.model and e.model:GetAttribute("AmbientGlider") then
					pcall(function() e.model:Destroy() end)
					table.remove(_G.activeBirds, i)
				end
			end
			playBirdSound()
			for k = 1, GINGER_FLOCK do
				task.delay((k - 1) * GINGER_STAGGER, function()
					local c2 = player.Character
					local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
					if h2 and inJunkZone(h2.Position.Y) then createBird() end
				end)
			end
		elseif not inBand then
			armed = true                      -- left the band: the next one can send a flock again
			-- ...and while you are stood UNDER a band, a couple of them drift about up there so the
			-- gap is visibly occupied. createBird() spawns relative to the player, so these are moved
			-- up into the band right after and left to their own chase loop -- which, from that far
			-- away, reads as circling. They are cleaned up by the same 15s despawn as the real ones.
			local band = hrp and bandBelowMe(hrp.Position.Y)
			if band and #_G.activeBirds < AMBIENT_GLIDERS and math.random() < 0.45 then
				createBird()
				local e = _G.activeBirds[#_G.activeBirds]
				if e and e.model then
					-- TAGGED, so entering the band can clear them (see the flock spawn above). Without
					-- this, five ambient gliders would fill createBird's alive-cap and the real flock
					-- would arrive two strong.
					e.model:SetAttribute("AmbientGlider", true)
				end
				if e and e.body then
					local a = math.random() * 2 * math.pi
					local r = SHOWCASE_RADIUS * math.sqrt(math.random())
					e.body.CFrame = CFrame.new((band.fromX or band.cx or 0) + math.cos(a) * r,
						(band.fromY or band.lo) + SHOWCASE_LO + math.random() * (SHOWCASE_HI - SHOWCASE_LO),
						(band.fromZ or band.cz or 0) + math.sin(a) * r)
				end
			end
		end
	end
end)
local JUNK_SPAWN_INTERVAL = 0.45  -- seconds between spawns -- denser candyfall through every gap
local JUNK_LIFETIME       = 6     -- seconds before auto-despawn (>= 220/55 fall time so it reaches the player from the higher spawn)
local JUNK_MAX_ACTIVE     = 24    -- cap concurrent debris (raised with the rate; still mobile-safe)
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

--======================================================================
-- WHAT FALLS OUT OF THE CANDY SKY
--======================================================================
-- All eight pieces were the first realm's junkyard: a rock, a tire, a car door, a satellite, an
-- oil drum, an old TV, a rocket booster and a washing machine. Correct for Fart to Float's sky and
-- completely wrong over a tower of candy islands -- a corroded washing machine falling past Taffy
-- Town reads as a bug, not a hazard.
--
-- Same eight slots, same part counts, same nominalMax maths (the hit radius is derived from it, so
-- getting that wrong would give phantom hits or pass-throughs). Only the SUBJECT changed, and each
-- one is re-skinned into the shape it was already closest to -- the tire was a disc, so it is a
-- peppermint wheel; the door was a flat panel, so it is a chocolate bar; the booster was a tall
-- cylinder, so it is an ice cream cone. Nothing about the physics moved.
local function buildJunk()
	local v = 0.8 + math.random() * 0.4          -- +/-20% size variation (whole piece)
	local D, R = JUNK_DEBRIS_SIZE, JUNK_ROCK_SIZE
	local model = Instance.new("Model"); model.Name = "CandyJunk"
	local body, nominalMax
	local pick = math.random(8)

	if pick == 1 then            -- JAWBREAKER (7 parts): a knobbly boiled sweet, layers showing
		body = jPart(model, Vector3.new(R*0.72, R*0.72, R*0.72)*v, Color3.fromRGB(250,240,230), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		body.CFrame = CFrame.Angles(math.random()*6, math.random()*6, math.random()*6)
		local shell = { Color3.fromRGB(236,72,110), Color3.fromRGB(120,210,235), Color3.fromRGB(255,205,90),
			Color3.fromRGB(150,225,140), Color3.fromRGB(196,140,240), Color3.fromRGB(255,140,90) }
		for k = 1, 6 do
			local cs = R*(0.34+math.random()*0.3)*v
			local c = jPart(model, Vector3.new(cs, cs, cs), shell[k], Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			c.CFrame = body.CFrame * CFrame.new((math.random()-0.5)*R*v*0.62,(math.random()-0.5)*R*v*0.62,(math.random()-0.5)*R*v*0.62)
			jWeld(body, c)
		end
		nominalMax = R*0.72*v

	elseif pick == 2 then        -- PEPPERMINT WHEEL (7 parts): white disc, red spokes, mint hub
		body = jPart(model, Vector3.new(D*0.34, D*1.5, D*1.5)*v, Color3.fromRGB(252,248,244), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		body.CFrame = CFrame.new()
		local hub = jPart(model, Vector3.new(D*0.4, D*0.5, D*0.5)*v, Color3.fromRGB(150,225,190), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		hub.CFrame = body.CFrame; jWeld(body, hub)
		for k = 0, 4 do          -- the swirl: five red wedges around the face
			local sp = jPart(model, Vector3.new(D*0.38, D*1.34, D*0.2)*v, Color3.fromRGB(236,72,110), Enum.Material.SmoothPlastic, Enum.PartType.Block)
			sp.CFrame = body.CFrame * CFrame.Angles(k*math.pi/5, 0, 0); jWeld(body, sp)
		end
		nominalMax = D*1.5*v

	elseif pick == 3 then        -- CHOCOLATE BAR (6 parts): scored slab, foil back, a bitten corner
		body = jPart(model, Vector3.new(D*1.5, D*0.28, D*1.0)*v, Color3.fromRGB(92,54,28), Enum.Material.SmoothPlastic, Enum.PartType.Block)
		body.CFrame = CFrame.new()
		for k = -1, 1 do         -- the scoring between squares
			local sc = jPart(model, Vector3.new(D*0.06, D*0.34, D*1.0)*v, Color3.fromRGB(66,38,20), Enum.Material.SmoothPlastic, Enum.PartType.Block)
			sc.CFrame = body.CFrame * CFrame.new(k*D*0.42*v, 0, 0); jWeld(body, sc)
		end
		local foil = jPart(model, Vector3.new(D*1.56, D*0.06, D*1.06)*v, Color3.fromRGB(226,226,232), Enum.Material.Foil, Enum.PartType.Block)
		foil.CFrame = body.CFrame * CFrame.new(0, -D*0.18*v, 0); jWeld(body, foil)
		local bite = jPart(model, Vector3.new(D*0.34, D*0.34, D*0.34)*v, Color3.fromRGB(120,74,42), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		bite.CFrame = body.CFrame * CFrame.new(D*0.7*v, 0, D*0.46*v); jWeld(body, bite)
		nominalMax = D*1.5*v

	elseif pick == 4 then        -- LOLLIPOP (8 parts): swirled disc on a paper stick
		body = jPart(model, Vector3.new(D*0.3, D*1.3, D*1.3)*v, Color3.fromRGB(255,255,250), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		body.CFrame = CFrame.new()
		local swirl = { Color3.fromRGB(236,72,110), Color3.fromRGB(120,210,235), Color3.fromRGB(255,205,90), Color3.fromRGB(150,225,140) }
		for k = 0, 3 do          -- four arms of the swirl, shrinking towards the centre
			local arm = jPart(model, Vector3.new(D*0.34, D*(1.1 - k*0.2), D*0.22)*v, swirl[k+1], Enum.Material.SmoothPlastic, Enum.PartType.Block)
			arm.CFrame = body.CFrame * CFrame.Angles(k*math.pi/4, 0, 0); jWeld(body, arm)
		end
		local stick = jPart(model, Vector3.new(D*0.14, D*1.1, D*0.14)*v, Color3.fromRGB(244,238,225), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		stick.CFrame = body.CFrame * CFrame.new(0, -D*1.0*v, 0) * CFrame.Angles(0, 0, math.rad(90)); jWeld(body, stick)
		local wrap = jPart(model, Vector3.new(D*0.34, D*0.3, D*0.34)*v, Color3.fromRGB(236,226,255), Enum.Material.Foil, Enum.PartType.Ball, 0.35)
		wrap.CFrame = body.CFrame * CFrame.new(0, D*0.1*v, 0); jWeld(body, wrap)
		nominalMax = D*1.3*v

	elseif pick == 5 then        -- GUMDROP (6 parts): sugared dome, crystals catching the light
		body = jPart(model, Vector3.new(D*1.1, D*1.0, D*1.1)*v, Color3.fromRGB(236,72,110), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		body.CFrame = CFrame.new()
		local base = jPart(model, Vector3.new(D*0.3, D*1.05, D*1.05)*v, Color3.fromRGB(214,54,94), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		base.CFrame = body.CFrame * CFrame.new(0, -D*0.4*v, 0) * CFrame.Angles(0, 0, math.rad(90)); jWeld(body, base)
		for k = 1, 4 do          -- the sugar crust
			local g = jPart(model, Vector3.new(D*0.16, D*0.16, D*0.16)*v, Color3.fromRGB(255,250,240), Enum.Material.Sand, Enum.PartType.Block)
			g.CFrame = body.CFrame * CFrame.Angles(0, k*math.pi/2, 0) * CFrame.new(D*0.5*v, D*0.2*v, 0)
				* CFrame.Angles(math.random()*3, math.random()*3, math.random()*3)
			jWeld(body, g)
		end
		nominalMax = D*1.1*v

	elseif pick == 6 then        -- CANDY CANE (7 parts): striped shaft with a hooked crook
		body = jPart(model, Vector3.new(D*0.32, D*1.6, D*0.32)*v, Color3.fromRGB(252,248,244), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		body.CFrame = CFrame.Angles(0, 0, math.rad(90))
		for k = -2, 2 do         -- the red barber stripes
			local st = jPart(model, Vector3.new(D*0.36, D*0.2, D*0.36)*v, Color3.fromRGB(236,72,110), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			st.CFrame = body.CFrame * CFrame.new(k*D*0.3*v, 0, 0) * CFrame.Angles(math.rad(22), 0, 0); jWeld(body, st)
		end
		local hook = jPart(model, Vector3.new(D*0.32, D*0.5, D*0.32)*v, Color3.fromRGB(252,248,244), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		hook.CFrame = body.CFrame * CFrame.new(D*0.8*v, D*0.28*v, 0) * CFrame.Angles(0, 0, math.rad(90)); jWeld(body, hook)
		nominalMax = D*1.6*v

	elseif pick == 7 then        -- ICE CREAM CONE (9 parts): waffle cone, two scoops, a cherry
		body = jPart(model, Vector3.new(D*1.0, D*0.9, D*0.9)*v, Color3.fromRGB(214,164,96), Enum.Material.Sand, Enum.PartType.Cylinder)
		body.CFrame = CFrame.Angles(0, 0, math.rad(90))
		for k = -1, 1 do         -- the waffle scoring
			local w = jPart(model, Vector3.new(D*1.02, D*0.1, D*0.94)*v, Color3.fromRGB(184,136,74), Enum.Material.Sand, Enum.PartType.Block)
			w.CFrame = body.CFrame * CFrame.Angles(k*math.pi/3, 0, 0); jWeld(body, w)
		end
		local s1 = jPart(model, Vector3.new(D*0.85, D*0.85, D*0.85)*v, Color3.fromRGB(255,190,215), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		s1.CFrame = body.CFrame * CFrame.new(0, D*0.62*v, 0); jWeld(body, s1)
		local s2 = jPart(model, Vector3.new(D*0.7, D*0.7, D*0.7)*v, Color3.fromRGB(255,250,238), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		s2.CFrame = body.CFrame * CFrame.new(0, D*1.16*v, 0); jWeld(body, s2)
		local cherry = jPart(model, Vector3.new(D*0.26, D*0.26, D*0.26)*v, Color3.fromRGB(226,44,66), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		cherry.CFrame = body.CFrame * CFrame.new(0, D*1.6*v, 0); jWeld(body, cherry)
		local sprinkle = jPart(model, Vector3.new(D*0.1, D*0.28, D*0.1)*v, Color3.fromRGB(120,210,235), Enum.Material.SmoothPlastic, Enum.PartType.Block)
		sprinkle.CFrame = body.CFrame * CFrame.new(D*0.3*v, D*0.9*v, D*0.2*v) * CFrame.Angles(0.6, 0.4, 0); jWeld(body, sprinkle)
		nominalMax = D*1.7*v

	else                          -- WRAPPED SWEET (9 parts): barrel of toffee, twisted foil ends
		body = jPart(model, Vector3.new(D*0.9, D*1.0, D*1.0)*v, Color3.fromRGB(255,176,86), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		body.CFrame = CFrame.new()
		for _, sx in ipairs({ -1, 1 }) do
			local neck = jPart(model, Vector3.new(D*0.24, D*0.5, D*0.5)*v, Color3.fromRGB(255,236,190), Enum.Material.Foil, Enum.PartType.Cylinder, 0.15)
			neck.CFrame = body.CFrame * CFrame.new(sx*D*0.55*v, 0, 0); jWeld(body, neck)
			local twist = jPart(model, Vector3.new(D*0.3, D*0.72, D*0.72)*v, Color3.fromRGB(255,236,190), Enum.Material.Foil, Enum.PartType.Cylinder, 0.15)
			twist.CFrame = body.CFrame * CFrame.new(sx*D*0.86*v, 0, 0) * CFrame.Angles(sx*0.7, 0, 0); jWeld(body, twist)
			local frill = jPart(model, Vector3.new(D*0.08, D*0.8, D*0.8)*v, Color3.fromRGB(255,246,214), Enum.Material.Foil, Enum.PartType.Cylinder, 0.25)
			frill.CFrame = body.CFrame * CFrame.new(sx*D*1.02*v, 0, 0); jWeld(body, frill)
		end
		local band = jPart(model, Vector3.new(D*0.94, D*0.22, D*1.04)*v, Color3.fromRGB(236,72,110), Enum.Material.SmoothPlastic, Enum.PartType.Block)
		band.CFrame = body.CFrame; jWeld(body, band)
		nominalMax = D*1.0*v
	end

	model.PrimaryPart = body
	return model, nominalMax / 2
end

-- `band` set = an AMBIENT piece: it falls through that band's airspace instead of onto the player,
-- so from the island below you can see candy tumbling through the gap you are about to cross. The
-- hit test further down is a distance check against the player, and an ambient piece is thousands
-- of studs away from them, so it can never register -- these are scenery that happens to use the
-- same builder, not a second hazard.
local function createJunk(band)
	if #activeJunk >= JUNK_MAX_ACTIVE then return end
	local char=player.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if not (band or JUNK_TEST_ON_ISLAND_1 or inJunkZone(hrp.Position.Y)) then return end
	local model, hitRadius = buildJunk()
	-- HOMING: a small fraction AIM at the player's CURRENT horizontal spot, but still spawn at the SAME
	-- full JUNK_SPAWN_HEIGHT above and then fall STRAIGHT down (no continuous homing) — so the player has
	-- full reaction time and can step aside. The other 95% spawn at a random horizontal offset.
	local homing = math.random() < JUNK_HOMING_CHANCE
	local ox = homing and 0 or math.random(-22, 22)
	local oz = homing and 0 or math.random(-22, 22)
	local spawnPos
	if band then
		-- Ambient: fall through the sky ABOVE THE ISLAND the player is stood on, for the same reason
		-- the plane showcase does -- over the gap's midpoint it is off to one side and invisible.
		-- Entering high enough to be a long visible fall, but centred where you are looking.
		local a = math.random() * 2 * math.pi
		local r = SHOWCASE_RADIUS * 1.6 * math.sqrt(math.random())
		local cx = band.fromX or band.cx or 0
		local cz = band.fromZ or band.cz or 0
		spawnPos = Vector3.new(cx + math.cos(a) * r, (band.fromY or band.lo) + 1200, cz + math.sin(a) * r)
	else
		spawnPos = hrp.Position + Vector3.new(ox, JUNK_SPAWN_HEIGHT, oz)
	end
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
		local c=player.Character; local h=c and c:FindFirstChild("HumanoidRootPart")
		if h then
			if _G.isFlying and (JUNK_TEST_ON_ISLAND_1 or inJunkZone(h.Position.Y)) then
				createJunk()                       -- the real thing: aimed at you, hits you
			else
				-- Stood on an island (or climbing toward one): if there is a band overhead, drop
				-- pieces through IT so the gap visibly has candy falling in it. TWO per tick at the
				-- full rate -- from the ground the pieces are small and spread over a 175-stud
				-- cylinder, so a trickle reads as nothing at all. This is scenery competing with an
				-- empty sky; it can afford to be generous.
				local band = bandBelowMe(h.Position.Y)
				if band then
					createJunk(band)
					createJunk(band)
				end
			end
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
-- THE SAME COPIED-HEIGHTS BUG THE JUNK ZONES HAD. This was
--       { {lo = 3580, hi = 4820} }   -- "between islands 5 and 6"
-- and 3580 / 4820 are FART TO FLOAT's Coconut Cove and Bread Board. On Candy's tower that strip
-- happens to land between Cookie Crumble (3620) and Gumtree Park (6420) -- so the planes did fly,
-- but in one arbitrary low gap and nowhere else across the other 94,000 studs of climb.
--
-- Derived from IslandOrder now, on the same JUNK_EVERY cadence as the falling candy, so the two
-- hazards share one rule: something is waiting in the gap above every 4th island.
local PLANE_BANDS = {}
for _, z in ipairs(JUNK_ZONES) do
	-- carried through whole: cx/cz aim the patrol at the real gap, fromY makes it visible from the
	-- island below it
	PLANE_BANDS[#PLANE_BANDS + 1] = {
		lo = z.lo, hi = z.hi, cx = z.cx, cz = z.cz, fromY = z.fromY, toY = z.toY, slot = z.slot,
	}
end
do
	local parts = {}
	for _, b in ipairs(PLANE_BANDS) do
		parts[#parts + 1] = ("slot %d: seen from Y%d, flown %d..%d, centred (%d, %d)")
			:format(b.slot, math.floor(b.fromY), math.floor(b.lo), math.floor(b.hi),
				math.floor(b.cx), math.floor(b.cz))
	end
	print(("[Planes] %d patrol band(s) -- %s"):format(#PLANE_BANDS, table.concat(parts, " | ")))
end
-- ⚠ HYSTERESIS, AND IT IS NOT A NICETY. The band test used to be a bare "is Y between lo and hi",
-- checked every frame, with the driver clearing every plane the moment it answered no and building
-- four new ones the moment it answered yes again. Hover on the boundary -- or lose your character
-- for a frame mid-teleport, which does the same thing -- and it alternates: the log filled with
-- "[Planes] spawned 4 planes in gap zone" fifteen times a second, four models built and destroyed
-- each time, for as long as the player stayed there.
--
-- Once you are IN the band you stay in it until you are BAND_EXIT_MARGIN studs clear of the edge.
-- Entering still takes the exact boundary, so the band is where it always was; only leaving is
-- sticky, and a wobble of a few studs cannot toggle it.
local BAND_EXIT_MARGIN = 120
-- WHEN DO THE PLANES EXIST?
--
-- They used to exist only while you were INSIDE the band -- so from the island below you looked up
-- at empty sky, launched, and four biplanes appeared around you with no warning. A hazard you
-- cannot see until you are in it is not a hazard you can plan around; it is an ambush.
--
-- Existence now starts at the ISLAND BELOW the gap (b.fromY) and runs to the top of the band. Stand
-- on Gumtree Park, look up, and the patrol is circling overhead where you are about to fly. What
-- does NOT change is the shooting: that is gated on being airborne further down, so while you are
-- stood on the island they only roam. You get to watch the thing that is going to shoot at you.
local function planeBandFor(y, current)
	for _,b in ipairs(PLANE_BANDS) do
		local lo, hi = (b.fromY or b.lo), b.hi
		if current == b then lo, hi = lo - BAND_EXIT_MARGIN, hi + BAND_EXIT_MARGIN end
		if y >= lo and y <= hi then return b end
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
-- A CHRISTMAS CANDY-CANE BIPLANE. Every dimension, weld offset and the un-welded Prop are exactly
-- as they were -- the flight model, the bank, the ScaleTo and the bullet muzzle all key off this
-- geometry, so moving any of it would change how the hazard plays. Only paint and two additions:
-- red/white barber stripes banded down the fuselage and across the wing (the thing that actually
-- says "candy cane" at 280 studs), and a holly sprig on the tail.
local function buildPlane()
	local model=Instance.new("Model"); model.Name="HazardPlane"
	local paint=Color3.fromRGB(236,72,110)          -- candy-cane red
	local cane =Color3.fromRGB(252,248,244)         -- peppermint white
	local metal=Color3.fromRGB(255,205,90)          -- gold sugar, where the bare metal was
	local fus=pPart(model, Vector3.new(3.6,3.6,16), paint, Enum.Material.SmoothPlastic, Enum.PartType.Block)
	fus.CFrame=CFrame.new(); model.PrimaryPart=fus
	-- the stripes: four white bands wrapped round the fuselage, angled like a real cane's
	for k=-1,2 do
		local band=pPart(model, Vector3.new(3.8,3.8,1.5), cane, Enum.Material.SmoothPlastic, Enum.PartType.Block)
		band.CFrame=fus.CFrame*CFrame.new(0,0,k*3.6)*CFrame.Angles(math.rad(18),0,0); pWeld(fus,band)
	end
	local nose=pPart(model, Vector3.new(3,3.4,3.4), metal, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	nose.CFrame=fus.CFrame*CFrame.new(0,0,-8.5)*CFrame.Angles(0,math.rad(90),0); pWeld(fus,nose)
	local wing=pPart(model, Vector3.new(16,0.7,4.5), paint, Enum.Material.SmoothPlastic, Enum.PartType.Block)
	wing.CFrame=fus.CFrame*CFrame.new(0,-0.3,-0.5); pWeld(fus,wing)
	-- ...and across the wing, so it reads as candy from above and below too
	for k=-1,1,2 do
		local ws=pPart(model, Vector3.new(2.4,0.9,4.6), cane, Enum.Material.SmoothPlastic, Enum.PartType.Block)
		ws.CFrame=wing.CFrame*CFrame.new(k*4.6,0,0); pWeld(fus,ws)
	end
	local fin=pPart(model, Vector3.new(0.5,3.5,3), cane, Enum.Material.SmoothPlastic, Enum.PartType.Block)
	fin.CFrame=fus.CFrame*CFrame.new(0,2,7); pWeld(fus,fin)
	local stab=pPart(model, Vector3.new(7,0.5,2.5), paint, Enum.Material.SmoothPlastic, Enum.PartType.Block)
	stab.CFrame=fus.CFrame*CFrame.new(0,0.3,7); pWeld(fus,stab)
	local cockpit=pPart(model, Vector3.new(3,1.8,4), Color3.fromRGB(190,240,255), Enum.Material.Glass, Enum.PartType.Block, 0.35)
	cockpit.CFrame=fus.CFrame*CFrame.new(0,2.2,-1); pWeld(fus,cockpit)
	-- holly on the tail fin, the one green note
	local holly=pPart(model, Vector3.new(2.6,0.4,1.4), Color3.fromRGB(86,168,104), Enum.Material.SmoothPlastic, Enum.PartType.Block)
	holly.CFrame=fus.CFrame*CFrame.new(0,3.6,7)*CFrame.Angles(0,0,math.rad(20)); pWeld(fus,holly)
	local berry=pPart(model, Vector3.new(0.8,0.8,0.8), Color3.fromRGB(226,44,66), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	berry.CFrame=fus.CFrame*CFrame.new(0,3.9,7); pWeld(fus,berry)
	for s=-1,1,2 do
		local strut=pPart(model, Vector3.new(0.4,3,0.4), cane, Enum.Material.SmoothPlastic, Enum.PartType.Block)
		strut.CFrame=fus.CFrame*CFrame.new(s*2.5,-3,-2); pWeld(fus,strut)
		local wheel=pPart(model, Vector3.new(0.6,2,2), Color3.fromRGB(92,54,28), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		wheel.CFrame=fus.CFrame*CFrame.new(s*2.5,-4.4,-2); pWeld(fus,wheel)
	end
	local hub=pPart(model, Vector3.new(1.2,1.4,1.4), metal, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	hub.CFrame=fus.CFrame*CFrame.new(0,0,-9)*CFrame.Angles(0,math.rad(90),0); pWeld(fus,hub)
	local blade=pPart(model, Vector3.new(0.5,10,1.4), Color3.fromRGB(150,225,190), Enum.Material.SmoothPlastic, Enum.PartType.Block)
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
-- HOW FAR ABOVE THE ISLAND THE PATROL DROPS TO WHILE YOU ARE STOOD ON IT.
--
-- Making the planes merely EXIST while you are on the island was not enough to see them. The band
-- starts a long way up -- 1,764 studs above Candy Mine Ridge, 3,420 above Sugarbeet Farm -- and a
-- 36-stud plane at 3,420 studs is about sixteen pixels. Technically visible; not something you
-- notice, and not a warning.
--
-- So while you are below the band they fly a SHOWCASE circuit a few hundred studs over your head,
-- where they read properly, and they climb back into the band on their own as you rise -- no
-- teleporting, they simply pick their next waypoint from wherever they belong now.
--
-- ⚠ THIS IS PURELY A VISUAL DESCENT. The shooting gate further down now also requires you to be
-- inside the REAL band, so bringing them within 400 studs of the island cannot turn into being shot
-- off the launchpad. They come close enough to look at, and no closer to being dangerous.
-- (SHOWCASE_LO / SHOWCASE_HI / SHOWCASE_RADIUS are declared up by the glider constants -- the
-- ambient-glider loop and createJunk use them hundreds of lines above this point, and a local
-- declared here was nil to both of them. See the note at the declaration.)

local function randomGapPoint(band)
	local r = GAP_RADIUS * math.sqrt(math.random())
	local a = math.random() * 2 * math.pi

	local loY = band.lo + GAP_VMARGIN
	local hiY = band.hi - GAP_VMARGIN
	local cx, cz = (band.cx or 0), (band.cz or 0)

	local ch  = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp and band.fromY and hrp.Position.Y < band.lo then
		-- BELOW THE BAND -> CIRCLE OVER THE ISLAND YOU ARE STOOD ON.
		--
		-- ⚠ AND OVER *IT*, NOT OVER THE GAP. Dropping the altitude alone was not enough and this is
		-- why: the tower zig-zags, so band.cx/cz -- the midpoint of the two islands -- is hundreds of
		-- studs to one side of either of them. From Sugarbeet Farm (X 340) the patrol was orbiting
		-- X -10: 350 studs past the edge of the island, out over empty sky behind you. Present,
		-- spawning, logged, and nowhere you would ever look.
		--
		-- The showcase circuit uses the ISLAND's own X/Z and a tighter radius, so it is genuinely
		-- overhead. The moment you climb into the band it goes back to the gap's centre line.
		loY = band.fromY + SHOWCASE_LO
		hiY = band.fromY + SHOWCASE_HI
		cx, cz = (band.fromX or cx), (band.fromZ or cz)
		r = SHOWCASE_RADIUS * math.sqrt(math.random())
	end
	local y = loY + math.random() * (hiY - loY)

	-- AROUND THE GAP, NOT AROUND THE ORIGIN. band.cx/cz is the midpoint of the two islands this gap
	-- joins; a cylinder at X=0,Z=0 was patrolling empty sky beside the route on every offset gap.
	return Vector3.new(cx + math.cos(a) * r, y, cz + math.sin(a) * r)
end

-- ===== ENGINE FLY-BY (ported from the Food realm's EventClient) =====
-- The one event sound Candy was missing. A 3D Sound welded to each plane's fuselage, fired as a ONE-SHOT
-- when the plane comes close enough to count as a pass -- not looped, so a short whoosh clip cannot
-- machine-gun, and a per-plane cooldown stops a circling plane re-triggering every second.
--
-- ONE TABLE rather than six top-level locals, same reason as everywhere else in this codebase.
--
-- ⚠ THE INVARIANT: ROLLOFF_MIN MUST STAY >= TRIGGER_DIST. A sound triggered at 85 studs with a 30-stud
-- full-volume radius is already attenuated to a fifth the instant it starts -- that is the original
-- "the pass was inaudible" bug in the realm this came from. Lower them together or not at all.
local FlyBy = {
	ID           = "rbxassetid://126002361266903",
	VOLUME       = 2.2,   -- at the source; rolls off with distance
	TRIGGER_DIST = 85,    -- studs: this close to the player counts as a pass. Fires BEFORE the closest
	                      -- point, so the engine is audible as the plane comes AT you, not after it has gone
	COOLDOWN     = 4.0,   -- seconds before the SAME plane may trigger again
	ROLLOFF_MIN  = 85,    -- full volume out to here (see the invariant above)
	ROLLOFF_MAX  = 260,   -- inaudible past here
}

local function spawnPlanes(band)
	clearPlanes(); activeBand = band
	for i=1,PLANE_COUNT do
		local model, blade = buildPlane()
		model.Parent = workspace
		local pos = randomGapPoint(band)
		model:PivotTo(CFrame.new(pos))

		-- Parented to a BasePart so it is positional: it arrives from the plane's direction and fades
		-- with distance on its own. Nothing to drive per-frame except the trigger test.
		local host = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		local snd
		if host and FlyBy.ID ~= "" then
			snd = Instance.new("Sound")
			snd.Name = "PlaneFlyBy"
			snd.SoundId = FlyBy.ID
			snd.Volume = FlyBy.VOLUME
			snd.Looped = false
			snd.RollOffMinDistance = FlyBy.ROLLOFF_MIN
			snd.RollOffMaxDistance = FlyBy.ROLLOFF_MAX
			snd.Parent = host
		end

		planes[i] = {
			model = model, blade = blade, spin = 0,
			pos = pos,
			flyby = snd,            -- may be nil if the model had no BasePart; every use is guarded
			flybyCooldown = 0,      -- seconds until this plane may play its fly-by again
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

local lastPlaneSpawn = 0        -- os.clock() of the last spawn; see the cooldown below

RunService.Heartbeat:Connect(function(dt)
	local char=player.Character
	local hrp=char and char:FindFirstChild("HumanoidRootPart")
	-- (!) NO CHARACTER IS NOT "OUT OF THE BAND". Respawning, teleporting and the wormhole all take
	-- the character away for a few frames; treating that as "left the zone" is what tore the
	-- planes down and rebuilt them mid-flight. With no body to measure we simply do nothing this
	-- frame and keep whatever is already flying.
	if not hrp then return end
	local band = planeBandFor(hrp.Position.Y, activeBand)
	if not band then
		if #planes>0 then clearPlanes(); clearBullets() end
		lastAirborne = nil
		return
	end
	-- ...and a hard floor on how often a spawn can happen at all. The hysteresis above fixes the
	-- cause; this makes the symptom impossible whatever else goes wrong later, because four models
	-- a frame is the kind of bug that comes back wearing a different hat.
	if band ~= activeBand and os.clock() - lastPlaneSpawn > 3 then
		lastPlaneSpawn = os.clock()
		spawnPlanes(band)
	end
	if band ~= activeBand then return end   -- waiting out the cooldown: nothing to drive yet

	-- LANDED-vs-FLYING GATE: planes only target/shoot while the player is AIRBORNE (FloorMaterial Air).
	-- Landed (standing on an island) = they just roam, no targeting/projectiles at the player.
	--
	-- ...AND INSIDE THE REAL BAND. The patrol now descends to a showcase circuit a few hundred studs
	-- over the island so you can actually see it from the ground (see SHOWCASE_LO above), which puts
	-- armed planes within range of someone who has not left yet. Without this second condition,
	-- "visible from the island" would have quietly become "shot at the moment you lift off", and the
	-- gap between islands would stop being where the danger lives. Existence and DANGER are now two
	-- different questions: they are visible from band.fromY, they only shoot from band.lo.
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local inHazardZone = hrp.Position.Y >= band.lo
	local airborne = (hum ~= nil) and (hum.FloorMaterial == Enum.Material.Air) and inHazardZone
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

		-- ---- ENGINE FLY-BY: one shot per pass, per plane ----
		-- Deliberately NOT gated on `airborne` like the shooting below. A plane roaring past while you are
		-- stood on an island is exactly the moment the sound is for; only the distance and the cooldown
		-- decide it.
		pl.flybyCooldown = math.max(0, pl.flybyCooldown - dt)
		if hrp and pl.flyby and pl.flyby.Parent and pl.flybyCooldown <= 0
			and (hrp.Position - pl.pos).Magnitude <= FlyBy.TRIGGER_DIST then
			pl.flybyCooldown = FlyBy.COOLDOWN
			pcall(function() pl.flyby:Play() end)
		end

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

-- Server events go through NotifyCenter's HERO lane (priority EVENT). The old eventBanner sat at
-- UDim2.new(0.5,0,0,10) -- the exact pixel the arrival, announce, reward and purchase banners ALSO
-- used, with nothing arbitrating between them, so a server event firing while you landed an island
-- drew both banners through each other. The hero lane shows one at a time and lets an island unlock
-- (higher priority) preempt the event notice rather than collide with it.
local function showEventBanner(dispName,msg,color)
	local NC = _G.NotifyCenter
	if not NC then return end
	NC.push({
		top      = tostring(dispName),
		text     = tostring(msg),
		color    = color,
		priority = NC.PRIORITY.EVENT,
		duration = 5,
	})
end

-- The pill and the banner no longer share a slot -- the banner goes to the hero lane (top-centre) and
-- the pill lives in the top-right status column -- so the pill no longer has to wait ~5.45s for the
-- banner to clear. A short beat is still nice so the two don't pop in on the same frame.
local BANNER_GONE_AFTER = 0.6
local pillToken = 0
-- Reveal the (top-centered) countdown pill, but ONLY after the banner has cleared the screen AND only if the event
-- is still running by then. `pillToken` cancels a pending reveal the moment a newer event/pill cycle begins, and
-- short events that finish before the banner clears simply never pop a pill (stillActive() is false by then).
local function showCountPillAfterBanner(stillActive)
	pillToken = pillToken + 1
	local myToken = pillToken
	countPill.Visible = false -- stay hidden while the announcement banner is on screen
	task.delay(BANNER_GONE_AFTER, function()
		if myToken == pillToken and (not stillActive or stillActive()) then
			countPill.Visible = true
		end
	end)
end

local activeEventSgs={}
local function addEventSg(sg2) table.insert(activeEventSgs,sg2) end

-- ===== SOUR STORM PALETTE =====
-- THE MECHANICS ARE THE FOOD REALM'S THUNDERSTORM, UNCHANGED. The fog wall, the fly-vs-land Lighting
-- swap, the wind vector, the lightning spikes, the rain batches, the countdown pill -- all of it is
-- the same code doing the same thing. Only the COLOURS and the WORDS are candy.
--
-- The internal event name stays THUNDERSTORM and must: ServerEventNotify's handler branches on that
-- exact string (see the note at the top of ServerEvents.server.lua), and renaming it turns the storm
-- into a generic banner with no weather attached. Display name is the only text safe to change, and
-- SOUR STORM is what BigEvents already announces it as.
--
-- Greens read off SourRain, deliberately: a realm should have ONE sour, and a player who has stood in
-- the acid rain should recognise the sky the moment this rolls in.
local SOUR_STORM = {
	KEY   = Color3.fromRGB(58, 92, 40),      -- banner / pill / glow: the storm's identity colour
	FOG_F = Color3.fromRGB(46, 72, 34),      -- FLYING: engulfed in sour cloud
	AMB_F = Color3.fromRGB(40, 58, 32),
	FOG_L = Color3.fromRGB(140, 178, 120),   -- LANDED: hazy sour daylight, island still readable
	AMB_L = Color3.fromRGB(140, 178, 120),
	CLOUD_A = Color3.fromRGB(84, 122, 62),   -- cloud mist, light and dark
	CLOUD_B = Color3.fromRGB(58, 88, 44),
	RAIN  = Color3.fromRGB(150, 226, 74),    -- SourRain's own green, exactly
	RAIN2D = Color3.fromRGB(168, 236, 96),
	-- THE SKY DOME ITSELF, not the fog in front of it. Atmosphere.Color tints the whole sky, so this
	-- is what turns the horizon dark green rather than just greying out what is near you.
	SKY     = Color3.fromRGB(52, 84, 40),
	SKY_HAZE = 4.2,       -- thick: haze is what carries the colour across the dome
	SKY_DENSITY = 0.42,   -- enough to feel heavy without washing the island out
}

-- ===== SOUR STORM SKY + WEATHER (rebuilt) -- DARK storm-cloud look while FLYING, island visible when LANDED.
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
	FogColor = SOUR_STORM.FOG_F, FogStart = 0, FogEnd = 60,  -- ~60 studs: islands fully invisible
	OutdoorAmbient = SOUR_STORM.AMB_F, Ambient = SOUR_STORM.AMB_F,
}
-- LANDED = on an island: cloud eases WAY back so the island is clearly visible (stormy but visible).
local STORM_LAND = {
	ClockTime = 14, Brightness = 1.6, ExposureCompensation = -0.1,
	FogColor = SOUR_STORM.FOG_L, FogStart = 50, FogEnd = 650,
	OutdoorAmbient = SOUR_STORM.AMB_L, Ambient = SOUR_STORM.AMB_L,
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
	mist.Color=ColorSequence.new(SOUR_STORM.CLOUD_A,SOUR_STORM.CLOUD_B) -- DARK sour-green storm cloud
	mist.LightEmission=0.1; mist.LightInfluence=0.8
	mist.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.18,0.3),NumberSequenceKeypoint.new(0.8,0.34),NumberSequenceKeypoint.new(1,1)})
	mist.Enabled=false; mist.Parent=anchor; stormMist=mist
	local rain=Instance.new("ParticleEmitter"); rain.Name="StormRain"; rain.Texture="rbxasset://textures/particles/smoke_main.dds"
	rain.Rate=340; rain.Lifetime=NumberRange.new(0.45,0.75); rain.Speed=NumberRange.new(0,0); rain.Acceleration=Vector3.new(0,-230,0)
	rain.EmissionDirection=Enum.NormalId.Top; rain.SpreadAngle=Vector2.new(10,10)
	rain.Size=NumberSequence.new(0.5); rain.Color=ColorSequence.new(SOUR_STORM.RAIN)
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
			-- ⚠ THE SKY GOES DARK GREEN HERE, and it is deliberately NOT the saved original.
			--
			-- This branch used to restore savedAtmos, which is the ordinary sky -- so landing during a
			-- sour storm gave you a normal blue horizon with green fog in front of it, and the storm
			-- stopped at eye level. The flying half already reads as sour because it is a solid wall of
			-- FOG_F; this is the half you actually LOOK at, standing on an island watching it roll over.
			--
			-- savedAtmos is still kept untouched and is still what endStorm restores. The original sky
			-- comes back when the storm ends, not when you land in the middle of one.
			TweenService:Create(stormAtmos, TweenInfo.new(t or 1.1, Enum.EasingStyle.Sine), {
				Density = SOUR_STORM.SKY_DENSITY,
				Haze    = SOUR_STORM.SKY_HAZE,
				Color   = SOUR_STORM.SKY,
				Decay   = SOUR_STORM.SKY,
				Glare   = 0,
				Offset  = 0,
			}):Play()
			print("[Storm] LANDED: Atmosphere re-attached in SOUR GREEN -> island visible under a green sky")
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
			drop.BackgroundColor3=SOUR_STORM.RAIN2D; drop.BackgroundTransparency=0.3
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
			local drop=Instance.new("Part"); drop.Name="RainDrop"; drop.Size=Vector3.new(0.05,2,0.05); drop.Color=SOUR_STORM.RAIN
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
	startGlowPulse(SOUR_STORM.KEY)
	showEventBanner("\xe2\x9b\x88 SOUR STORM","\xe2\x98\xa0 The sky has gone sour -- hold on tight!",SOUR_STORM.KEY)
	countPill.BackgroundColor3=SOUR_STORM.KEY; showCountPillAfterBanner(function() return _G.thunderstormActive end)
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
			countLabel.Text="\xe2\x9b\x88 SOUR STORM: "..rem.."s"
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
	countPill.BackgroundColor3=Color3.fromRGB(0,200,220); showCountPillAfterBanner(function() return _G.windstormActive end)
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
-- ⚠ THIS BLOCK NEVER RAN IN CANDY REALM. It read _G.ServerEventNotify, which is published by the Food realm's
-- CoreClient -- a script that does not exist here. The global was always nil, so `if ServerEventNotify then`
-- was always false and every branch below (the banner, the countdown pill, the glow pulse, SUGAR RUSH, COIN
-- RUSH, HIGH GRAVITY, POWER SURGE, RING FEVER, the storm and the meteor) was dead code in this realm.
--
-- It now resolves the remote ITSELF: the global first, so the Food realm's copy of this file is unaffected,
-- then ReplicatedStorage directly. ServerEvents.server.lua creates that remote on boot -- before this, it did
-- not exist in Candy at all, which is why MusicDucking's WaitForChild for it always timed out too.
local ServerEventNotify = _G.ServerEventNotify
	or game:GetService("ReplicatedStorage"):WaitForChild("ServerEventNotify", 30)
if ServerEventNotify then
	_G.ServerEventNotify = ServerEventNotify -- publish for anything else in this realm that expects the global
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
			countPill.BackgroundColor3=eventColor; showCountPillAfterBanner(function() return _G.serverEventActive end)

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
						-- FART SOUNDS DISABLED FOR NOW: don't play the ambient event fart loop.
						-- if hrpNow then local sa=hrpNow:FindFirstChild("FartAmbientSound"); if sa then pcall(function() sa:Play() end) end end
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


-- ============================================================================================================
-- /thunderstorm  --  fire the storm on demand
-- ============================================================================================================
-- BigEvents puts SOUR STORM on a rotation that starts 420s into a server and repeats every 600s. That is the
-- right pacing for players and the wrong pacing for looking at it: tuning the fog, the wind or the lightning
-- meant sitting through seven minutes per attempt, per change.
--
-- It lives HERE rather than in a command script of its own because startThunderstorm and startWindstorm are
-- locals in this file. Reaching them from outside would mean publishing two more globals for a test command,
-- and a global is a permanent public surface bought for a temporary convenience.
--
-- ⚠ CLIENT-SIDE ONLY, ON PURPOSE. This runs the storm on YOUR screen; it does not broadcast, so it cannot be
-- used to force weather on a live server. The real event still comes from BigEvents on the server. Same shape
-- as SummitBellQuest's /blizzard and DoneCommand's /done -- a local rehearsal of a server-owned thing.
--
--     /thunderstorm [seconds]   -- default 30, matching BigEvents' SOUR STORM
--     /windstorm                -- the other half of the weather pair
--     /stormend                 -- stop either one early
-- ============================================================================================================
do
	local TextChatService = game:GetService("TextChatService")
	local plr = game:GetService("Players").LocalPlayer

	local function onStormCommand(msg)
		local m = tostring(msg or ""):lower():gsub("^%s+", "")
		if m:sub(1, 13) == "/thunderstorm" then
			local secs = tonumber(m:match("(%d+)")) or 30
			print(("[EventClient] /thunderstorm -- running SOUR STORM locally for %ds"):format(secs))
			pcall(startThunderstorm, secs)
		elseif m:sub(1, 10) == "/windstorm" then
			print("[EventClient] /windstorm -- running SUGAR GALE locally")
			pcall(startWindstorm)
		elseif m:sub(1, 9) == "/stormend" then
			print("[EventClient] /stormend -- storm stopped")
			pcall(endEvent)
		end
	end

	-- Both chat routes, like every other command in this realm (/done, /island<N>, /reveal, /npc).
	pcall(function()
		TextChatService.MessageReceived:Connect(function(m)
			if m.TextSource and m.TextSource.UserId == plr.UserId then onStormCommand(m.Text) end
		end)
	end)
	pcall(function() plr.Chatted:Connect(onStormCommand) end)
	print("[EventClient] /thunderstorm [secs], /windstorm and /stormend ready (local rehearsal -- the real "
		.. "one is BigEvents' SOUR STORM on the server rotation)")
end

print("CHUNK 2 DONE")
