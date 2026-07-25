--======================================================================
-- BlackBarKiller.client.luau  (LocalScript -> StarterPlayer > StarterPlayerScripts)
--======================================================================
-- Permanently kills the recurring "black bar" over the HUD.
--
-- Cause: a STALE baked-in copy of SocialRewards keeps showing an EMPTY dark toast. An empty toast should NEVER
-- be visible, so this watchdog just enforces that rule forever -- ONLY inside SocialRewardsGui, and ONLY on
-- blank dark toasts, so it can never touch real UI. It HIDES (does not sweep / destroy), and it self-heals on
-- respawn + timing races by re-checking whenever a toast's Visible/Text changes, plus a 1s safety re-scrub.
--======================================================================
local Players = game:GetService("Players")
local player  = Players.LocalPlayer
local gui     = player:WaitForChild("PlayerGui")

local function isBlank(s) return s == nil or tostring(s):gsub("%s+", "") == "" end

-- a "black bar" = a VISIBLE, opaque-ish, DARK toast/label with NO text. Always a bug -> hide it.
local function isEmptyToast(o)
	if not (o:IsA("TextLabel") or o:IsA("TextButton")) then return false end
	if not o.Visible then return false end
	if o.BackgroundTransparency > 0.6 then return false end     -- must actually be filling the screen
	local c = o.BackgroundColor3
	if (c.R + c.G + c.B) > 1.2 then return false end            -- must be DARK
	return isBlank(o.Text)                                      -- ...with no message
end

local function hideEmptyToasts(sg)
	if not (sg and sg:IsA("ScreenGui") and sg.Name == "SocialRewardsGui") then return end
	for _, o in ipairs(sg:GetDescendants()) do
		if isEmptyToast(o) then o.Visible = false end
	end
end

local hooked = setmetatable({}, { __mode = "k" })
local function hook(o)
	if hooked[o] or not (o:IsA("TextLabel") or o:IsA("TextButton")) then return end
	hooked[o] = true
	local function recheck() if isEmptyToast(o) then o.Visible = false end end
	o:GetPropertyChangedSignal("Visible"):Connect(recheck)  -- the moment a stale copy shows it, flip it back
	o:GetPropertyChangedSignal("Text"):Connect(recheck)
	recheck()
end

local function watch(sg)
	if not (sg:IsA("ScreenGui") and sg.Name == "SocialRewardsGui") then return end
	hideEmptyToasts(sg)
	for _, o in ipairs(sg:GetDescendants()) do hook(o) end
	sg.DescendantAdded:Connect(hook)
end

for _, sg in ipairs(gui:GetChildren()) do watch(sg) end
gui.ChildAdded:Connect(watch)

-- belt-and-braces: re-scrub every second (cheap; only ever looks at SocialRewardsGui)
task.spawn(function()
	while true do
		for _, sg in ipairs(gui:GetChildren()) do hideEmptyToasts(sg) end
		task.wait(1)
	end
end)

print("[BlackBarKiller] active -- keeps empty SocialRewards toasts hidden (kills the black bar)")
