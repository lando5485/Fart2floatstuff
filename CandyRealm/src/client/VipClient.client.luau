-- ============================================================================================================
-- VIP CLIENT -- shows the VIP daily-stipend banner.
-- ============================================================================================================
-- This is the whole client side of VIP, and it is deliberately tiny:
--   * the +25% coin perk is server-side (RewardsService folds it into _G.coinBonusMult)
--   * the VIP tag above the head is drawn by TitleTags off the replicated HasVIP attribute
--   * only the "your daily coins landed" banner needs a remote, because the grant happens on the server
--
-- It pushes through _G.NotifyCenter rather than building a ScreenGui, so the banner queues behind an island
-- unlock or a purchase instead of drawing over it -- NotifyCenter is the ONLY thing in this game allowed to
-- own that slot, and a second full-screen frame is exactly what MenuBackdropGuard exists to hunt down.
-- ============================================================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local VipStipendEvent = RS:WaitForChild("VipStipendEvent", 30)
if not VipStipendEvent then
	warn("[VipClient] VipStipendEvent never appeared -- stipend banner disabled")
	return
end

VipStipendEvent.OnClientEvent:Connect(function(data)
	local amount = type(data) == "table" and tonumber(data.amount) or nil
	if not amount or amount <= 0 then return end

	-- NotifyCenter may not have published its API yet on a slow first frame. Wait briefly rather than dropping
	-- the banner -- the coins are already granted, so the player would otherwise see the counter jump with no
	-- explanation at all.
	local deadline = os.clock() + 10
	while not (_G.NotifyCenter and _G.NotifyCenter.push) and os.clock() < deadline do
		task.wait(0.2)
	end
	if not (_G.NotifyCenter and _G.NotifyCenter.push) then
		warn("[VipClient] NotifyCenter unavailable -- stipend banner skipped (+" .. amount .. " coins still granted)")
		return
	end

	_G.NotifyCenter.push({
		top      = "\xE2\xAD\x90 VIP",
		text     = ("Daily bonus: +%d coins!"):format(amount),
		color    = Color3.fromRGB(255, 215, 0),
		-- REWARD, not PURCHASE: this is a recurring perk landing, not a Robux transaction going through, and
		-- PURCHASE outranks the server-event banners on purpose. A daily stipend should never talk over a
		-- FART STORM starting.
		priority = 40,
		duration = 4,
	})
end)

print("[VipClient] ready -- VIP daily stipend banner")
