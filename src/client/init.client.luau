--!strict
local UserInputService = game:GetService("UserInputService")
local Replay = require(script.ReplayModule);

local Player = game:GetService('Players').LocalPlayer

Player.CharacterAdded:Wait()

local Viewport = Player.PlayerGui.ScreenGui.ViewportFrame


print("Ready")
local savedReplay = Replay.New({FrameFrequency = 5, ReplayLocation = Viewport}, {workspace}, {})

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
		end
	end
end)

savedReplay.ReplayStarted:Connect(function ()
	Viewport.Parent.Enabled = true
end)

savedReplay.ReplayEnded:Connect(function ()
	Viewport.Parent.Enabled = false
end)