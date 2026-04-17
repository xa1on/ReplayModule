-- i am in typechecking purgatory.
-- death and damnation

--!strict
local DEBUG = true
local ID_ATTRIBUTE = "ReplayID"
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
--local UserInputService = game:GetService("UserInputService")

--   Numeric Mapping Constants
local P_CFRAME = 1
local P_TRANSPARENCY = 2
local P_COLOR = 3
local P_NOT_DESTROYED = 4
local P_FIELD_OF_VIEW = 5

local PROPERTY_MAP: {string} = {
    [P_CFRAME] = "CFrame",
    [P_TRANSPARENCY] = "Transparency",
    [P_COLOR] = "Color",
    [P_NOT_DESTROYED] = "NotDestroyed",
    [P_FIELD_OF_VIEW] = "FieldOfView",
}
--   Types
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
    [number]: any -- Use constants P_CFRAME, etc.
}

-- Stores Frame Info
export type FrameType = {
    Time: number, -- time in seconds the frame took place
    ModelChanges: {any}, -- flat array: {PartIndex, PropertyIndex, Value, ...}
}

-- Stores Replays
export type ReplayType = {
    -- Custom Properties
    Frames: {FrameType}, -- array of frames in the replay
    Settings: SettingsTypeStrict, -- settings applied to the replay
    ActiveModels: {Instance}, -- models that user specifies to keep track of
    ActualActiveModels: {Instance}, -- above, but the actual models being kept track of
    StaticModels: {Instance}, -- models that user specifies to not move and remain static througout the replay. these models are not tracked
    ActualStaticModels: {Instance}, -- above, but the actual static models
    PreviousRecordedState: {ModelStateType}, -- saves the previous recorded state of each active part
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
    RegisterChange: (ReplayType, number, number, any, nil|number) -> nil, -- registers a model change to the current frame
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
local function TableEmpty(t1: {any}): boolean
    local next = next
    if next(t1) == nil then
        return true
    end
    return false
end

-- Dumps deep table data into a string
local function DumpTable(t1: {any}): string
    local function Helper(t1: {any}, step: number): string
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

-- round a number to a certain decimal place
local function RoundToPlace(num: number, digits: number): number
    return math.round(num * (10 ^ digits)) / (10 ^ digits)
end

-- same as above but for cframes
local function RoundCFrame(cf: CFrame, digits: number): CFrame
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    return CFrame.new(
        RoundToPlace(x, digits), RoundToPlace(y, digits), RoundToPlace(z, digits),
        RoundToPlace(r00, digits), RoundToPlace(r01, digits), RoundToPlace(r02, digits),
        RoundToPlace(r10, digits), RoundToPlace(r11, digits), RoundToPlace(r12, digits),
        RoundToPlace(r20, digits), RoundToPlace(r21, digits), RoundToPlace(r22, digits)
    )
end

-- same but color3
local function RoundColor3(c: Color3, digits: number): Color3
    return Color3.new(RoundToPlace(c.R, digits), RoundToPlace(c.G, digits), RoundToPlace(c.B, digits))
end

-- Checks if two tables are shallow equal (idk)
local function ShallowEquals(t1: {any}, t2: {any}): boolean
    if #t1 ~= #t2 then return false end
    for index, inst in pairs(t1) do
        if t2[index] ~= inst then
            return false
        end
    end
    return true
end

-- Creates a shallow copy of tables
local function ShallowCopy(original: {any}): {any}
    local new: {any} = {}
    for index, inst in pairs(original) do
        new[index] = inst
    end
    return new
end

-- Check if two instances are identical-ish
local function InstanceIdentical(inst1: Instance, inst2: Instance): boolean
    local id: any = inst1:GetAttribute(ID_ATTRIBUTE)
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
        [P_NOT_DESTROYED] = inst:IsDescendantOf(game)
    }
    if inst:IsA("BasePart") then
        state[P_CFRAME] = RoundCFrame(inst.CFrame, rounding)
        state[P_COLOR] = RoundColor3(inst.Color, rounding)
        state[P_TRANSPARENCY] = RoundToPlace(1 - ((1 - inst.Transparency) * (1 - inst.LocalTransparencyModifier)), rounding)
    elseif inst:IsA("Camera") then
        state[P_CFRAME] = RoundCFrame(inst.CFrame, rounding)
        state[P_FIELD_OF_VIEW] = RoundToPlace(inst.FieldOfView, rounding)
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
    self.Frames = {}
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

