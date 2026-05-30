local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local ok, gui = pcall(function() return player:WaitForChild("PlayerGui"):WaitForChild("DialogueGui", 5) end)
if not ok or not gui then return end
local textLabel = gui:WaitForChild("DialogueText", 5)
if not textLabel then return end

local beanFarmerDialogue = [[
Howdy.

Ain’t much out here, but beans make gas… and gas makes ya float.

Buy food at the stand, fill up on gas, then hop in the balloon.

Even if ya fall, the higher ya fly, the more coins ya get.

(Press Talk again to close)
]]

local dialogueOpen = false

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	if prompt.ObjectText ~= "Bean Farmer" then return end

	if not dialogueOpen then
		textLabel.Text = beanFarmerDialogue
		textLabel.Visible = true
		dialogueOpen = true
	else
		textLabel.Visible = false
		dialogueOpen = false
	end
end)