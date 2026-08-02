-- ============================================================================================================
-- AMBIENT SMOKE & STEAM  (client)
--
-- Vertical motion is the cheapest "this place is real" trick there is. A perfectly still scene reads as a
-- rendering; the same scene with something rising out of it reads as a world with weather and heat in it. Smoke
-- does more for a landscape than almost any amount of extra geometry.
--
-- Each landmark gets the plume it should have:
--
--     Bean Farm (SmokeBrick)   chimney smoke -- slow, lazy, leaning in the breeze
--     Toaster (Bread Board)    hot, fast, thin wisps -- it is a giant toaster, it should look like it is working
--     Milk Marsh               a thick, cold, ground-hugging mist -- the opposite of the toaster in every way
--     Popcorn trees            quick pops of steam
--     Meatball shooter         hot exhaust
--     Community Garden         soft pollen / dust drifting through the light
--
-- Butter Swamp deliberately gets NOTHING. A haze over the lake obscured the thing you actually go there to do.
--
-- ===== IT DOES NOT ASSUME ANY OF THEM EXIST =====
-- These landmarks are built by six different scripts, at different times, some of them minutes after join. So this
-- POLLS for each by name and attaches when it appears, and it says in the log exactly which ones it found and
-- which it did not -- so a missing plume is a one-line diagnosis instead of a hunt.
--
-- Client-side: particles are simulated per-client anyway, so putting the emitters on the server would replicate
-- instances for no benefit whatsoever.
-- ============================================================================================================

local Workspace = game:GetService("Workspace")

