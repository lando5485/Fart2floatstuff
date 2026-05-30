--======================================================================
-- RainbowBeamUI.client.lua  (LocalScript)
--======================================================================
-- Client listener for the "RAINBOW BEAMS" hazard.
--
-- ★ This script does NOT compute the rewind. ★ The whole hit response --
-- restoring the launch fart meter + blasting the player back to the launch
-- island -- is the PRE-BUILT CoreClient function `_G.applyBeamHit()`. The
-- server (RainbowBeamManager) detects the beam collision and fires
-- RainbowBeamSync:FireClient(player, "hit"); this handler simply calls
-- `_G.applyBeamHit()` (skipping if a rewind is already in progress).
--
-- It also shows lightweight presentation: an optional floating text + a very
-- brief rainbow-tinted screen flash. Nothing here touches meter/flight/etc.
--======================================================================

-- Wait until CoreClient has defined _G.applyBeamHit / _G.beamBlasting (it
-- sets _G.CoreClientReady once those globals exist), mirroring EventClient.
repeat task.wait() until _G.CoreClientReady

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local RainbowBeamSync = ReplicatedStorage:WaitForChild("RainbowBeamSync")

--======================================================================
-- A tiny rainbow-tinted full-screen flash for hit feedback. Its own
-- ScreenGui so it never interferes with other UI. Starts invisible.
--======================================================================
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "RainbowBeamFlashGui"
flashGui.ResetOnSpawn = false
flashGui.IgnoreGuiInset = true
flashGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
flashGui.Parent = PlayerGui

local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.new(1, 0, 1, 0)
flashFrame.BackgroundColor3 = Color3.fromRGB(255, 120, 255)
flashFrame.BackgroundTransparency = 1   -- invisible until a hit
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 30
flashFrame.Parent = flashGui

-- screenFlash(): a quick rainbow-pink flash that fades back to clear.
local function screenFlash()
	flashFrame.BackgroundTransparency = 0.45
	TweenService:Create(flashFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = 1 }):Play()
end

--======================================================================
-- Sync handler. The server sends a string action; "hit" => run the rewind.
--======================================================================
RainbowBeamSync.OnClientEvent:Connect(function(action)
	if action == "hit" then
		-- Guard: if a rewind is already running, skip (the server also
		-- debounces, so this is belt-and-braces).
		if _G.beamBlasting then return end
		if not _G.applyBeamHit then return end

		-- Optional presentation cues (only if the globals/functions exist).
		if _G.showFloatingText then
			_G.showFloatingText("\u{1F308} Beam hit! Flight rewound!", Color3.fromRGB(255, 120, 255))
		end
		screenFlash()

		-- Run the PRE-APPROVED snapshot/restore. This is the only effect.
		_G.applyBeamHit()
	end
end)
