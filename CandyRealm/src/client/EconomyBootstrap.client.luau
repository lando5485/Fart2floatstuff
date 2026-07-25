--======================================================================
-- EconomyBootstrap.client.luau  (LocalScript)  -- CandyRealm
--======================================================================
-- The MISSING GLUE. In the food realm, CoreClient does (CoreClient:1741):
--     _G.leaderstats = leaderstats
--     _G.BuyStomachEvent = BuyStomachEvent
--     _G.BuyFoodEvent = BuyFoodEvent ; _G.CoinEvent = CoinEvent
-- CandyRealm has NO CoreClient, so none of those globals were ever set -- which
-- is why the Stomach shop's buys no-op'd ("_G.BuyStomachEvent missing") and every
-- _G.leaderstats read in Shop_AllInOne / StomachShop silently fell back to nil.
--
-- This binds those shared globals from the instances the server provides. Each is
-- GUARDED (short WaitForChild) and NON-CLOBBERING (never overwrites a global that
-- some other script already set), so it's safe alongside any future bootstrap.
--======================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player            = Players.LocalPlayer

-- leaderstats (created by StomachUpgrade.server.luau / any save system)
if not _G.leaderstats then
	local ls = player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats", 30)
	if ls then _G.leaderstats = ls end
end

-- _G.foods -- the food-shop data (name/price/power/island). Nothing else defines
-- it in this realm, so Shop_AllInOne would `ipairs(nil)` -> crash. Provide it from
-- the shared CandyData module. Non-clobbering.
if not _G.foods then
	local ok, CandyData = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared", 10):WaitForChild("CandyData", 10))
	end)
	if ok and CandyData then _G.foods = CandyData.FOODS end
end

-- UNBLOCK the CoreClient-gated scripts. Shop_AllInOne / WorldClient / EventClient /
-- RainbowBeamUI all do `repeat task.wait() until _G.CoreClientReady` at their top.
-- The food realm's CoreClient sets that flag; CandyRealm has none, so those four
-- hung forever (a deadlock -- EventClient was meant to set it but is itself blocked).
-- Now that the globals they need exist, release them.
_G.CoreClientReady = true

-- bind an RS RemoteEvent to a _G.<name> if present and not already bound
local function bindRemote(globalName, instanceName)
	if _G[globalName] then return end
	local ev = ReplicatedStorage:FindFirstChild(instanceName) or ReplicatedStorage:WaitForChild(instanceName, 20)
	if ev then _G[globalName] = ev end
end

bindRemote("BuyStomachEvent", "BuyStomachEvent") -- required by StomachShop buys
bindRemote("BuyFoodEvent",   "BuyFoodEvent")     -- food shop (bound if the remote exists)
bindRemote("CoinEvent",      "CoinEvent")        -- flight coin payouts (bound if the remote exists)

print(("[EconomyBootstrap] bound: leaderstats=%s foods=%s CoreClientReady=true BuyStomachEvent=%s BuyFoodEvent=%s CoinEvent=%s")
	:format(tostring(_G.leaderstats ~= nil), tostring(_G.foods ~= nil),
	        tostring(_G.BuyStomachEvent ~= nil), tostring(_G.BuyFoodEvent ~= nil), tostring(_G.CoinEvent ~= nil)))