-- Each entry: the NAME to look for, and how its plume should behave. Everything about a plume that matters is in
-- these numbers -- rate, speed, drift, lifetime, size, colour -- so a new landmark is one table row, not new code.
local PLUMES = {
	{
		-- CHIMNEY SMOKE. A part named "SmokeBrick", placed by hand on Bean Farm -- so the plume goes exactly where
		-- you want it rather than wherever a script guessed.
		--
		-- Tuned as a real chimney, which is slower and lazier than people expect: a LOW rate, a slow rise, a strong
		-- sideways drift, and a long lifetime so it lingers and thins out instead of vanishing. Smoke that fires
		-- fast and dies quickly reads as a smoke MACHINE; smoke that hangs around and drifts reads as a fire that
		-- has been burning a while.
		-- HIDE THE BRICK. It is a MARKER, not scenery -- it exists only to say "put the smoke here", so a grey box
		-- floating on the roof would be the one part of this the player actually notices.
		--
		-- Only its VISIBILITY is touched. Collision is deliberately left exactly as you set it: this brick may well
		-- be part of a roof or a chimney stack, and silently turning off CanCollide could drop a player through the
		-- building. If you want it non-solid, that is a decision for Studio, not for a smoke script.
		-- NOTE: this one is now left VISIBLE (hideHost = false). It is real scenery -- a chimney stack you can see --
		-- so hiding it would delete the thing the smoke is supposed to be coming out of. Its twin, SmokeBrick1
		-- below, IS a pure marker and stays hidden.
		hideHost = false,
		find = "SmokeBrick", label = "chimney smoke (Bean Farm)",
		-- DARKER AND THICKER. Three separate levers, all pulled -- one on its own would not have been enough:
		--   * RATE 7 -> 16      : twice as many puffs, so it is a continuous column instead of a dotted line
		--   * TRANS 0.45 -> 0.12: nearly opaque at its densest. The old value was see-through and washed out
		--                         against a bright sky, which is where this smoke actually lives.
		--   * COLOUR            : starts a dirty grey rather than near-white, and DARKENS as it rises. Real smoke
		--                         from a wood fire is sooty at the source; near-white reads as steam, not smoke.
		rate = 16, speed = { 1.2, 2.6 }, lifetime = { 4.5, 8 }, spread = 14,
		accel = Vector3.new(1.6, 2.2, 0.6),             -- rises AND leans: a chimney in a breeze, not a rocket
		size = { 1.6, 11 },                             -- billows out wide as it climbs and cools
		trans = { 0.12, 1 },
		color = ColorSequence.new(Color3.fromRGB(120, 118, 122), Color3.fromRGB(64, 62, 68)),
		offsetY = 0.6,                                  -- just above the brick's top face
	},
	{
		-- SECOND CHIMNEY. Identical plume to the one above -- same rate, drift, colour and lifetime, so the two
		-- read as the same fire rather than two unrelated effects.
		--
		-- The difference is hideHost: THIS brick is a pure MARKER (it only exists to say "put smoke here"), so it
		-- is hidden. Its twin above is visible scenery and is left alone. Visibility only -- collision is not
		-- touched on either, since a marker may well be part of a roof and silently un-soliding it could drop a
		-- player through the building.
		hideHost = true,
		find = "SmokeBrick1", label = "chimney smoke 2 (Bean Farm)",
		rate = 16, speed = { 1.2, 2.6 }, lifetime = { 4.5, 8 }, spread = 14,
		accel = Vector3.new(1.6, 2.2, 0.6),
		size = { 1.6, 11 },
		trans = { 0.12, 1 },
		color = ColorSequence.new(Color3.fromRGB(120, 118, 122), Color3.fromRGB(64, 62, 68)),
		offsetY = 0.6,
	},
	{
		find = "Toaster", label = "toaster steam",
		rate = 9, speed = { 5, 9 }, lifetime = { 1.4, 2.4 }, spread = 12,
		accel = Vector3.new(0.6, 6, 0),                 -- shoots UP: it is hot
		size = { 0.6, 5 }, trans = { 0.35, 1 },
		color = ColorSequence.new(Color3.fromRGB(250, 250, 250), Color3.fromRGB(210, 210, 215)),
		offsetY = 3,
	},
	-- (The Butter Lake haze was removed -- a warm haze over the whole lake did not read as heat, it read as fog
	-- sitting on top of the thing you are trying to fish in. Butter Swamp gets no plume.)
	{
		area = true, find = "MilkCap", label = "milk marsh mist",
		rate = 16, speed = { 0.3, 1 }, lifetime = { 5, 9 }, spread = 60,
		accel = Vector3.new(0.4, 0.25, 0.2),            -- HANGS at ground level. Cold mist does not climb.
		size = { 8, 22 }, trans = { 0.86, 1 },
		color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(230, 238, 245)),
		offsetY = 2,
	},
	{
		find = "PopTree1", label = "popcorn steam (tree 1)",
		rate = 4, speed = { 2, 4 }, lifetime = { 1, 2 }, spread = 25,
		accel = Vector3.new(0, 3.5, 0),
		size = { 0.5, 3 }, trans = { 0.5, 1 },
		color = ColorSequence.new(Color3.fromRGB(255, 250, 235)),
		offsetY = 6,
	},
	{
		find = "PopTree2", label = "popcorn steam (tree 2)",
		rate = 4, speed = { 2, 4 }, lifetime = { 1, 2 }, spread = 25,
		accel = Vector3.new(0, 3.5, 0),
		size = { 0.5, 3 }, trans = { 0.5, 1 },
		color = ColorSequence.new(Color3.fromRGB(255, 250, 235)),
		offsetY = 6,
	},
	{
		find = "Meatballshooter", label = "meatball shooter exhaust",
		rate = 5, speed = { 1.5, 3.5 }, lifetime = { 1.4, 2.6 }, spread = 20,
		accel = Vector3.new(0.4, 3, 0),
		size = { 1, 4 }, trans = { 0.55, 1 },
		color = ColorSequence.new(Color3.fromRGB(140, 130, 125), Color3.fromRGB(90, 84, 80)),
		offsetY = 2.5,
	},
	{
		area = true, find = "CommunityGardenBuild", label = "garden pollen",
		rate = 10, speed = { 0.3, 1.2 }, lifetime = { 6, 11 }, spread = 90,
		accel = Vector3.new(0.7, 0.4, 0.2),             -- drifts sideways more than up -- it is pollen, not smoke
		size = { 0.3, 0.8 }, trans = { 0.72, 1 },
		color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(230, 255, 190)),
		offsetY = 8,
	},
}

