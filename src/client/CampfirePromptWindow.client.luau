--======================================================================
-- CampfirePromptWindow.client.luau   (StarterPlayerScripts, LocalScript)
--======================================================================
-- THE "COZY CAMPFIRE / rest & warm up" SIGN: A TIMED WINDOW.
--
-- Walk into range of a campfire and its floating sign shows for SHOW_SECONDS, then hides -- so it stops
-- sitting over the NPC speech bubbles and the chat around the fire. Move anywhere you like INSIDE the
-- zone and it stays up for its full run: it is a pure timer, not a distance gate. Step outside the zone
-- and it hides at once and re-arms, so the next approach gets a fresh window.
--
-- ===== WHAT THIS DOES *NOT* TOUCH: THE MARSHMALLOW PROMPT =====
-- Earlier versions of this file windowed the "Take a Marshmallow" ProximityPrompt. That was the wrong
-- target: picking up a marshmallow is a thing you must always be able to see and do, so that prompt
-- stays on permanently. It is the SIGN -- pure decoration, and the tallest thing at the fire -- that
-- gets in the way and needs to go quiet.
--
-- Because those earlier builds may have left a prompt hidden (Style=Custom) or disabled in a live
-- session, this file actively RESTORES every marshmallow prompt to normal on load and then leaves them
-- alone forever. See restoreMarshmallowPrompts().
--
-- ===== WHY THIS IS ITS OWN FILE, AND NOT PART OF Campfire.client.luau =====
-- That file's duplicate guard has every copy DESTROY the other copies on load:
--
--     elseif inst ~= script and inst:IsA("LocalScript") and inst.Name == script.Name then
--         inst.Disabled = true; inst:Destroy()
--
-- There are stale copies of the campfire client baked into the place, so whenever one of them won the
-- load race it deleted the freshly-synced Rojo script and none of the new code ran. A version check
-- inside that file cannot help -- a guard in a destroyed script never executes. Those copies only hunt
-- for LocalScripts named "Campfire", so a different filename is immune, which is why this lives here.
--
-- Everything here is CLIENT-LOCAL: BillboardGui.Enabled written from a LocalScript changes only this
-- player's view. Every other player's sign is untouched.
--======================================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local BUILD = 2   -- 2 = windows the SIGN (build 1 wrongly windowed the marshmallow prompt)
if (_G.__CampfirePromptWindowBuild or 0) >= BUILD then return end
_G.__CampfirePromptWindowBuild = BUILD

local SHOW_SECONDS = 4          -- how long the sign stays up per approach
local FALLBACK_ZONE = 45        -- used only if a sign reports no MaxDistance (matches the server's 45)

-- ===== PUT THE MARSHMALLOW PROMPT BACK =====
-- Build 1 of this script hid that prompt (Style=Custom, and in one revision Enabled=false /
-- MaxActivationDistance=0). Those writes are client-local but they persist for the whole session, so a
-- player who joined under the old build could be left unable to see or take a marshmallow. Restore the
-- authored state, repeatedly for the first minute while the campfires are still being built, then never
-- touch these again.
local function restoreMarshmallowPrompts()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "TakeMarshmallowStick" then
			local base = d:GetAttribute("F2FBaseDist")
			if base and base > 0 and d.MaxActivationDistance ~= base then d.MaxActivationDistance = base end
			if d.MaxActivationDistance <= 0 then d.MaxActivationDistance = 12 end
			if d.Style ~= Enum.ProximityPromptStyle.Default then d.Style = Enum.ProximityPromptStyle.Default end
			if not d.Enabled then d.Enabled = true end
		end
	end
end
task.spawn(function()
	for _ = 1, 30 do
		restoreMarshmallowPrompts()
		task.wait(2)
	end
end)

-- ===== THE SIGNS =====
-- Each campfire hangs one BillboardGui off a part named "SignAnchor" (Campfire.server.lua). Collect the
-- BillboardGui plus the anchor it is adorned to, since distance is measured to that anchor.
local signs = {}      -- { gui = BillboardGui, anchor = BasePart, zone = number, armed = bool, until_ = n|nil }
local lastScan = 0
local announced = false

local function rescan()
	signs = {}
	for _, m in ipairs(Workspace:GetDescendants()) do
		if m:IsA("BillboardGui") then
			local anchor = m.Adornee or m.Parent
			if anchor and anchor:IsA("BasePart") and anchor.Name == "SignAnchor" then
				-- THE ZONE IS THE SIGN'S OWN MaxDistance -- i.e. exactly where it pops up today, which is
				-- the trigger distance that already felt right. A separate radius would either start the
				-- timer before the sign was visible (burning the window while it could not be seen) or
				-- leave it up beyond its own range.
				local zone = (m.MaxDistance and m.MaxDistance > 0 and m.MaxDistance < 1e6)
					and m.MaxDistance or FALLBACK_ZONE
				signs[#signs + 1] = { gui = m, anchor = anchor, zone = zone, armed = true, until_ = nil }
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.2)   -- 5 Hz: instant to a player, trivial cost

		-- cull destroyed signs
		for i = #signs, 1, -1 do
			local s = signs[i]
			if not (s.gui.Parent and s.anchor.Parent) then table.remove(signs, i) end
		end
		-- campfires are built server-side over the first minute, so keep looking while we have none
		if #signs == 0 and os.clock() - lastScan > 3 then
			lastScan = os.clock()
			rescan()
			if #signs > 0 and not announced then
				announced = true
				print(("[CampfireSign] build %d ACTIVE -- %d sign(s), %ds window, zone %d studs")
					:format(BUILD, #signs, SHOW_SECONDS, signs[1].zone))
			end
		end

		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, s in ipairs(signs) do
				local d = (s.anchor.Position - hrp.Position).Magnitude

				if d > s.zone then
					s.armed = true        -- OUTSIDE: hide at once and re-arm for the next approach
					s.until_ = nil
				elseif s.armed then
					s.armed = false       -- crossed IN: the one moment a window opens
					s.until_ = os.clock() + SHOW_SECONDS
				end

				-- Inside the zone this is a PURE TIMER: where you move makes no difference to it.
				local show = (s.until_ ~= nil) and os.clock() < s.until_
				if not show then s.until_ = nil end

				-- A BillboardGui hides instantly and reliably on Enabled -- no style/rebuild dance is
				-- needed here (that was only ever a ProximityPrompt problem).
				if s.gui.Enabled ~= show then s.gui.Enabled = show end
			end
		end
	end
end)

print(("[CampfireSign] build %d loaded -- %ds window on the Cozy Campfire sign; "
	.. "the marshmallow prompt is left on permanently"):format(BUILD, SHOW_SECONDS))