function Module:RegisterChange(index: number, pindex: number, pval: any, frameNum: nil|number): nil
    frameNum = frameNum or self.ReplayFrame
    table.insert(self.Frames[frameNum].ModelChanges, index)
    table.insert(self.Frames[frameNum].ModelChanges, pindex)
    table.insert(self.Frames[frameNum].ModelChanges, pval)
    return
end

-- Registers an object as an ActiveModel
function Module:RegisterActive(model: Instance): number
    if not self.Recording then
        self.ActiveModels[#self.ActiveModels+1] = model
        return
    end
    self.ActualActiveModels[#self.ActualActiveModels + 1] = model
    local function Register(model: Instance): number
        if table.find(self.IgnoredModels, model) or model:IsA("Status") or not (model:IsA("BasePart") or model:IsA("Model") or model:IsA("Camera")) then return 0 end
        local index: number = #self.AllActiveParts + 1
        local state = GetState(model, self.Settings.Rounding)
        for pindex, pval in pairs(state) do
            self:RegisterChange(index, pindex, pval)
        end
        self.PreviousRecordedState[index] = state
        self.AllActiveParts[index] = model
        model:SetAttribute(ID_ATTRIBUTE, index)
        if self.ReplayFrame ~= 1 then
            self:RegisterChange(index, P_NOT_DESTROYED, false, 1)
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
    if #self.Frames > 0 then
        self:Clear()
    end
    self.PreviousRecordedState = {}
    self.Recording = true
    self.ReplayFrame = 1;
    self.ReplayFrameCount = 1;
    local currentTime: number = 0
    
    local recordFrameCounter: number = self.Settings.FrameFrequency -- Count before recording frame using FrameFrequency
    
    self.Frames[1] = {
        Time = 0,
        ModelChanges = {},
    }
    
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
        local newFrame: FrameType = {
            Time = RoundToPlace(currentTime, self.Settings.Rounding),
            ModelChanges = {},
        }
        
        -- Temporary swap to the new frame to use RegisterChange
        local currentFrameIdx = self.ReplayFrame
        self.ReplayFrame = #self.Frames + 1
        self.Frames[self.ReplayFrame] = newFrame
        
        local anyChange = false
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
                    self:RegisterChange(index, pindex, pval)
                    anyChange = true
                end
            end
        end
        
        if anyChange then
            self.ReplayFrameCount += 1
            -- ReplayFrame stays at the last one
        else
            self.Frames[self.ReplayFrame] = nil
            self.ReplayFrame = currentFrameIdx
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
    if not override and (self.Playing or self.Recording or not self.ReplayVisible or (frame == self.ReplayFrame and t == self.ReplayT)) then return end
    
    local function ApplyFlatChanges(changes: {any})
        for i: number = 1, #changes, 3 do
            local index: number = changes[i]
            local pindex: number = changes[i+1]
            local value: any = changes[i+2]
            
            if not self.CurrentState[index] then self.CurrentState[index] = {} end
            self.CurrentState[index][pindex] = value
        end
    end

    local startFrame: number = self.ReplayFrame
    local newStates: {ModelStateType} = {}
    
    if frame < startFrame then
        self.CurrentState = {}
        startFrame = 1
    else
        startFrame += 1
    end
    
    for currentFrameNum = startFrame, frame, 1 do
        ApplyFlatChanges(self.Frames[currentFrameNum].ModelChanges)
    end
    self.ReplayFrame = frame
    
    for index, _ in ipairs(self.AllActiveClones) do
        newStates[index] = if self.CurrentState[index] then ShallowCopy(self.CurrentState[index]) else {}
    end
    
    local f1: FrameType = self.Frames[frame]
    local f2: FrameType | nil = self.Frames[frame + 1]
    
    local epsilon: number = 10 ^ -self.Settings.Rounding
    
    -- Interpolation logic
    if f2 and t > 0 then
        local f2Changes = f2.ModelChanges
        for i: number = 1, #f2Changes, 3 do
            local index: number = f2Changes[i]
            local pindex: number = f2Changes[i+1]
            local value: any = f2Changes[i+2]
            
            if self.CurrentState[index] and self.CurrentState[index][pindex] then
                local v1: any = self.CurrentState[index][pindex]
                local v2: any = value
                
                if typeof(v2) == "CFrame" or typeof(v2) == "Color3" or typeof(v2) == "Vector3" then
                    newStates[index][pindex] = v1:Lerp(v2, t)
                elseif typeof(v2) ~= "boolean" then
                    newStates[index][pindex] = Lerp(v1, v2, t)
                end
            end
        end
        self.ReplayTime = t * (f2.Time - f1.Time) + f1.Time
    else
        self.ReplayTime = f1.Time
    end

    for index, clone in ipairs(self.AllActiveClones) do
        local state = newStates[index]
        if not state then continue end

        if state[P_NOT_DESTROYED] == false then
            if self.ActiveClones[index] then
                clone.Parent = nil
            end
            if clone:IsA("BasePart") then
                (clone :: BasePart).Transparency = 1
            end
            continue
        end

        for pindex, value in pairs(state) do
            if pindex == P_NOT_DESTROYED then
                if value and not clone:IsDescendantOf(game) then
                    clone.Parent = self.Settings.ReplayLocation
                end
            elseif pindex == P_CFRAME then
                if not clone.CFrame:FuzzyEq(value, epsilon) then
                    clone.CFrame = value
                end
            else
                local name = PROPERTY_MAP[pindex]
                if name then
                    if typeof(value) == "number" then
                        if math.abs(clone[name] - value) > epsilon then
                            clone[name] = value
                        end
                    elseif clone[name] ~= value then
                        clone[name] = value
                    end
                end
            end
        end
    end
    self.ReplayT = t
    self.CustomEvents.ReplayFrameChanged:Fire()
    return
end

function Module:GoToTime(time: number, override: boolean?): nil
    local currentFrameNum: number = self.ReplayFrame
    if self.ReplayTime > time then
        currentFrameNum = 1
    end
    while currentFrameNum < self.ReplayFrameCount and self.Frames[currentFrameNum].Time < time do
        currentFrameNum += 1
    end
    
    local f1: FrameType? = self.Frames[currentFrameNum - 1]
    local f2: FrameType = self.Frames[currentFrameNum]
    
    if f1 then
        local gap: number = f2.Time - f1.Time
        if gap > 0 then
            local prevGap: number = if currentFrameNum > 2 then f1.Time - self.Frames[currentFrameNum - 2].Time else gap
            local window: number = math.min(gap, prevGap)
            local t: number = math.clamp((time - (f2.Time - window)) / window, 0, 1)
            self:GoToFrame(currentFrameNum - 1, t, override)
        else
            self:GoToFrame(currentFrameNum, 0, override)
        end
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
    if self.ReplayFrame >= self.ReplayFrameCount then
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
        if currentTime < self.Frames[#self.Frames].Time then
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
            Time.Text = ConvertTime(self.ReplayTime) .. " / " .. ConvertTime(self.Frames[#self.Frames].Time)
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
            self:GoToTime(self.Frames[#self.Frames].Time * XToTime(input.Position.X))
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
        local mouseX: number = mouse.X
        self:GoToTime(self.Frames[#self.Frames].Time * XToTime(mouseX))
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
            scale = self.ReplayTime / self.Frames[#self.Frames].Time
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
    self.Frames = {}
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