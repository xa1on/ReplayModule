-- i am in typechecking purgatory.
-- death and damnation

--!strict
local DEBUG = true
local ID_ATTRIBUTE = "ReplayID"
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
--local UserInputService = game:GetService("UserInputService")

--   Types
type StoredCFrame = {number} -- also stores type in __type = "StoredCFrame"

type SettingsType = {
    FrameFrequency: number?, -- store a single frame for every n frames rendered
    ReplayLocation: Instance?, -- where the replay folder is stored under (the replay folder is what stores the models that are being replayed)
    Rounding: number?, -- number of digits values should be rounded to to save memory
}
type SettingsTypeStrict = {
    FrameFrequency: number,
    ReplayLocation: Instance,
    Rounding: number,
}
local DefaultSettings: SettingsTypeStrict = {
    FrameFrequency = 1,
    ReplayLocation = workspace,
    Rounding = 3
}

-- Stores Model Change Info
export type ModelStateType = {
    ["CFrame"]: StoredCFrame?,
    ["Transparency"]: number?,
    ["Color"]: Color3?,
    ["NotDestroyed"]: boolean?,
    ["FieldOfView"]: number?
}

-- Stores Frame Info
export type FrameType = {
    Time: number, -- time in seconds the frame took place
    ModelChanges: {ModelStateType}, -- table containing the changes in model properties, keys representing the index the model is stored inside activeModels
    Next: FrameType | nil, -- next frame in the replay
    Previous: FrameType | nil -- previous frame in replay
}

-- Stores Replays
export type ReplayType = {
    -- Custom Properties
    StartFrame: FrameType, -- starting frame of replay
    EndFrame: FrameType, -- ending frame of replay
    CurrentFrame: FrameType,
    Settings: SettingsTypeStrict, -- settings applied to the replay
    ActiveModels: {Instance}, -- models that user specifies to keep track of
    ActualActiveModels: {Instance}, -- above, but the actual models being kept track of
    StaticModels: {Instance}, -- models that user specifies to not move and remain static througout the replay. these models are not tracked
    ActualStaticModels: {Instance}, -- above, but the actual static models
    PreviousRecordedState: {Instance}, -- saves the previous recorded state of each active part
    StaticClones: {Instance}, -- clones of all static models
    IgnoredModels: {Instance}, -- all models who are not rendered
    AllActiveParts: {Instance}, -- all objects, including activeModel children that are being kept track of
    ActiveClones: {Instance}, -- clones of all active models
    AllActiveClones: {Instance}, -- actual parts associated with all the active parts in the clones
    CurrentState: {ModelStateType}, -- current ModelStateType values of all models
    Connections: {RBXScriptConnection}, -- list of connections being used by the replay. they are disconnected and cleared after recording and replay
    ViewportFrameConnections: {RBXScriptConnection}, -- list of connections used in the viewport frame.
    CustomEvents: {[string]: BindableEvent},

    -- Events
    RecordingStarted: RBXScriptSignal, -- fires when recording starts
    RecordingEnded: RBXScriptSignal, -- fires when recording ends
    ReplayShown: RBXScriptSignal, -- fires when replay is shown
    ReplayHidden: RBXScriptSignal, -- fires when replay is hidden
    ReplayStarted: RBXScriptSignal, -- fires when replay is started
    ReplayEnded: RBXScriptSignal, -- fires when replay is ended
    ReplayFrameChanged: RBXScriptSignal, -- fires when the current frame of the replay is changed

    -- Properties
    Recording: boolean, -- represents whether or not the replay is recording 
    Playing: boolean, -- represents whether or not the replay is being played
    ReplayVisible: boolean, -- represents whether or not the replay is visible
    ReplayTime: number, -- number of seconds in the replay is.
    ReplayFrame: number, -- current frame number of the replay
    ReplayT: number, -- number from 0 - 1 representing the progress between the current frame and the subsequent frame
    ReplayFrameCount: number, -- number of frames in the replay

    -- Methods
    New: (SettingsType, {Instance}, {Instance}?, {Instance}?) -> ReplayType,
    RegisterActive: (ReplayType, Instance) -> number, -- registers a model as an active model, returns the id of the active model
    RegisterStatic: (ReplayType, Instance) -> nil, -- registers a model as a static model
    StartRecording: (ReplayType) -> nil, -- starts recording the replay
    StopRecording: (ReplayType) -> nil, -- stops recording the replay
    UpdateReplayLocation: (ReplayType, Instance?) -> nil, -- sets the location of the replay
    ShowReplay: (ReplayType, boolean?) -> nil, -- puts replay into ReplayLocation. makes the replay visible
    HideReplay: (ReplayType) -> nil, -- hides the replay. it gets removed from replaylocation
    GoToFrame: (ReplayType, number, number, boolean?) -> nil, -- go to a specific frame. t (number 0 to 1) represents the progress from that frame to the subsequent frame
    GoToTime: (ReplayType, number, boolean?) -> nil, -- go to a specific time in a replay
    StopReplay: (ReplayType) -> nil, -- stops the replay on the current frame
    StartReplay: (ReplayType, number) -> nil, -- starts the replay on the current frame
    CreateViewport: (ReplayType, Instance) -> ViewportFrame, -- Creates a ViewportFrame for the replay. Sets the ReplayLocation to the ViewportFrame and returns the ViewportFrame
    Clear: (ReplayType) -> nil, -- clears the recording off the replay
    Destroy: (ReplayType) -> nil -- destroys the replay. the whole replay will be cleared
}