local function seq2(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- Transparency has to FADE IN as well as out. A puff that appears at full opacity and then fades looks like it was
-- switched on; one that fades in from nothing looks like it condensed out of the air.
local function fadeSeq(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, peak),
		NumberSequenceKeypoint.new(0.65, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- How tall a part is IN WORLD SPACE. Not Size.Y -- that is its LOCAL height, and the two are only the same for a
-- part that is not rotated. This is the standard world-AABB half-extent: project each of the part's three local
-- axes onto world Y and add up how much each contributes.
local function worldHalfHeight(part)
	local cf, sz = part.CFrame, part.Size
	return 0.5 * (
		math.abs(cf.RightVector.Y) * sz.X +
		math.abs(cf.UpVector.Y)    * sz.Y +
		math.abs(cf.LookVector.Y)  * sz.Z
	)
end

-- One plume per part, ever. Both the named specs and the Bean Farm chimney sweep below funnel through attach(),
-- and the stale places this game finds parts in (recursive FindFirstChild, a rescan after an event) can hand the
-- same brick over twice. Claimed hosts are refused, so a chimney never gets two overlapping columns.
local claimed = {}

local attach
function attach(spec, target)
	local host = target
	if target:IsA("Model") then
		host = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	end
	if not (host and host:IsA("BasePart")) then return false end
	if claimed[host] then return false end

	-- ===== WHERE THE PLUME STARTS =====
	-- Two bugs lived here, and both of them put the smoke UNDER the brick instead of on top of it:
	--
	--   1. The offset used to be `host.CFrame * CFrame.new(0, Size.Y/2, 0)` -- i.e. along the BRICK'S OWN up axis.
	--      Tilt or turn the brick and its local "up" is no longer world up, so the anchor slid sideways or, on a
	--      brick lying flat, straight DOWN into the ground. The lift is now measured in WORLD space, so however the
	--      brick is rotated, the smoke leaves the top of it.
	--
	--   2. The anchor was a 1x1x1 cube, and a ParticleEmitter fires from a part's whole VOLUME -- so half of every
	--      puff was born below the anchor's centre, i.e. inside the brick. The anchor is now a thin plate, so the
	--      puffs are born ON the surface and go up from there.
	-- Marker parts (the SmokeBrick) are hidden, since they exist only to position the plume. Landmarks that are
	-- real scenery (the toaster, the marsh, the garden) obviously are not -- hence the per-plume flag.
	if spec.hideHost then
		host.Transparency = 1
		host.CastShadow = false
		for _, d in ipairs(host:GetDescendants()) do
			if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
		end
		-- Belt and braces: something else in the game may set Transparency later (a material pass, a streaming
		-- reload). Re-hide it if anything makes it visible again.
		host:GetPropertyChangedSignal("Transparency"):Connect(function()
			if host.Transparency < 1 then host.Transparency = 1 end
		end)
		print("[Smoke] hid the marker part '" .. host.Name .. "' (collision left untouched)")
	end

	local anchor = Instance.new("Part")
	anchor.Name = "PlumeAnchor"
	anchor.Transparency = 1
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false
	anchor.CastShadow = false

	-- AREA plumes (a lake, a marsh, the whole garden) must emit across the landmark's footprint -- a haze rising
	-- from a single point in the middle of a lake looks like a bonfire. POINT plumes (a chimney, a toaster) emit
	-- from one spot, which is exactly what a chimney is.
	if spec.area then
		local sz = host.Size
		anchor.Size = Vector3.new(math.min(sz.X, 220), 0.2, math.min(sz.Z, 220))
	else
		anchor.Size = Vector3.new(0.4, 0.2, 0.4) -- thin plate: puffs start ON the surface, never inside it
	end

	-- Positioned with NO rotation, so the emitter's Top face is genuinely world-up regardless of how the landmark
	-- happens to be turned.
	anchor.CFrame = CFrame.new(
		host.Position.X,
		host.Position.Y + worldHalfHeight(host) + spec.offsetY,
		host.Position.Z
	)
	anchor.Parent = Workspace

	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = spec.rate
	e.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	e.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2])
	e.SpreadAngle = Vector2.new(spec.spread, spec.spread)
	e.Acceleration = spec.accel
	e.Size = seq2(spec.size[1], spec.size[2])       -- puffs EXPAND as they rise -- smoke that keeps its size is fake
	e.Transparency = fadeSeq(spec.trans[1])
	e.Color = spec.color
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-12, 12)           -- slow tumble; without it every puff is the same sprite

	-- ===== SAME FROM EVERY ANGLE, AND IT NEVER STOPS =====
	--
	-- ORIENTATION: FacingCamera makes every puff a flat sprite that always turns to face you. That is what makes the
	-- column look identically thick whether you are in front of it, beside it, or looking down on it from a flight.
	-- Left to any other mode, the puffs are billboards with a FIXED axis and you can catch them edge-on -- which is
	-- exactly the "it gets thin from over there" effect. It is the default, but it is set EXPLICITLY here because it
	-- is load-bearing and a default is not a decision.
	e.Orientation = Enum.ParticleOrientation.FacingCamera

	-- LIGHTING: LightInfluence 1 means the world lights the smoke, so the SUN'S ANGLE changes how bright it looks --
	-- dark and heavy with the sun behind it, washed out with the sun behind you. That is realistic and it is exactly
	-- what makes it look inconsistent as you fly around it. Dropping it to 0.45 and adding a little self-emission
	-- keeps it looking like the SAME smoke from every side, at every time of day.
	e.LightInfluence = 0.45
	e.LightEmission = 0.08

	-- ALWAYS ON. Never gated on distance, never toggled: a chimney does not stop smoking because nobody is standing
	-- next to it, and a plume that pops into existence as you approach is worse than no plume.
	e.Enabled = true
	e.ZOffset = 0.4 -- nudge the puffs toward the camera so the roof/brick cannot z-fight through the column
	e.LockedToPart = false                          -- puffs are left behind in the air rather than dragged along
	e.Parent = anchor
	claimed[host] = true

	-- INSTANT re-enable. Big events / thunderstorms flip ambient emitters OFF; the once-a-second watchdog below
	-- would leave a visible gap. This fires the MOMENT anything disables it (or zeroes its rate) and turns it
	-- straight back on, so the chimney smoke keeps pouring through every event with no interruption.
	local wantRate = e.Rate
	e:GetPropertyChangedSignal("Enabled"):Connect(function()
		if e.Parent and not e.Enabled then e.Enabled = true end
	end)
	e:GetPropertyChangedSignal("Rate"):Connect(function()
		if e.Parent and e.Rate < wantRate then e.Rate = wantRate end
	end)

	-- KEEP-ALIVE. The anchor is a loose Part in Workspace, and plenty of things in this game sweep Workspace --
	-- the garden nukes and rebuilds itself, SecurityGuard scans for inserted instances, streaming reloads chunks.
	-- If anything destroys the anchor or switches the emitter off, put it back. Checked once a second: far too
	-- cheap to matter, and it turns "the smoke mysteriously stopped after ten minutes" into a non-event.
	task.spawn(function()
		-- ===== WATCHDOG: the plumes must ALWAYS be running =====
		-- Big events (meteor, rocket, rainbow beam), the community garden's "rebuild fresh" pass, and streaming
		-- reloads all destroy and RECREATE parts. Two distinct ways a plume dies, and both are handled here:
		--
		--   1. The ANCHOR is destroyed  -> no more particles at all.
		--   2. The HOST is destroyed    -> the anchor survives, ANCHORED at a fixed CFrame, so the smoke keeps
		--      pouring out of thin air where the brick used to be. Arguably worse than no smoke.
		--
		-- On either, we tear down and RE-RESOLVE THE HOST BY NAME. The previous version re-attached to the old
		-- `target` reference -- but if an event destroyed and rebuilt that part, `target` is a dangling instance
		-- with no parent, so it would rebuild the plume onto a corpse.
		while true do
			task.wait(1)
			local hostAlive   = host.Parent ~= nil and host:IsDescendantOf(Workspace)
			local anchorAlive = anchor.Parent ~= nil

			if hostAlive and anchorAlive then
				if not e.Enabled then e.Enabled = true end -- something disabled it; turn it back on
			else
				local why = (not anchorAlive) and "anchor destroyed" or "host destroyed"
				print(("[Smoke] '%s' died (%s) -- re-resolving '%s'"):format(spec.label, why, spec.find))
				if anchor.Parent then anchor:Destroy() end -- kill the orphan so it can't smoke from mid-air

				-- Wait for the part to come back. A garden rebuild or an event takes a moment to put the world
				-- back together, so give it a long window rather than giving up on the first miss.
				task.spawn(function()
					for _ = 1, 600 do
						local fresh = Workspace:FindFirstChild(spec.find, true)
						if fresh and attach(spec, fresh) then
							print("[Smoke] '" .. spec.label .. "' re-attached")
							return
						end
						task.wait(1)
					end
					warn("[Smoke] '" .. spec.label .. "' never came back after 10 min -- '" .. spec.find .. "' is gone")
				end)
				return -- this watchdog's job is done; the new attach() spawns its own
			end
		end
	end)

	return true
