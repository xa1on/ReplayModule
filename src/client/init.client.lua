--!strict
local UserInputService = game:GetService("UserInputService")
local Replay = require(script.ReplayModule);

local Player = game:GetService('Players').LocalPlayer

print("ReplayModule Loaded")

if not Player.Character then
	print("Waiting for character to load...")
	Player.CharacterAdded:Wait()
end



print("Ready")
local savedReplay = Replay.New({FrameFrequency = 5}, {Player.Character, workspace.sphere, workspace.CurrentCamera}, {workspace.enclosure, workspace.Baseplate, workspace.SpawnLocation}, {})
local Viewport = savedReplay:CreateViewport(Player.PlayerGui.ScreenGui)
Viewport.AnchorPoint = Vector2.new(0.5, 0.5)
Viewport.Size = UDim2.fromScale(0.3, 0.3)
Viewport.Position = UDim2.fromScale(0.8, 0.5)

savedReplay.RecordingStarted:Connect(function()
	Player.PlayerGui.Info.Recording.TextTransparency = 0
end)

savedReplay.RecordingEnded:Connect(function()
	Player.PlayerGui.Info.Recording.TextTransparency = 1
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.R then
			savedReplay:StartRecording()
		elseif input.KeyCode == Enum.KeyCode.T then
			savedReplay:StopRecording()
			savedReplay:ShowReplay()
        end
	end
end)