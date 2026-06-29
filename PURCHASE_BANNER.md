# Purchase Announcement Banner

The gold banner that slides in for EVERY player when someone buys a gamepass or a
developer product. Source: `CoreClient.client.lua` (`showPurchaseBanner`) +
`PlayerStats.server.lua` (the broadcast). Self-contained copies:
`src/client/PurchaseBanner_AllInOne.client.lua` + `src/server/PurchaseBanner_AllInOne.server.lua`.

## How it works

1. A player buys a **developer product** (via `ProcessReceipt`) or a **gamepass**
   (via `PromptGamePassPurchaseFinished`).
2. The SERVER broadcasts to EVERYONE:
   `PurchaseAnnouncementEvent:FireAllClients(playerName, itemName, isGamepass)`.
3. EVERY client runs `showPurchaseBanner(...)` -> the banner appears for all players.

## The banner (look + behavior)

- **Frame:** 500 x 60, top-center, slides down from `y=-70` to `y=10`
  (Back easing, 0.4s). Color `255,200,0` (gold), corner 12, stroke `200,150,0` th3, ZIndex 20.
- **Icon (left):** `⭐` for a gamepass, `🎉` for a developer product (TextSize 28).
- **Text:** `"[playerName] bought [itemName]!"`, GothamBold 16, color `80,40,0`, left-aligned.
- **Confetti:** 30 small rounded frames spawned over ~1.5s, random colors, falling +
  spinning + fading (Debris-cleaned). A confetti **sound** `rbxassetid://112825313814792` (vol 0.8).
- **Auto-dismiss:** after 4s it slides back up and the ScreenGui is destroyed.

## Server broadcast

- Remote: `PurchaseAnnouncementEvent` (RemoteEvent in ReplicatedStorage).
- Product: `PAE:FireAllClients(player.Name, productName, false)` (false -> 🎉).
- Gamepass: `PAE:FireAllClients(player.Name, passName, true)` (true -> ⭐).
- Name maps (set to YOUR real IDs):
  - products: 2x Power 1 Hour, Mid-Air Recharge, Skip Island, Bird Nuke.
  - gamepasses: 2x Fart Power Forever, Glitter Fart Trail, Infinite Gut.

## Wiring notes

- **Gamepasses** auto-announce: `MarketplaceService.PromptGamePassPurchaseFinished`
  fires server-side -> call `announceGamepassPurchase(plr, passId)` when `wasPurchased`.
- **Dev products** go through `MarketplaceService.ProcessReceipt`, and only ONE
  script may own it. If you already have a `ProcessReceipt`, just add inside it:
  `_G.announceProductPurchase(player, info.ProductId)`. If you have none yet, use the
  commented minimal `ProcessReceipt` in the server file.
- Generic escape hatch: `_G.announcePurchase(name, item, isGamepass)` to announce anything.

## Copy-paste (client banner)

```lua
local TweenService, Debris = game:GetService("TweenService"), game:GetService("Debris")
local PlayerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local function showPurchaseBanner(playerName, itemName, isGamepass)
	local g = Instance.new("ScreenGui"); g.Name="PurchaseBanner"; g.ResetOnSpawn=false; g.IgnoreGuiInset=true; g.Parent=PlayerGui
	local b = Instance.new("Frame"); b.Size=UDim2.new(0,500,0,60); b.Position=UDim2.new(0.5,0,0,-70); b.AnchorPoint=Vector2.new(0.5,0)
	b.BackgroundColor3=Color3.fromRGB(255,200,0); b.ZIndex=20; b.Parent=g
	Instance.new("UICorner",b).CornerRadius=UDim.new(0,12); local s=Instance.new("UIStroke",b); s.Color=Color3.fromRGB(200,150,0); s.Thickness=3
	local icon=Instance.new("TextLabel"); icon.Size=UDim2.new(0,50,1,0); icon.Position=UDim2.new(0,8,0,0); icon.BackgroundTransparency=1
	icon.Text = isGamepass and "\xe2\xad\x90" or "\xf0\x9f\x8e\x89"; icon.TextSize=28; icon.Font=Enum.Font.Gotham; icon.ZIndex=21; icon.Parent=b
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-60,1,0); l.Position=UDim2.new(0,55,0,0); l.BackgroundTransparency=1
	l.Text=playerName.." bought "..itemName.."!"; l.Font=Enum.Font.GothamBold; l.TextSize=16; l.TextColor3=Color3.fromRGB(80,40,0); l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=21; l.Parent=b
	TweenService:Create(b, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position=UDim2.new(0.5,0,0,10)}):Play()
	local snd=Instance.new("Sound"); snd.SoundId="rbxassetid://112825313814792"; snd.Volume=0.8; snd.Parent=workspace; snd:Play(); Debris:AddItem(snd,5)
	task.spawn(function() for i=1,30 do task.wait(0.05)
		local c=Instance.new("Frame"); c.Size=UDim2.new(0,math.random(8,14),0,math.random(8,14)); c.Position=UDim2.new(math.random(20,80)/100,0,0,math.random(-10,0))
		c.BackgroundColor3=Color3.fromHSV(math.random(0,100)/100,1,1); c.BorderSizePixel=0; c.ZIndex=22; c.Rotation=math.random(0,360); c.Parent=g
		Instance.new("UICorner",c).CornerRadius=UDim.new(0,2)
		TweenService:Create(c, TweenInfo.new(2), {Position=UDim2.new(c.Position.X.Scale,0,1,50), Rotation=math.random(360), BackgroundTransparency=1}):Play()
		Debris:AddItem(c,2.1)
	end end)
	task.delay(4, function() TweenService:Create(b, TweenInfo.new(0.3), {Position=UDim2.new(0.5,0,0,-70)}):Play(); task.wait(0.4); g:Destroy() end)
end
```
