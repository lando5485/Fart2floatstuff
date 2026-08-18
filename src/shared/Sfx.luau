--======================================================================
-- Sfx.luau  (ModuleScript, ReplicatedStorage.Shared)
--======================================================================
-- ONE PLACE FOR EVERY UI SOUND. click, confirm, deny, purchase, reward, levelup, whoosh, pop.
--
-- Right now almost nothing in this game makes a noise when you touch it. Buttons, purchases, menu opens and
-- refusals are all silent, and silence is the single biggest reason a finished game still feels unfinished --
-- audio is most of what people actually mean by "polish".
--
-- ===== THE PROBLEM THIS MODULE EXISTS TO SOLVE =====
-- Six sound ids in this place are broken. Straight from the boot log:
--     Failed to load sound rbxassetid://9116367700       Asset type does not match requested type
--     Failed to load sound rbxassetid://199578212        Asset type does not match requested type
--     Failed to load sound rbxassetid://1369158752       Asset type does not match requested type
--     Failed to load sound rbxassetid://3240498563       Asset type does not match requested type
--     Failed to load sound rbxassetid://9116458024       Asset type does not match requested type
--     Failed to load sound rbxassetid://101642229651469  Asset is not approved for the requester
-- So a sound module that just holds a list of ids would ship silent, exactly like the current code does, and
-- nobody would find out until a player complained.
--
-- ===== SO IT FALLS BACK, AND THE FALLBACK STILL SOUNDS DIFFERENT =====
-- Every cue names a PREFERRED id and a PlaybackSpeed/Volume shape. If the preferred id fails to load, the cue
-- is re-pointed at KNOWN_GOOD -- the one id CrateClient's own boot diagnostic reports loading successfully --
-- and PLAYED AT ITS OWN PITCH. A click at 1.8x and a deny at 0.55x are audibly different events even though
-- they are the same
-- recording, so the game still speaks to the player instead of going quiet. When you have real
-- assets, put their ids in CUES and the fallback stops being used; nothing else has to change.
--
-- ===== WHY IT PRELOADS AND REPORTS =====
-- ContentProvider tells us which ids resolved BEFORE anything tries to play, so the failures are known at boot
-- and printed once as a single readable line -- rather than discovered one broken button at a time.
--
-- USAGE (client):
--     local Sfx = require(ReplicatedStorage.Shared.Sfx)
--     Sfx.play("click")            -- or "confirm" / "deny" / "purchase" / "reward" / "levelup" / "whoosh" / "pop"
--     Sfx.button(someTextButton)   -- wires MouseButton1Click -> click, one line per button
--======================================================================

local ContentProvider = game:GetService("ContentProvider")
local SoundService    = game:GetService("SoundService")
local RunService      = game:GetService("RunService")
local Debris          = game:GetService("Debris")

local Sfx = {}

-- The only id in this place confirmed to load (CrateClient logs it as AssetFetchStatus.Success). Every cue
-- degrades to this rather than to silence.
Sfx.KNOWN_GOOD = "rbxassetid://4612378364"

--======================================================================
-- THE CUES
--======================================================================
-- id       : your preferred asset. Leave as KNOWN_GOOD (or set nil) to use the fallback deliberately.
-- speed    : PlaybackSpeed. This is what keeps the eight cues distinguishable when they all fall back to one
--            recording -- pitch is the cheapest way to say "different event".
-- volume   : per-cue, because a click that is as loud as a reward is a click nobody wants to hear twice.
-- cooldown : minimum seconds between two plays of THIS cue. Without it a repeat-firing signal (a coin tick,
--            a hover) machine-guns the sound and the effect turns into an irritant.
local CUES = {
	click    = { id = nil, speed = 1.75, volume = 0.28, cooldown = 0.05 }, -- any tap: small, dry, out of the way
	confirm  = { id = nil, speed = 1.30, volume = 0.45, cooldown = 0.06 }, -- yes / accepted / equipped
	deny     = { id = nil, speed = 0.55, volume = 0.40, cooldown = 0.10 }, -- refused: can't afford, stomach full
	purchase = { id = nil, speed = 1.00, volume = 0.55, cooldown = 0.06 }, -- money changed hands
	reward   = { id = nil, speed = 1.15, volume = 0.65, cooldown = 0.08 }, -- you were GIVEN something
	levelup  = { id = nil, speed = 1.45, volume = 0.70, cooldown = 0.10 }, -- a threshold was crossed
	whoosh   = { id = nil, speed = 0.80, volume = 0.35, cooldown = 0.06 }, -- panel opens / closes
	pop      = { id = nil, speed = 2.00, volume = 0.30, cooldown = 0.03 }, -- tiny: a chip lands, a token arrives
}