end

task.spawn(function()
	local pending = {}
	for _, spec in ipairs(PLUMES) do pending[#pending + 1] = spec end

	-- Landmarks appear over the first couple of minutes as their owning scripts build them. Keep looking, and
	-- report ONCE at the end -- so the log is a single verdict, not a wall of retries.
	for _ = 1, 240 do
		for i = #pending, 1, -1 do
			local spec = pending[i]
			local target = Workspace:FindFirstChild(spec.find, true)
			if target and attach(spec, target) then
				print("[Smoke] attached " .. spec.label)
				table.remove(pending, i)
			end
		end
		if #pending == 0 then break end
		task.wait(1)
	end

	if #pending > 0 then
		local missing = {}
		for _, spec in ipairs(pending) do missing[#missing + 1] = spec.find end
		warn("[Smoke] never found: " .. table.concat(missing, ", ")
			.. " -- no plume on those. (Names are matched exactly; tell me the real name and it is a one-line fix.)")
	end
	print(("[Smoke] ready -- %d/%d plumes attached"):format(#PLUMES - #pending, #PLUMES))
end)

-- ============================================================================================================
-- BEAN FARM CHIMNEY SWEEP
--
-- The two named bricks above (SmokeBrick / SmokeBrick1) are matched EXACTLY -- but chimney blocks get renamed
-- and duplicated in Studio ("smoke", "Smoke2", "smoke brick", ...), and a renamed chimney silently gets no
-- plume while the log still says "attached" (to the OLD marker). So on top of the named specs, sweep Bean Farm
-- for ANY part or model with "smoke" in its name and give each one the standard chimney plume.
--
-- Scoped to the Island_1 model only, so a "smoke" prop on some other island doesn't suddenly become a chimney.
-- Hosts are real scenery, so they stay visible; the claimed-set in attach() stops double plumes on the two
-- bricks the named specs already handled.
-- ============================================================================================================
task.spawn(function()
	local CHIMNEY = {
		hideHost = false,
		rate = 16, speed = { 1.2, 2.6 }, lifetime = { 4.5, 8 }, spread = 14,
		accel = Vector3.new(1.6, 2.2, 0.6),
		size = { 1.6, 11 },
		trans = { 0.12, 1 },
		color = ColorSequence.new(Color3.fromRGB(120, 118, 122), Color3.fromRGB(64, 62, 68)),
		offsetY = 0.6,
	}

	-- "^island_1%D" and not just "^island_1": Island_10..14 also start with "island_1".
	local function beanFarm()
		for _, m in ipairs(Workspace:GetChildren()) do
			if m:IsA("Model") and string.lower(m.Name):match("^island_1%D") then return m end
		end
		return nil
	end

	local found = 0
	for _ = 1, 120 do -- keep sweeping for 2 minutes: the island streams/positions late on join
		local isl = beanFarm()
		if isl then
			for _, d in ipairs(isl:GetDescendants()) do
				if (d:IsA("BasePart") or d:IsA("Model")) and d.Name ~= "PlumeAnchor" then
					local n = string.lower(d.Name)
					if n:find("smoke", 1, true) then
						local spec = table.clone(CHIMNEY)
						spec.find = d.Name -- the watchdog re-resolves by this name after events/rebuilds
						spec.label = ("chimney smoke ('%s')"):format(d.Name)
						if attach(spec, d) then
							found += 1
							print("[Smoke] chimney sweep attached " .. spec.label)
						end
					end
				end
			end
		end
		task.wait(2)
	end
	print(("[Smoke] chimney sweep done -- %d extra chimney(s) smoking on Bean Farm"):format(found))
end)
