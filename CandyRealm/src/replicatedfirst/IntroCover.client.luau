--======================================================================
-- IntroCover.client.luau  (ReplicatedFirst)  -- CandyRealm
--======================================================================
-- THE INTRO IS THE FIRST THING THE PLAYER SEES. This is what guarantees it.
--
-- ===== WHY THIS IS NOT IN Intro.client.luau =====
-- Intro owns the cinematic and it already builds a black pre-roll cover -- but it lives in
-- StarterPlayerScripts, and it builds that cover AFTER four WaitForChild calls (IntroPlay,
-- IntroDone, IntroFocus, IntroArm, 30s each). Two consequences, both visible in the boot log:
--
--   * StarterPlayerScripts does not run until the character and the world are already loading,
--     so the first frames of the session are the world, not the intro. The log has the intro
--     starting TWELVE SECONDS after the client came up, by which time NpcGuideArrow had already
--     announced two island arrivals -- the player watched the map before the film began.
--   * If any of those four remotes is slow, the cover is late by exactly that much. A cover that
--     arrives late is worse than no cover: the player sees the world, then it goes black.
--
-- ReplicatedFirst is the only place in Roblox that runs BEFORE the rest of the game replicates,
-- which is precisely the guarantee needed here. So the black goes up here, on the very first
-- frame this client executes anything, and Intro ADOPTS it rather than building its own.
--
-- ===== IT CAN NEVER STRAND ANYONE ON BLACK =====
-- A permanent black screen is the worst bug this file could have, so it owns its own way out:
-- HARD_TIMEOUT fades the cover no matter what, even if Intro never loads, errors, is stripped
-- from the place, or the server never speaks. Intro taking over cancels that only in the sense
-- that Intro then owns the cut -- the timeout still fires if the intro never actually starts.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

local HARD_TIMEOUT = 25   -- seconds. Longer than any real intro pre-roll, shorter than a player's patience.

-- Roblox's own loading screen sits over ours and is removed the moment the game finishes loading;
-- taking it down ourselves means OUR black is continuous from that instant, with no single frame
-- of world in between. This is the whole reason ReplicatedFirst exists.
pcall(function() ReplicatedFirst:RemoveDefaultLoadingScreen() end)

local gui = Instance.new("ScreenGui")
gui.Name = "IntroPreRoll"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9000    -- under ArrivalCinematic's 10000, over everything else
gui.Parent = player:WaitForChild("PlayerGui")

local black = Instance.new("Frame")
black.Name = "Black"
black.Size = UDim2.new(1, 0, 1, 0)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 0   -- opaque from frame one
black.BorderSizePixel = 0
black.Parent = gui

local done = false

-- CUT, do not fade: the next thing on screen is the cinematic's opening slam, and fading into a
-- slam is the one thing that robs it of its impact. (Intro made this argument first; it is right.)
local function cut()
	if done then return end
	done = true
	pcall(function() gui:Destroy() end)
end

-- FADE: no cinematic is coming, so this reads as a load screen ending rather than a light being
-- switched on.
local function fade()
	if done then return end
	done = true
	pcall(function()
		TweenService:Create(black, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end)
	task.delay(0.45, function() pcall(function() gui:Destroy() end) end)
end

-- Published for Intro.client.luau, which adopts this instead of building a second cover. `taken`
-- lets Intro tell whether a cover already exists without having to care where it came from.
_G.introCover = {
	gui = gui,
	cut = cut,
	fade = fade,
	isDone = function() return done end,
}

-- THE BACKSTOP. Nothing about the intro is allowed to leave someone staring at black: if the
-- cinematic has not started by now, the player gets the world.
task.delay(HARD_TIMEOUT, function()
	if not _G.introPlaying then fade() end
end)

print(("[IntroCover] black up from frame one (ReplicatedFirst); Intro adopts it. Hard timeout %ds.")
	:format(HARD_TIMEOUT))