--======================================================================
-- RESOLVE
--======================================================================
local resolved = {}   -- [cue] = final sound id actually used
local lastPlay = {}   -- [cue] = os.clock() of the last play
local ready    = false

local function idFor(cue)
	local c = CUES[cue]
	if not c then return nil end
	return c.id or Sfx.KNOWN_GOOD
end

-- Preload every DISTINCT id once and record which survived. A cue whose preferred id failed is re-pointed at
-- KNOWN_GOOD but KEEPS its own speed/volume, so it stays a recognisably different cue.
local function resolveAll()
	if ready then return end
	ready = true

	local wanted, seen = {}, {}
	for cue in pairs(CUES) do
		local id = idFor(cue)
		if id and not seen[id] then seen[id] = true; wanted[#wanted + 1] = id end
	end

	local status = {}
	for _, id in ipairs(wanted) do
		local probe = Instance.new("Sound")
		probe.SoundId = id
		local ok = pcall(function() ContentProvider:PreloadAsync({ probe }) end)
		-- IsLoaded is the honest answer; PreloadAsync returns even for assets that resolved to nothing.
		status[id] = ok and probe.IsLoaded or false
		probe:Destroy()
	end

	local broken = {}
	for cue in pairs(CUES) do
		local id = idFor(cue)
		if id and status[id] then
			resolved[cue] = id
		else
			resolved[cue] = Sfx.KNOWN_GOOD
			if id and id ~= Sfx.KNOWN_GOOD then broken[#broken + 1] = cue .. "(" .. id .. ")" end
		end
	end

	if #broken > 0 then
		warn("[Sfx] these cues' ids did not load and fell back to the known-good sound at their own pitch: "
			.. table.concat(broken, ", "))
	end
	print(string.format("[Sfx] ready -- %d cues, fallback=%s%s",
		(function() local n = 0; for _ in pairs(CUES) do n = n + 1 end; return n end)(),
		Sfx.KNOWN_GOOD, (#broken > 0) and (", " .. #broken .. " using the fallback") or ""))
end

--======================================================================
-- PLAY
--======================================================================
-- Parented to SoundService, not to a part: these are UI cues and must not be positional, must not attenuate
-- with distance, and must not die when a character respawns mid-sound.
function Sfx.play(cue, volumeScale)
	local c = CUES[cue]
	if not c then warn("[Sfx] unknown cue '" .. tostring(cue) .. "'"); return end
	if not ready then resolveAll() end

	local now = os.clock()
	if lastPlay[cue] and (now - lastPlay[cue]) < (c.cooldown or 0) then return end
	lastPlay[cue] = now

	local ok = pcall(function()
		local s = Instance.new("Sound")
		s.Name = "Sfx_" .. cue
		s.SoundId = resolved[cue] or Sfx.KNOWN_GOOD
		s.Volume = (c.volume or 0.4) * (tonumber(volumeScale) or 1)
		s.PlaybackSpeed = c.speed or 1
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 6)
	end)
	if not ok then warn("[Sfx] failed to play '" .. cue .. "'") end
end

-- One-liner for wiring a button. Returns the connection so a caller can drop it if the button is rebuilt.
function Sfx.button(btn, cue)
	if not (btn and btn:IsA("GuiButton")) then return nil end
	if btn:GetAttribute("SfxWired") then return nil end -- never double-wire: two clicks per press is worse than none
	btn:SetAttribute("SfxWired", true)
	return btn.MouseButton1Click:Connect(function() Sfx.play(cue or "click") end)
end

-- Let callers retune at runtime (a settings slider, a "quiet mode") without reaching into the table.
function Sfx.setVolume(cue, v)
	local c = CUES[cue]; if c then c.volume = math.clamp(tonumber(v) or c.volume, 0, 2) end
end

-- Resolve on the client at require time so the first click is not the thing that pays for the preload.
if RunService:IsClient() then task.spawn(resolveAll) end

return Sfx