-- Module
local Module: ReplayType = {} -- The functions are defined later on ignore warning
Module.__index = Module



--   Helper Functions

-- Checks if table is empty
local function TableEmpty(t1: {}): boolean
    local next = next
    if next(t1) == nil then
        return true
    end
    return false
end

-- Dumps deep table data into a string
local function DumpTable(t1: {}): string
    local function Helper(t1: {}, step: number): string
        step = step or 1
        if type(t1) == "table" then
            if TableEmpty(t1) then return "{}" end
            local result: string = "{\n" .. string.rep(":", step)
            for i, v in pairs(t1) do
                result = result .. tostring(i) .." = " .. Helper(v, step+1) .. ","
            end
            return result .. "\n".. string.rep(":", step-1) .. "}"
        else
            return tostring(t1)
        end
    end
    return Helper(t1, 1)
end

-- Converts a StoredCFrame to a CFrame
local function StoredCFrameToCFrame(cf1: StoredCFrame): CFrame
    return CFrame.new(table.unpack(cf1))
end

-- Converts a CFrame to a StoredCFrame
local function CFrameToStoredCFrame(cf1: CFrame): StoredCFrame
    local temp: StoredCFrame = table.pack(cf1:GetComponents())
    temp.__type = "StoredCFrame" -- Required for type detection. ignore warning
    return temp
end

-- round a number to a certain decimal place
local function RoundToPlace(num: number, digits: number): number
    return math.round(num * (10 ^ digits)) / (10 ^ digits)
end

-- same as above but for cframes
local function RoundCFrame(cf: CFrame, digits: number): StoredCFrame
    local cframeTable: StoredCFrame = CFrameToStoredCFrame(cf)
    for index, value in ipairs(cframeTable) do
        cframeTable[index] = RoundToPlace(value, digits) -- cframes only contain numbers for the indexed part of the table. ignore warning
    end
    return cframeTable
end

-- same but color3
local function RoundColor3(c: Color3, digits: number): Color3
    return Color3.new(RoundToPlace(c.R, digits), RoundToPlace(c.G, digits), RoundToPlace(c.B, digits))
end

-- Checks if two tables are shallow equal (idk)
local function ShallowEquals(t1: {}, t2: {}): boolean
    if #t1 ~= #t2 then return false end
    for index, inst in pairs(t1) do
        if t2[index] ~= inst then
            return false
        end
    end
    return true
end

-- Creates a shallow copy of tables
local function ShallowCopy(original: {}): {}
    local new: {} = {}
    for index, inst in pairs(original) do
        new[index] = inst
    end
    return new
end

-- Check if two instances are identical-ish
local function InstanceIdentical(inst1: Instance, inst2: Instance): boolean
    local id = inst1:GetAttribute(ID_ATTRIBUTE)
    return inst1.Name == inst2.Name and inst1.ClassName == inst2.ClassName and (not id or (id == inst2:GetAttribute(ID_ATTRIBUTE))) --[[ and (not inst1:IsA("BasePart") or (inst1.CFrame == inst2.CFrame and inst1.Size == inst2.Size))]]
end

-- Find first child that is identical to inst1
local function FindChildWhichIs(parent: Instance, inst1: Instance): Instance
    if InstanceIdentical(parent, inst1) then
        return parent
    end
    for _, inst2 in ipairs(parent:GetChildren()) do
        if InstanceIdentical(inst1, inst2) then
            return inst2
        end
    end
    error("Child not found. " .. parent:GetFullName() .. " does not contain " .. inst1.Name)
end

local function FindDescendantWhichIs(parent: Instance, inst1: Instance): Instance
    if InstanceIdentical(parent, inst1) then
        return parent
    end
    for _, inst2 in ipairs(parent:GetDescendants()) do
        if InstanceIdentical(inst1, inst2) then
            return inst2
        end
    end
    --[[
    parent.Parent = workspace
    inst1.Parent = workspace
    parent.Name ..= "EP"
    inst1.Name ..= "E"]]
    error("Descendent not found. " .. parent:GetFullName() .. " does not contain " .. inst1.Name)
end

