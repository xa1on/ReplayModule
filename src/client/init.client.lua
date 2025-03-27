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
local savedReplay = Replay.New({FrameFrequency = 1}, {Player.Character, workspace.sphere, workspace.CurrentCamera, workspace.Hank}, {workspace.enclosure, workspace.Baseplate, workspace.SpawnLocation}, {})
local Viewport = savedReplay:CreateViewport(Player.PlayerGui.ScreenGui)
Viewport.AnchorPoint = Vector2.new(0.5, 0.5)
Viewport.Size = UDim2.fromScale(0.3, 0.3)
Viewport.Position = UDim2.fromScale(0.8, 0.5)

local fullscreen = false

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
        elseif input.KeyCode == Enum.KeyCode.F then
            fullscreen = not fullscreen
            if fullscreen then
                Viewport.Size = UDim2.fromScale(0.9, 0.9)
                Viewport.Position = UDim2.fromScale(0.5, 0.5)
            else
                Viewport.Size = UDim2.fromScale(0.3, 0.3)
                Viewport.Position = UDim2.fromScale(0.8, 0.5)
            end
        end
    end
end)

game:GetService("RunService").Stepped:Connect(function()
    if savedReplay and savedReplay.Recording then
        Player.PlayerGui.Info.FrameNum.Text = savedReplay.ReplayFrame
    end
end)