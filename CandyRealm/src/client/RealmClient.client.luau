--!nonstrict
--[[
	RealmClient.client.luau  —  the new realm's main client script (starter).

	Runs on the player in the NEW realm's place. Put this realm's HUD / UI / input here.
	ROUTED BY: NewRealm/default.project.json -> StarterPlayerScripts.RealmClient
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---- your realm UI / feedback goes here ----

print("[NewRealm] client ready")