-- turns part into uninteractable ghost part
local function GhostPart(inst: Instance): Instance
    if not inst:IsA("BasePart") then return inst end
    inst.Anchored = true
    inst.Massless = true
    inst.CanCollide = false
    inst.CanTouch = false
    inst.CanQuery = false
    return inst
end

-- Converts regular settings into strict settings with default values from DefaultSettings
local function NormalizeSettings(Settings: SettingsType): SettingsTypeStrict
    local Current: SettingsTypeStrict = DefaultSettings
    for Property, _ in pairs(DefaultSettings) do
        if Settings[Property] ~= nil then
            Current[Property] = Settings[Property]
        end
    end
    return Current
end

-- Gets the state of an instance
local function GetState(inst: Instance, rounding: number): ModelStateType
    local state: ModelStateType = {
        ["NotDestroyed"] = inst:IsDescendantOf(game)
    }
    if inst:IsA("BasePart") then
        state["CFrame"] = RoundCFrame(inst.CFrame, rounding)
        state["Color"] = RoundColor3(inst.Color, rounding)
        state["Transparency"] = RoundToPlace(1 - ((1 - inst.Transparency) * (1 - inst.LocalTransparencyModifier)), rounding)
    elseif inst:IsA("Camera") then
        state["CFrame"] = RoundCFrame(inst.CFrame, rounding)
        state["FieldOfView"] = RoundToPlace(inst.FieldOfView, rounding)
    end
    return state
end

-- Gets the type of an item (includes custom types)
local function GetType(item): string
    local suggestedType: string = typeof(item)
    if suggestedType == "table" and item.__type then
        return item.__type
    end
    return suggestedType
end

-- Turns seconds into a string in the form minutes : seconds

local function ConvertTime(time: number): string
    local result: string = ""
    local minutes: number = 0
    if time >= 60 then
        minutes = math.floor(time / 60)
        time -= minutes * 60
    end
    result ..= tostring(minutes) .. ":"
    if time < 10 then
        result ..= "0"
    end
    result ..= tostring(math.floor(time))
    return result
end



-- Interpolation

-- linear interpolation method for numbers
local function Lerp(p1: number, p2: number, t: number)
    return t * (p2 - p1) + p1 -- again, can be vector3 or number, doesnt matter which it is
end


-- Create a new Replay Object
function Module.New(s: SettingsType, ActiveModels: {Instance}, StaticModels: {Instance}?, IgnoredModels: {Instance}?): ReplayType
    local self: ReplayType = {}  -- The functions are defined later on ignore warning
    self.Settings = NormalizeSettings(s)
    self.StartFrame = nil
    self.EndFrame = nil
    self.CurrentFrame = nil
    self.ActiveModels = ActiveModels
    self.ActualActiveModels = {}
    self.AllActiveParts = {}
    self.StaticModels = StaticModels or {}
    self.ActualStaticModels = {}
    self.StaticClones = {}
    self.IgnoredModels = IgnoredModels or {}
    self.ActiveClones = {}
    self.AllActiveClones = {}
    self.CurrentState = {}
    self.Connections = {}
    self.ViewportFrameConnections = {}
    self.CustomEvents = {
        RecordingStarted = Instance.new("BindableEvent"),
        RecordingEnded = Instance.new("BindableEvent"),
        ReplayShown = Instance.new("BindableEvent"),
        ReplayHidden = Instance.new("BindableEvent"),
        ReplayStarted = Instance.new("BindableEvent"),
        ReplayEnded = Instance.new("BindableEvent"),
        ReplayFrameChanged = Instance.new("BindableEvent")
    }
    self.RecordingStarted = self.CustomEvents.RecordingStarted.Event
    self.RecordingEnded = self.CustomEvents.RecordingEnded.Event
    self.ReplayStarted = self.CustomEvents.ReplayStarted.Event
    self.ReplayShown = self.CustomEvents.ReplayShown.Event
    self.ReplayHidden = self.CustomEvents.ReplayHidden.Event
    self.ReplayEnded = self.CustomEvents.ReplayEnded.Event
    self.ReplayFrameChanged = self.CustomEvents.ReplayFrameChanged.Event
    self.Recording = false
    self.Playing = false
    self.ReplayVisible = false
    self.ReplayTime = 0
    self.ReplayFrame = 0
    self.ReplayT = 0
    self.ReplayFrameCount = 0
    
    return setmetatable(self, Module)
end

