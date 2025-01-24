--!strict
local UserInputService = game:GetService("UserInputService")
local Replay = require(script.ReplayModule);

local Player = game:GetService('Players').LocalPlayer

Player.CharacterAdded:Wait()


print("Ready")
local savedReplay = Replay.New({FrameFrequency = 5}, {Player.Character, workspace.sphere, workspace.CurrentCamera}, {workspace.enclosure, workspace.Baseplate, workspace.SpawnLocation}, {})
local Viewport = savedReplay:CreateViewport(Player.PlayerGui.ScreenGui)
Viewport.AnchorPoint = Vector2.new(0.5, 0.5)
Viewport.Size = UDim2.fromScale(0.3, 0.3)
Viewport.Position = UDim2.fromScale(0.8, 0.5)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.R then
			savedReplay:StartRecording()
		elseif input.KeyCode == Enum.KeyCode.T then
			savedReplay:StopRecording()
		elseif input.KeyCode == Enum.KeyCode.Y then
			savedReplay:StartReplay(1)
		elseif input.KeyCode == Enum.KeyCode.U then
			savedReplay:StopReplay()
		elseif input.KeyCode == Enum.KeyCode.P then
			savedReplay:GoToFrame(1,0)
        end
	end
end)