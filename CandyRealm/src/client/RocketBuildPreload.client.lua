--======================================================================
-- RocketBuildPreload.client.lua  (LocalScript)
--======================================================================
-- MOBILE-RELIABILITY helper for the ROCKET event's 3D BUILD STAGE only.
--
-- The build content (the EventRocket model, the 3 R15 "RocketWorker_*" NPCs, and the RocketSiteDressing)
-- is created on the SERVER and parented to Workspace, so it already replicates to every client. The
-- mobile problem is ASSET LOADING, not replication: the R15 worker rigs (avatar body meshes) and their
-- walk/idle animations are asset-backed, and mobile downloads those slowly/on-demand — so on phones the
-- workers can render blank or appear late while the build runs. Plain Parts (rocket/dressing) need no
-- assets. This script forces those rocket-build assets to load up front via ContentProvider:PreloadAsync
-- so they're ready the moment the build phase starts on mobile.
--
-- SCOPE: this ONLY preloads rocket-build assets. It does NOT touch the rocket GUI/banner/countdown/
-- teleport button, the rocket sounds, the launch/flight/explosion code, any other event, or any game
-- system. It reads the RocketEventSync RemoteEvent (the same one the GUI listens to) only to know when
-- a build is starting.
--======================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")
local Workspace         = game:GetService("Workspace")

-- Worker animation ids — MUST match RocketNPCs.lua (WALK_ANIM_ID / IDLE_ANIM_ID). Preloaded at join so
-- the workers animate immediately on mobile instead of T-posing/stuttering while the anim loads.
local WORKER_ANIM_IDS = { "rbxassetid://913402848", "rbxassetid://507766388" }

-- The server-created Workspace containers for the rocket build (see RocketLogic / RocketNPCs).
local BUILD_CONTAINER_NAMES = { "RocketEventNPCs", "EventRocket", "RocketSiteDressing" }

-- 1) Preload the worker animations ONCE at join (cheap; ready before any event fires).
task.spawn(function()
	local anims = {}
	for _, id in ipairs(WORKER_ANIM_IDS) do
		local a = Instance.new("Animation"); a.AnimationId = id; anims[#anims + 1] = a
	end
	pcall(function() ContentProvider:PreloadAsync(anims) end)
	for _, a in ipairs(anims) do a:Destroy() end
end)

-- 2) When a rocket event STARTS, wait for the server to spawn + replicate the build containers, then
--    force-load their assets (the R15 rig meshes especially) so they render promptly on mobile.
local function preloadBuildContent()
	task.spawn(function()
		local seen = {}
		local toLoad = {}
		local deadline = os.clock() + 25  -- covers the build phase; the workers spawn right at "start"
		while os.clock() < deadline do
			for _, name in ipairs(BUILD_CONTAINER_NAMES) do
				local inst = Workspace:FindFirstChild(name)
				if inst and not seen[inst] then
					seen[inst] = true
					toLoad[#toLoad + 1] = inst
					-- Force this container's asset-backed descendants (R15 rig meshes, decals, etc.) to load.
					pcall(function() ContentProvider:PreloadAsync({ inst }) end)
				end
			end
			task.wait(0.5)
		end
		-- Re-run once at the end in case late descendants were added during the staged build.
		if #toLoad > 0 then pcall(function() ContentProvider:PreloadAsync(toLoad) end) end
	end)
end

local sync = ReplicatedStorage:WaitForChild("RocketEventSync", 60)
if sync then
	sync.OnClientEvent:Connect(function(phase)
		if phase == "start" then preloadBuildContent() end
	end)
end

-- 3) Safety for a client that JOINS mid-build: if the containers are already present, preload them now.
preloadBuildContent()