-- Registers an object as an ActiveModel
function Module:RegisterActive(model: Instance): number
    self.ActualActiveModels[#self.ActualActiveModels + 1] = model
    if not self.Recording then return end
    local function Register(model: Instance): number
        if table.find(self.IgnoredModels, model) or model:IsA("Status") or not (model:IsA("BasePart") or model:IsA("Model") or model:IsA("Camera")) then return 0 end
        local index: number = #self.AllActiveParts + 1
        self.CurrentFrame.ModelChanges[index] = GetState(model, self.Settings.Rounding)
        self.PreviousRecordedState[index] = GetState(model, self.Settings.Rounding) -- duplicate of previous call. need to create deep copy
        self.AllActiveParts[index] = model
        model:SetAttribute(ID_ATTRIBUTE, index)
        if self.ReplayFrame ~= 1 then
            self.StartFrame.ModelChanges[index] = {
                ["NotDestroyed"] = false
            }
        end
        return index
    end
    local id: number = Register(model)
    for _, inst2 in ipairs(model:GetDescendants()) do
        Register(inst2)
    end
    -- clone activemodel, then assign allactiveclones and activeclones
    model.Archivable = true
    for _, inst2 in ipairs(model:GetDescendants()) do
        inst2.Archivable = true
    end
    local clone = model:Clone()
    if clone == nil and DEBUG then
        error("Failed to clone: " .. model:GetFullName())
    end
    GhostPart(clone)
    self.ActiveClones[id] = clone
    self.AllActiveClones[id] = clone
    for _, inst2 in ipairs(clone:GetDescendants()) do
        GhostPart(inst2)
        id = inst2:GetAttribute(ID_ATTRIBUTE)
        if id ~= nil then
            self.AllActiveClones[id] = inst2
        end
    end
    table.insert(self.Connections, model.DescendantAdded:Connect(function(desc)
        if desc:GetAttribute(ID_ATTRIBUTE) then return end
        desc.Archivable = true
        local id = Register(desc)
        local clone2 = desc:Clone()
        if clone2 == nil and DEBUG then
            error("Failed to clone: " .. desc:GetFullName())
        end
        GhostPart(clone2)
        clone2.Parent = FindDescendantWhichIs(clone, desc.Parent) -- well, i mean, if a descendant was added, that means it has a parent, right? why are you giving a warning here
        if id ~= 0 then
            self.AllActiveClones[id] = clone2
        end
    end))
    return id
end

-- Registers an object as a StaticModel
function Module:RegisterStatic(model: Instance): nil
    self.ActualStaticModels[#self.ActualStaticModels + 1] = model
    if not self.Recording then return end
    local clone = model:Clone()
    GhostPart(clone)
    table.insert(self.StaticClones, clone)
end

-- Assuming all Replays initially contain no frames
function Module:StartRecording(): nil
    if self.Recording or self.Playing then return end
    if self.StartFrame then
        self:Clear()
    end
    self.PreviousRecordedState = {}
    self.Recording = true
    self.ReplayFrame = 1;
    self.ReplayFrameCount = 1;
    local currentTime: number = 0
    
    local recordFrameCounter: number = self.Settings.FrameFrequency -- Count before recording frame using FrameFrequency
    
    local newFrame: FrameType = {
        Time = 0,
        ModelChanges = {},
        Next = nil,
        Previous = nil
    }

    self.StartFrame = {
        Time = 0,
        ModelChanges = {},
        Next = nil,
        Previous = nil
    }
    
    self.CurrentFrame = self.StartFrame
    
    -- If workspace is contained, replace active models with only children of workspace
    for _, inst in ipairs(self.ActiveModels) do
        if inst == workspace then
            self.ActiveModels = {}
            for _, inst2 in ipairs(workspace:GetChildren()) do
                if not inst2:IsA("Terrain") and not table.find(self.IgnoredModels, inst2) then
                    table.insert(self.ActiveModels, inst2)
                end
            end
            break
        end
    end
    
    self.ActualActiveModels = {}
    self.ActualStaticModels = {}
    for _, inst in ipairs(self.ActiveModels) do
        self:RegisterActive(inst)
    end
    
    for _, inst in ipairs(self.StaticModels) do
        self:RegisterStatic(inst)
    end
    
    if DEBUG then
        print("Recording Started")
        --print(DumpTable(Replay))
        --print(DumpTable(self.PreviousRecordedState))
    end
    self.CustomEvents.RecordingStarted:Fire()
    
    --   Actual recording part
    local newState: ModelStateType -- temp table containing the state of the current part
    local change: boolean -- temp variable used to indicate whether or not a value has changed
    local previousClock: number = os.clock()
    local currentClock: number
    table.insert(self.Connections, RunService.PreAnimation:Connect(function()
        recordFrameCounter -= 1
        currentClock = os.clock()
        currentTime += currentClock - previousClock
        previousClock = currentClock
        self.ReplayTime = currentTime
        if recordFrameCounter == 0 then
            recordFrameCounter = self.Settings.FrameFrequency
        else
            return
        end
        newFrame = {
            Time = RoundToPlace(currentTime, self.Settings.Rounding),
            ModelChanges = {},
            Next = nil,
            Previous = self.CurrentFrame
        }
        for index, inst in ipairs(self.AllActiveParts) do
            newState = GetState(inst, self.Settings.Rounding)
            for pindex, pval in pairs(newState) do
                if typeof(pval) == "table" then
                    change = not ShallowEquals(pval, self.PreviousRecordedState[index][pindex])
                else
                    change = self.PreviousRecordedState[index][pindex] ~= pval
                end
                if change then
                    self.PreviousRecordedState[index][pindex] = pval
                    if not newFrame.ModelChanges[index] then
                        newFrame.ModelChanges[index] = {}
                    end
                    newFrame.ModelChanges[index][pindex] = pval
                end
            end
        end
        if not TableEmpty(newFrame.ModelChanges) then
            self.ReplayFrame += 1
            self.CurrentFrame.Next = newFrame
            self.CurrentFrame = newFrame
            self.EndFrame = newFrame
            self.ReplayFrameCount += 1
        end
    end))
    return
end

function Module:StopRecording(): nil
    if not self.Recording then return end
    self.CustomEvents.RecordingEnded:Fire()
    for _, connection in ipairs(self.Connections) do
        if connection ~= nil then
            connection:Disconnect()
        end
    end
    self.Connections = {}
    self.PreviousRecordedState = {}
    self.Recording = false
    self:GoToFrame(1, 0, true)
    if DEBUG then
        print("Recording Stopped")
        --print(DumpTable(self.StartFrame))
        --print(DumpTable(self.AllActiveParts))
        --print(DumpTable(self.AllActiveClones))
    end
    return
end

function Module:UpdateReplayLocation(location: Instance?): nil
    if location then self.Settings.ReplayLocation = location end
    if not self.ReplayVisible then return end
    for _, inst in pairs(self.ActiveClones) do
        inst.Parent = self.Settings.ReplayLocation
    end
    for _, inst in pairs(self.StaticClones) do
        inst.Parent = self.Settings.ReplayLocation
    end
    if DEBUG then
        print("Replay Location Updated")
    end
    return
end

function Module:ShowReplay(override: boolean?): nil
    if not override and (self.Playing or self.Recording or self.ReplayVisible) then return end
    for _, inst in pairs(self.ActiveClones) do
        inst.Parent = self.Settings.ReplayLocation
    end
    
    for _, inst in pairs(self.StaticClones) do
        inst.Parent = self.Settings.ReplayLocation
    end
    self.ReplayVisible = true
    self.CustomEvents.ReplayShown:Fire()
    for _, clone in ipairs(self.AllActiveClones) do
        if clone:IsA("Camera") then
            clone.CameraType = Enum.CameraType.Scriptable
            if self.Settings.ReplayLocation.Parent and self.Settings.ReplayLocation.Parent:IsA("ViewportFrame") and self.Settings.ReplayLocation:IsA("WorldModel") then
                self.Settings.ReplayLocation.Parent.CurrentCamera = clone
            elseif self.Settings.ReplayLocation:IsA("ViewportFrame") then
                self.Settings.ReplayLocation.CurrentCamera = clone -- theres gotta be a better way of doing this
            end
        end
    end
    if DEBUG then
        print("Replay Shown")
    end
    return
end

function Module:HideReplay(): nil
    if self.Playing or self.Recording or not self.ReplayVisible then return end
    for _, clone in pairs(self.ActiveClones) do -- ActiveClones is not continuous sometimes
        clone.Parent = nil
    end
    for _, clone in pairs(self.StaticClones) do
        clone.Parent = nil
    end
    self.ReplayVisible = false
    self.CustomEvents.ReplayHidden:Fire()
    if DEBUG then
        print("Replay Hidden")
    end
    return
end

function Module:GoToFrame(frame: number, t: number, override: boolean?): nil
    if frame < 1 or frame > self.ReplayFrameCount then error("Frame out of range. [1, " .. self.ReplayFrameCount .. "]") end
    if not override and (self.Playing or self.Recording or not self.ReplayVisible or frame == self.ReplayFrame) then return end
    local function SetCurrentState(state: ModelStateType, index: number): nil
        if state == nil then return end
        if not self.CurrentState[index] then self.CurrentState[index] = {} end
        for name, value in pairs(state) do
            if value ~= nil then
                self.CurrentState[index][name] = value
            end
        end
        return
    end
    local startFrame: number = self.ReplayFrame
    local newStates: {ModelStateType} = {}
    if frame < startFrame then
        self.CurrentState = {}
    end
    if TableEmpty(self.CurrentState) then
        startFrame = 1
        self.CurrentFrame = self.StartFrame
        self.ReplayFrame = 1
    end
    
    for currentFrameNum = startFrame, frame, 1 do
        for index, _ in ipairs(self.AllActiveClones) do
            SetCurrentState(self.CurrentFrame.ModelChanges[index], index)
        end
        if currentFrameNum ~= frame then
            self.CurrentFrame = self.CurrentFrame.Next
            self.ReplayFrame += 1
        end
    end
    
    for index, _ in ipairs(self.AllActiveClones) do
        newStates[index] = if self.CurrentState[index] then ShallowCopy(self.CurrentState[index]) else {}
    end
    
    local f1: FrameType = self.CurrentFrame
    local f2: FrameType | nil = self.CurrentFrame.Next
    
    local values: {}
    for index, clone in ipairs(self.AllActiveClones) do
        if self.CurrentState[index]["NotDestroyed"] then -- Ignore warnings here. GetType should protect from any errors
            if f2 then
                if f2.ModelChanges[index] then
                    values = {}
                    for name, value in pairs(f2.ModelChanges[index]) do
                        if self.CurrentState[index][name] then
                            values[1] = self.CurrentState[index][name]
                            values[2] = value
                            if GetType(value) == "StoredCFrame" then
                                for index2, value2 in pairs(values) do
                                    values[index2] = StoredCFrameToCFrame(value2)
                                end
                                newStates[index][name] = values[1]:Lerp(values[2], t)
                            elseif GetType(value) == "Color3" or GetType(value) == "Vector3" then
                                newStates[index][name] = values[1]:Lerp(values[2], t)
                            elseif GetType(value) ~= "boolean" then
                                newStates[index][name] = Lerp(values[1], values[2], t)
                            end
                        end
                    end
                end
                self.ReplayTime = t * (f2.Time - f1.Time) + f1.Time
            else
                t = 0
                self.ReplayTime = f1.Time
            end
        end
        for name, value in pairs(newStates[index]) do
            if name == "NotDestroyed" then
                if value then
                    if not clone:IsDescendantOf(game) then
                        clone.Parent = self.Settings.ReplayLocation
                    end
                elseif clone:IsA("BasePart") then
                    if clone.Transparency ~= 1 then
                        clone.Transparency = 1
                    end
                    newStates[index].Transparency = nil
                end
            elseif GetType(value) == "StoredCFrame" then
                if not ShallowEquals(RoundCFrame(clone[name], self.Settings.Rounding), value) then
                    clone[name] = StoredCFrameToCFrame(value) -- Ignore warnings here. GetType should protect from any errors
                end
            elseif clone[name] ~= value then
                clone[name] = value -- same w/ here
            end
        end
    end
    self.ReplayT = t
    self.CustomEvents.ReplayFrameChanged:Fire()
    return
end

function Module:GoToTime(time: number, override: boolean?): nil
    local currentFrameNum: number = self.ReplayFrame
    local currentFrame: FrameType | nil = self.CurrentFrame
    if self.ReplayTime > time then
        currentFrameNum = 1
        currentFrame = self.StartFrame
    end
    while currentFrameNum < self.ReplayFrameCount and currentFrame.Time < time do
        currentFrameNum += 1
        currentFrame = currentFrame.Next
    end
    local f1: FrameType = currentFrame.Previous
    local f2: FrameType = currentFrame
    if f1 then
        self:GoToFrame(currentFrameNum - 1, (time - f1.Time) / (f2.Time - f1.Time), override)
    else
        self:GoToFrame(currentFrameNum, 0, override)
    end
    return
end

function Module:StartReplay(timescale: number): nil
    if self.Playing or self.Recording then return end
    self.Connections = {}
    if not self.ReplayVisible then
        self:ShowReplay(true)
    end
    if self.ReplayFrame > self.ReplayFrameCount then
        self:GoToFrame(1, 0)
    end
    self.Playing = true
    if DEBUG then
        print("Replay Started")
    end
    self.CustomEvents.ReplayStarted:Fire()
    local currentTime: number = self.ReplayTime
    self.Connections[1] = RunService.RenderStepped:Connect(function(dt: number)
        currentTime += dt * timescale
        if currentTime < self.EndFrame.Time then
            self:GoToTime(currentTime, true)
        else
            self:GoToFrame(self.ReplayFrameCount, 0, true)
            self:StopReplay()
        end
    end)
    return
end

function Module:StopReplay(): nil
    if not self.Playing then return end
    self.CustomEvents.ReplayEnded:Fire()
    self.Connections[1]:Disconnect()
    self.Connections = {}
    self.Playing = false
    if DEBUG then
        print("Replay Stopped")
    end
    return
end

function Module:CreateViewport(parent: Instance): ViewportFrame
    local timescale: number = 1
    local dragStarted: boolean = false
    local wasPlaying: boolean = false
    local mouse: Mouse = Players.LocalPlayer:GetMouse()
    local ViewportFrame = Instance.new("ViewportFrame", parent)
    ViewportFrame.BorderSizePixel = 0
    ViewportFrame.BackgroundColor3 = Color3.new(0)
    ViewportFrame.Ambient = Color3.new(0)
    ViewportFrame.LightColor = Color3.new(1, 1, 1)
    ViewportFrame.LightDirection = Vector3.new(-1, -0.6, -0.6)
    local WorldModel = Instance.new("WorldModel", ViewportFrame)
    local BottomFrame = Instance.new("Frame", ViewportFrame)
    BottomFrame.ZIndex = 0
    BottomFrame.AnchorPoint = Vector2.new(0.5, 1)
    BottomFrame.Position = UDim2.fromScale(0.5, 1)
    BottomFrame.Size = UDim2.fromScale(1, 0.1)
    local UIGradient = Instance.new("UIGradient", BottomFrame)
    UIGradient.Color = ColorSequence.new(Color3.new(0))
    UIGradient.Transparency = NumberSequence.new(1, 0)
    UIGradient.Rotation = 90
    local BackButton = Instance.new("ImageButton", BottomFrame)
    BackButton.AnchorPoint = Vector2.new(0.5, 0.5)
    BackButton.BackgroundTransparency = 1
    BackButton.Position = UDim2.fromScale(0.46, 0.5)
    BackButton.Size = UDim2.fromScale(1, 1)
    BackButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
    BackButton.Image = "rbxasset://textures/AnimationEditor/button_control_previous.png"
    table.insert(self.ViewportFrameConnections, BackButton.MouseButton1Click:Connect(function()
        if self.Recording or self.ReplayFrameCount < 1 then return end
        self:GoToFrame(1, 0, true)
    end))
    local ForwardButton = Instance.new("ImageButton", BottomFrame)
    ForwardButton.AnchorPoint = Vector2.new(0.5, 0.5)
    ForwardButton.BackgroundTransparency = 1
    ForwardButton.Position = UDim2.fromScale(0.54, 0.5)
    ForwardButton.Size = UDim2.fromScale(1, 1)
    ForwardButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
    ForwardButton.Image = "rbxasset://textures/AnimationEditor/button_control_next.png"
    table.insert(self.ViewportFrameConnections, ForwardButton.MouseButton1Click:Connect(function()
        if self.Recording or self.ReplayFrameCount < 1 then return end
        if self.Playing then
            self:StopReplay()
        end
        self:GoToFrame(self.ReplayFrameCount, 0, true)
    end))
    local PlayButton = Instance.new("ImageButton", BottomFrame)
    PlayButton.AnchorPoint = Vector2.new(0.5, 0.5)
    PlayButton.BackgroundTransparency = 1
    PlayButton.Position = UDim2.fromScale(0.50, 0.5)
    PlayButton.Size = UDim2.fromScale(1, 1)
    PlayButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
    PlayButton.Image = "rbxasset://textures/DeveloperFramework/MediaPlayerControls/play_button.png"
    table.insert(self.ViewportFrameConnections, PlayButton.MouseButton1Click:Connect(function()
        if self.Recording or self.ReplayFrameCount < 1 then return end
        if self.Playing then
            self:StopReplay()
        else
            if self.ReplayFrame == self.ReplayFrameCount then
                self:GoToFrame(1, 0, true)
            end
            self:StartReplay(timescale)
        end
    end))
    table.insert(self.ViewportFrameConnections, self.ReplayStarted:Connect(function()
        PlayButton.Image = "rbxasset://textures/DeveloperFramework/MediaPlayerControls/pause_button.png"
    end))
    table.insert(self.ViewportFrameConnections, self.ReplayEnded:Connect(function()
        PlayButton.Image = "rbxasset://textures/DeveloperFramework/MediaPlayerControls/play_button.png"
    end))
    local Time = Instance.new("TextLabel", BottomFrame)
    Time.BorderSizePixel = 0
    Time.AnchorPoint = Vector2.new(0, 0.5)
    Time.BackgroundTransparency = 1
    Time.Position = UDim2.fromScale(0.05, 0.5)
    Time.Size = UDim2.fromScale(2, 0.5)
    Time.SizeConstraint = Enum.SizeConstraint.RelativeYY
    Time.FontFace = Font.fromName("SourceSansPro", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    Time.TextColor3 = Color3.new(1, 1, 1)
    Time.TextScaled = true
    Time.TextSize = 12
    local function UpdateTime()
        if self.ReplayFrameCount < 1 then
            Time.Text = "0:00 / 0:00"
        else
            Time.Text = ConvertTime(self.ReplayTime) .. " / " .. ConvertTime(self.EndFrame.Time)
        end
    end
    UpdateTime()
    local TimescaleInput = Instance.new("TextBox", BottomFrame)
    TimescaleInput.BorderSizePixel = 0
    TimescaleInput.AnchorPoint = Vector2.new(1, 0.5)
    TimescaleInput.BackgroundColor3 = Color3.new(0, 0, 0)
    TimescaleInput.BackgroundTransparency = 0.5
    TimescaleInput.Position = UDim2.fromScale(0.95, 0.5)
    TimescaleInput.Size = UDim2.fromScale(2, 0.5)
    TimescaleInput.SizeConstraint = Enum.SizeConstraint.RelativeYY
    TimescaleInput.FontFace = Font.fromName("SourceSansPro", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    TimescaleInput.TextColor3 = Color3.new(1, 1, 1)
    TimescaleInput.TextScaled = true
    TimescaleInput.TextSize = 12
    TimescaleInput.Text = tostring(timescale)
    TimescaleInput.PlaceholderText = "Timescale"
    table.insert(self.ViewportFrameConnections, TimescaleInput.FocusLost:Connect(function()
        local newTimescale = tonumber(TimescaleInput.Text)
        if newTimescale then
            timescale = newTimescale
            if self.Playing then
                self:StopReplay()
                self:StartReplay(timescale)
            end
        else
            TimescaleInput.Text = tostring(timescale)
        end
    end))
    local Timeline = Instance.new("Frame", ViewportFrame)
    Timeline.BorderSizePixel = 0
    Timeline.AnchorPoint = Vector2.new(0.5, 1)
    Timeline.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
    Timeline.Position = UDim2.fromScale(0.5, 0.9)
    Timeline.Size = UDim2.fromScale(0.95, 0.01)
    local TimelineProgress = Instance.new("Frame", Timeline)
    TimelineProgress.BorderSizePixel = 0
    TimelineProgress.BackgroundColor3 = Color3.new(1, 1, 1)
    local function XToTime(x: number): number
        return math.min((x - Timeline.AbsolutePosition.X) / Timeline.AbsoluteSize.X, 1)
    end
    table.insert(self.ViewportFrameConnections, Timeline.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if self.Recording or self.ReplayFrameCount < 1 then return end
            wasPlaying = self.Playing
            dragStarted = true
            if wasPlaying then
                self:StopReplay()
            end
            self:GoToTime(self.EndFrame.Time * XToTime(input.Position.X))
        end
    end))
    local FrameNumCounter = Instance.new("TextLabel", ViewportFrame)
    FrameNumCounter.BorderSizePixel = 0
    FrameNumCounter.BackgroundTransparency = 1
    FrameNumCounter.Position = UDim2.fromScale(0.02, 0.02)
    FrameNumCounter.Size = UDim2.fromScale(0.05, 0.05)
    FrameNumCounter.SizeConstraint = Enum.SizeConstraint.RelativeYY
    FrameNumCounter.FontFace = Font.fromName("SourceSansPro", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    FrameNumCounter.TextColor3 = Color3.new(1, 1, 1)
    FrameNumCounter.TextTransparency = 0.5
    FrameNumCounter.TextScaled = true
    FrameNumCounter.TextSize = 12
    FrameNumCounter.Text = self.ReplayFrame
    table.insert(self.ViewportFrameConnections, mouse.Move:Connect(function()
        if not dragStarted then return end
        local mouseX = mouse.X
        self:GoToTime(self.EndFrame.Time * XToTime(mouseX))
    end))
    table.insert(self.ViewportFrameConnections, mouse.Button1Up:Connect(function()
        if not dragStarted then return end
        dragStarted = false
        if wasPlaying then
            self:StartReplay(timescale)
        end
    end))
    local function UpdateTimeline()
        local scale: number = 1
        if self.ReplayFrameCount > 1 then
            scale = self.ReplayTime / self.EndFrame.Time
        end
        TimelineProgress.Size = UDim2.fromScale(scale, 1)
    end
    UpdateTimeline()
    table.insert(self.ViewportFrameConnections, self.ReplayFrameChanged:Connect(function()
        UpdateTimeline()
        UpdateTime()
        FrameNumCounter.Text = self.ReplayFrame
    end))
    self:UpdateReplayLocation(WorldModel)
    return ViewportFrame
end

function Module:Clear(): nil
    if self.ReplayVisible then
        self:HideReplay()
    end
    for _, inst in pairs(self.ActiveClones) do
        inst:Destroy()
    end
    for _, inst in pairs(self.StaticClones) do
        inst:Destroy()
    end
    for _, connection in ipairs(self.Connections) do
        if connection ~= nil then
            connection:Disconnect()
        end
    end
    self.StartFrame = nil
    self.EndFrame = nil
    self.CurrentFrame = nil
    self.AllActiveParts = {}
    self.PreviousRecordedState = {}
    self.StaticClones = {}
    self.ActiveClones = {}
    self.AllActiveClones = {}
    self.CurrentState = {}
    self.Connections = {}
    self.ReplayTime = 0
    self.ReplayFrame = 0
    self.ReplayT = 0
    self.ReplayFrameCount = 0
    if DEBUG then
        print("Recording Cleared")
    end
    return
end

function Module:Destroy(): nil
    self:Clear()
    for _, event in pairs(self.CustomEvents) do
        event:Destroy()
    end
    for _, connection in pairs(self.ViewportFrameConnections) do
        connection:Disconnect()
    end

    table.clear(self)
    if DEBUG then
        print("Recording Destroyed")
    end
    return
end


return Module