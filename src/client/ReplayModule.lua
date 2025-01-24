
-- i am in typechecking purgatory.
-- death and damnation

--!strict
local DEBUG = true
local ID_ATTRIBUTE = "ReplayID"
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Module
local m = {}

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
	["Time"]: number, -- time in seconds the frame took place
	ModelChanges: {ModelStateType} -- table containing the changes in model properties, keys representing the index the model is stored inside activeModels
}

-- Stores Custom Events
type CustomEventsType = {
	[string]: BindableEvent
}

-- Stores Replays
export type ReplayType = {
    -- Custom Properties
	Frames: {FrameType}, -- stores all the frames in the replay
	["Settings"]: SettingsTypeStrict, -- settings applied to the replay
	ActiveModels: {Instance}, -- all models whose properties are kept track of
    StaticModels: {Instance},
    StaticClones: {Instance},
	IgnoredModels: {Instance}, -- all models who are not rendered
	AllActiveParts: {Instance}, -- all objects, including activeModel children that are being kept track of
	ActiveClones: {Instance}, -- clones of all active models
	AllActiveClones: {Instance}, -- actual parts associated with all the active parts in the clones
    CurrentState: {ModelStateType},
	Connections: {RBXScriptConnection}, -- list of connections being used by the replay. they are disconnected and cleared after recording and replay
	
	-- Events
	RecordingStarted: RBXScriptSignal, -- fires when recording starts
	RecordingEnded: RBXScriptSignal, -- fires when recording ends
    ReplayShown: RBXScriptSignal,
    ReplayHidden: RBXScriptSignal,
	ReplayStarted: RBXScriptSignal, -- fires when replay is started
	ReplayEnded: RBXScriptSignal, -- fires when replay is ended
	ReplayFrameChanged: RBXScriptSignal, -- fires when the current frame of the replay is changed
	
	-- Properties
	Recording: boolean, -- represents whether or not the replay is recording 
	Playing: boolean, -- represents whether or not the replay is being played
    ReplayVisible: boolean, -- represents whether or not the replay is visible
	RecordingTime: number, -- number of seconds in the recording is
	RecordingFrame: number, -- current frame number of the recording
	ReplayTime: number, -- number of seconds in the replay is.
	ReplayFrame: number, -- current frame number of the replay
    ReplayT: number, -- number from 0 - 1 representing the progress between the current frame and the subsequent frame
	
	-- Methods
	StartRecording: (ReplayType) -> nil, -- starts recording the replay
	StopRecording: (ReplayType) -> nil, -- stops recording the replay
    UpdateReplayLocation: (ReplayType) -> nil, -- sets the location of the replay to Replay.ReplayID if replay is visible
	ShowReplay: (ReplayType, boolean?) -> nil, -- puts replay into ReplayLocation. makes the replay visible
	HideReplay: (ReplayType) -> nil, -- hides the replay. it gets removed from replaylocation
	GoToFrame: (ReplayType, number, number, boolean?) -> nil, -- go to a specific frame. t (number 0 to 1) represents the progress from that frame to the subsequent frame
    GoToTime: (ReplayType, number, number, boolean?) -> nil, -- go to a specific time in a replay
	StopReplay: (ReplayType) -> nil, -- stops the replay on the current frame
	StartReplay: (ReplayType, number) -> nil, -- starts the replay on the current frame
    CreateViewport: (ReplayType, Instance) -> ViewportFrame, -- Creates a ViewportFrame for the replay. Sets the ReplayLocation to the ViewportFrame and returns the ViewportFrame
	Clear: (ReplayType) -> nil, -- clears the recording off the replay
	Destroy: (ReplayType) -> nil -- destroys the replay. the whole replay will be cleared
}





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
local function StoreCFrameToCFrame(cf1: StoredCFrame): CFrame
	return CFrame.new(table.unpack(cf1))
end

-- Converts a CFrame to a StoredCFrame
local function CFrameToStoreCFrame(cf1: CFrame): StoredCFrame
	local temp: StoredCFrame = table.pack(cf1:GetComponents())
	temp["__type"] = "StoredCFrame" -- Required for type detection. ignore warning
	return temp
end

-- Create instance Type with Name as a child of Parent if it doesn't already exist
local function CreateIfNotExist(class: string, name: string, parent: Instance): Instance
	for _, inst in ipairs(parent:GetChildren()) do
		if inst.ClassName == class and inst.Name == name then
			return inst
		end
	end
	local temp: Instance = Instance.new(class, parent)
	temp.Name = name
	return temp
end

-- same as above but the opposite
local function DestroyIfExist(class: string, name: string, parent: Instance): nil
	for _, inst in ipairs(parent:GetChildren()) do
		if inst.ClassName == class and inst.Name == name then
			return inst:Destroy()
		end
	end
	return
end

-- round a number to a certain decimal place
local function RoundToPlace(num: number, digits: number): number
	return math.round(num * (10 ^ digits)) / (10 ^ digits)
end

-- same as above but for cframes
local function RoundCFrame(cf: CFrame, digits: number): StoredCFrame
	local cframeTable: StoredCFrame = CFrameToStoreCFrame(cf)
	for index, value in ipairs(cframeTable) do
		cframeTable[index] = RoundToPlace(value, digits) -- cframes only contain numbers for the indexed part of the table. ignore warning
	end
	return cframeTable
end

-- same but color3
local function RoundColor3(c: Color3, digits: number): Color3
	return Color3.new(RoundToPlace(c.R, digits), RoundToPlace(c.G, digits), RoundToPlace(c.B, digits))
end

-- self-explanitory. got too lazy to do color3 interp
local function Color3ToVector3(c: Color3): Vector3
	return Vector3.new(c.R, c.G, c.B)
end

local function Vector3ToColor3(c: Vector3): Color3
	return Color3.new(c.X, c.Y, c.Z)
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
		state["Transparency"] = RoundToPlace(inst.Transparency, rounding)
	elseif inst:IsA("Camera") then
		state["CFrame"] = RoundCFrame(inst.CFrame, rounding)
		state["FieldOfView"] = RoundToPlace(inst.FieldOfView, rounding)
	end
	return state
end

-- Gets the type of an item (includes custom types)
local function GetType(item): string
	local suggestedType: string = typeof(item)
	if suggestedType == "table" and item["__type"] then
		return item["__type"]
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
    result ..= tostring(math.round(time))
    return result
end




--   Interpolation

-- catmull rom interpolation for numbers and vectors
local function CRInterp(p0: number | Vector3, p1: number | Vector3, p2: number | Vector3, p3: number | Vector3, t: number, tension: number, alpha: number)
	local function cubic(t: number, a: number, b: number, c: number, d: number): number
		return d + t*(c + t*(b + t*a))
	end
	local function tj(pi: number | Vector3, pf: number | Vector3)
		if pi == pf then return 1 end
		if type(pi) == "number" then
			return pi-pf
		elseif typeof(pi) == "Vector3" and typeof(pf) == "Vector3" then
			return (pi-pf).Magnitude
		end
	end
	local t0 = 0;
	local t1 = t0 + tj(p0,p1)^alpha;
	local t2 = t1 + tj(p1,p2)^alpha;
	local t3 = t2 + tj(p2,p3)^alpha;
	local m1 = (1.0 - tension) * (t2 - t1) * ((p1 - p0) / (t1 - t0) - (p2 - p0) / (t2 - t0) + (p2 - p1) / (t2 - t1));
	local m2 = (1.0 - tension) * (t2 - t1) * ((p2 - p1) / (t2 - t1) - (p3 - p1) / (t3 - t1) + (p3 - p2) / (t3 - t2));
	return cubic(t, 2*(p1 - p2) + m1 + m2, -3*(p1 - p2) - m1 - m1 - m2, m1, p1)
end

-- linear interpolation method for numbers and vectors
local function Lerp(p0: number | Vector3, p1: number | Vector3, p2: number | Vector3, p3: number | Vector3, t: number, tension: number, alpha: number)
	return t * (p2 - p1) + p1 -- again, can be vector3 or number, doesnt matter which it is
end

-- using interpolation on a cframe
local function InterpolateCF(p0: CFrame, p1: CFrame, p2: CFrame, p3: CFrame, t: number, tension: number, alpha: number, func)
	local newpv: Vector3 = func(p0.Position, p1.Position, p2.Position, p3.Position, t, tension, alpha)
	local newlv: Vector3 = func(p0.LookVector, p1.LookVector, p2.LookVector, p3.LookVector, t, tension, alpha)
	return CFrame.new(newpv, newpv + newlv)
end

-- setting which interpolation method to use
local InterpMethod: (number | Vector3, number | Vector3, number | Vector3, number | Vector3, number, number, number)->number? = Lerp




-- Create a new Replay Object
function m.New(s: SettingsType, ActiveModels: {Instance}, StaticModels: {Instance}?, IgnoredModels: {Instance}?): ReplayType
	local CustomEvents: CustomEventsType = {
		RecordingStarted = Instance.new("BindableEvent"),
		RecordingEnded = Instance.new("BindableEvent"),
        ReplayShown = Instance.new("BindableEvent"),
        ReplayHidden = Instance.new("BindableEvent"),
		ReplayStarted = Instance.new("BindableEvent"),
		ReplayEnded = Instance.new("BindableEvent"),
		ReplayFrameChanged = Instance.new("BindableEvent")
	}

    local ViewportFrameConnections: {RBXScriptConnection} = {}
	
	local Replay: ReplayType = {  -- The functions are defined later on ignore warning
		Frames = {},
		["Settings"] = NormalizeSettings(s),
		["ActiveModels"] = ActiveModels,
		["AllActiveParts"] = {},
        ["StaticModels"] = StaticModels or {},
        ["StaticClones"] = {},
		["IgnoredModels"] = IgnoredModels or {},
		["ActiveClones"] = {},
		["AllActiveClones"] = {},
        ["CurrentState"] = {},
		["Connections"] = {},
		RecordingStarted = CustomEvents.RecordingStarted.Event,
		RecordingEnded = CustomEvents.RecordingEnded.Event,
		ReplayStarted = CustomEvents.ReplayStarted.Event,
        ReplayShown = CustomEvents.ReplayShown.Event,
        ReplayHidden = CustomEvents.ReplayHidden.Event,
		ReplayEnded = CustomEvents.ReplayEnded.Event,
		ReplayFrameChanged = CustomEvents.ReplayFrameChanged.Event,
		Recording = false,
		Playing = false,
        ReplayVisible = false,
		RecordingTime = 0,
		RecordingFrame = 0,
		ReplayTime = 0,
		ReplayFrame = 0,
	}
	
	-- Assuming all Replays initially contain no frames
	function Replay:StartRecording(): nil
		if Replay.Recording or Replay.Playing then return end
		Replay.Recording = true
		Replay.Frames = {}
		Replay.AllActiveParts = {}
		Replay.ActiveClones = {}
		Replay["Connections"] = {} -- Contains all the connections that need to be disconnected after recording is done
		Replay.RecordingFrame = 1;
		local startTime: number = time()
		
		local recordFrameCounter: number = Replay.Settings.FrameFrequency -- Count before recording frame using FrameFrequency
		local previousStates: {ModelStateType} = {} -- Contains the previous state of all active parts
		local initalFrame: FrameType = { -- Inital frame
			["Time"] = 0,
			ModelChanges = {}
		}
		local newFrame: FrameType = {
			["Time"] = 0,
			ModelChanges = {}
		}

		Replay.Frames[Replay.RecordingFrame] = initalFrame

		local function Register(model:Instance): number
			if table.find(Replay.IgnoredModels, model) or model:IsA("Status") or not (model:IsA("BasePart") or model:IsA("Model") or model:IsA("Camera")) then return 0 end
			local index: number = #Replay.AllActiveParts + 1
			previousStates[index] = GetState(model, Replay.Settings.Rounding)
			Replay.Frames[Replay.RecordingFrame].ModelChanges[index] = GetState(model, Replay.Settings.Rounding)
			Replay.AllActiveParts[index] = model
			model:SetAttribute(ID_ATTRIBUTE, index)
			if Replay.RecordingFrame ~= 1 then
				Replay.Frames[1].ModelChanges[index] = {
					["NotDestroyed"] = false
				}
			end
			return index
		end

		-- If workspace is contained, replace active models with only children of workspace
		for _, inst in ipairs(Replay.ActiveModels) do
			if inst == workspace then
				Replay.ActiveModels = {}
				for _, inst2 in ipairs(workspace:GetChildren()) do
					if not inst2:IsA("Terrain") and not table.find(Replay.IgnoredModels, inst2) then
						table.insert(Replay.ActiveModels, inst2)
					end
				end
				break
			end
		end
		
		
		-- register all models in activemodels and all it's descendents
		for _, inst in ipairs(Replay.ActiveModels) do
			local id: number = Register(inst)
			for _, inst2 in ipairs(inst:GetDescendants()) do
				Register(inst2)
			end
			-- clone activemodel, then assign allactiveclones and activeclones
			inst.Archivable = true
			for _, inst2 in ipairs(inst:GetDescendants()) do
				inst2.Archivable = true
			end
			local clone = inst:Clone()
			if clone == nil and DEBUG then
				error("Failed to clone: " .. inst:GetFullName())
			end
			GhostPart(clone)
			Replay.ActiveClones[id] = clone
			Replay.AllActiveClones[id] = clone
			for _, inst2 in ipairs(clone:GetDescendants()) do
				GhostPart(inst2)
				id = inst2:GetAttribute(ID_ATTRIBUTE)
				if id ~= nil then
					Replay.AllActiveClones[id] = inst2
				end
			end
			table.insert(Replay["Connections"], inst.DescendantAdded:Connect(function(desc)
				desc.Archivable = true
				local id = Register(desc)
				local clone2 = desc:Clone()
				if clone2 == nil and DEBUG then
					error("Failed to clone: " .. desc:GetFullName())
				end
				GhostPart(clone2)
				clone2.Parent = FindDescendantWhichIs(clone, desc.Parent) -- well, i mean, if a descendant was added, that means it has a parent, right? why are you giving a warning here
				if id ~= 0 then
					Replay.AllActiveClones[id] = clone2
				end
			end))
		end

        for _, inst in ipairs(Replay.StaticModels) do
            local clone = inst:Clone()
            GhostPart(clone)
            table.insert(Replay.StaticClones, clone)
        end

		if DEBUG then
			print("Recording Started")
			--print(DumpTable(Replay))
			--print(DumpTable(previousStates))
		end
		CustomEvents.RecordingStarted:Fire()

		--   Actual recording part
		local newState: ModelStateType -- temp table containing the state of the current part
		local change: boolean -- temp variable used to indicate whether or not a value has changed
		table.insert(Replay["Connections"], RunService.RenderStepped:Connect(function()
			recordFrameCounter -= 1
			Replay.RecordingTime = time() - startTime
			if recordFrameCounter == 0 then
				recordFrameCounter = Replay.Settings.FrameFrequency
			else
				return
			end
			newFrame = {
				["Time"] = RoundToPlace(Replay.RecordingTime, Replay.Settings.Rounding),
				ModelChanges = {}
			}
			for index, inst in ipairs(Replay.AllActiveParts) do
				newState = GetState(inst, Replay.Settings.Rounding)
				for pindex, pval in pairs(newState) do
					if typeof(pval) == "table" then
						change = not ShallowEquals(pval, previousStates[index][pindex])
					else
						change = previousStates[index][pindex] ~= pval
					end
					if change then
						previousStates[index][pindex] = pval
						if not newFrame.ModelChanges[index] then
							newFrame.ModelChanges[index] = {}
						end
						newFrame.ModelChanges[index][pindex] = pval
					end
				end
				if not TableEmpty(newFrame.ModelChanges) then
					Replay.RecordingFrame += 1
					Replay.Frames[Replay.RecordingFrame] = newFrame
				end
			end

		end))
		return
	end

	function Replay:StopRecording(): nil
		if not Replay.Recording then return end
		CustomEvents.RecordingEnded:Fire()
		for _, connection in ipairs(Replay["Connections"]) do
			if connection ~= nil then
				connection:Disconnect()
			end
		end
		Replay["Connections"] = {}
		Replay.Recording = false
		if DEBUG then
			print("Recording Stopped")
			--print(DumpTable(Replay))
			--print(DumpTable(Replay.AllActiveParts))
			--print(DumpTable(Replay.AllActiveClones))
		end
		return
	end

    function Replay:UpdateReplayLocation(): nil
        if not Replay.ReplayVisible then return end
        for _, inst in pairs(Replay.ActiveClones) do
            inst.Parent = Replay.Settings.ReplayLocation
        end
        for _, inst in pairs(Replay.StaticClones) do
            inst.Parent = Replay.Settings.ReplayLocation
        end
        if DEBUG then
			print("Replay Location Updated")
		end
        return
    end

    function Replay:ShowReplay(override: boolean?): nil
        if not override and (Replay.Playing or Replay.Recording or Replay.ReplayVisible) then return end
        for _, inst in pairs(Replay.ActiveClones) do
            inst.Parent = Replay.Settings.ReplayLocation
        end

        for _, inst in pairs(Replay.StaticClones) do
            inst.Parent = Replay.Settings.ReplayLocation
        end
        Replay.ReplayVisible = true
        CustomEvents.ReplayShown:Fire()
        if Replay.ReplayFrame == 0 then
            Replay:GoToFrame(1, 0)
        end
        for _, clone in ipairs(Replay.AllActiveClones) do
			if clone:IsA("Camera") then
				clone.CameraType = Enum.CameraType.Scriptable
				if Replay.Settings.ReplayLocation.Parent and Replay.Settings.ReplayLocation.Parent:IsA("ViewportFrame") and Replay.Settings.ReplayLocation:IsA("WorldModel") then
					Replay.Settings.ReplayLocation.Parent.CurrentCamera = clone
				elseif Replay.Settings.ReplayLocation:IsA("ViewportFrame") then
					Replay.Settings.ReplayLocation.CurrentCamera = clone -- theres gotta be a better way of doing this
				end
			end
		end
        if DEBUG then
            print("Replay Shown")
        end
        return
    end

    function Replay:HideReplay(): nil
        if Replay.Playing or Replay.Recording or not Replay.ReplayVisible then return end
        for _, clone in pairs(Replay.ActiveClones) do -- ActiveClones is not continuous sometimes
			clone.Parent = nil
		end
        for _, clone in pairs(Replay.StaticClones) do -- ActiveClones is not continuous sometimes
			clone.Parent = nil
		end
        Replay.ReplayVisible = false
        CustomEvents.ReplayHidden:Fire()
        if DEBUG then
            print("Replay Hidden")
        end
        return
    end

	function Replay:GoToFrame(frame: number, t: number, override: boolean?): nil
        if frame < 1 or frame > #Replay.Frames then error("Frame out of range. [1, " .. #Replay.Frames .. "]") end
        if not override and (Replay.Playing or Replay.Recording or not Replay.ReplayVisible or frame == Replay.ReplayFrame) then return end
        local function SetCurrentState(state: ModelStateType, index: number): nil
			if state == nil then return end
            if not Replay.CurrentState[index] then Replay.CurrentState[index] = {} end
			for name, value in pairs(state) do
				if value ~= nil then
                    Replay.CurrentState[index][name] = value
				end
			end
			return
		end
        local startFrame: number = Replay.ReplayFrame
        local f1: FrameType = Replay.Frames[frame]
        local f2: FrameType = Replay.Frames[frame + 1]
        local newStates: {ModelStateType} = {}
        if frame < startFrame then
            Replay.CurrentState = {}
        end
        if TableEmpty(Replay.CurrentState)  then
            startFrame = 1
        end
        for index, _ in ipairs(Replay.AllActiveClones) do
            for currentFrame = startFrame, frame, 1 do
                SetCurrentState(Replay.Frames[currentFrame].ModelChanges[index], index)
            end
            newStates[index] = if Replay.CurrentState[index] then ShallowCopy(Replay.CurrentState[index]) else {}
        end
        
        local values: {}
        for index, clone in ipairs(Replay.AllActiveClones) do
            if Replay.CurrentState[index]["NotDestroyed"] then
                if f2 then
                    local f0 = if frame > 1 then Replay.Frames[frame - 1] else f1
                    local f3 = if frame + 2 <= #Replay.Frames then Replay.Frames[frame + 2] else f2
                    if f2.ModelChanges[index] then
                        values = {}
                        for name, value in pairs(f2.ModelChanges[index]) do
                            if Replay.CurrentState[index][name] then
                                values[2] = Replay.CurrentState[index][name]
                                values[3] = value
                                values[1] = (if f0.ModelChanges[index] then f0.ModelChanges[index][name] else values[2]) or values[2]
                                values[4] = (if f3.ModelChanges[index] then f3.ModelChanges[index][name] else values[3]) or values[3]
                                if GetType(value) == "StoredCFrame" then
                                    for index2, value2 in ipairs(values) do
                                        values[index2] = StoreCFrameToCFrame(value2)
                                    end
                                    newStates[index][name] = InterpolateCF(values[1], values[2], values[3], values[4], t, 0, 0, InterpMethod) -- Ignore warnings here. GetType should protect from any errors
                                elseif GetType(value) == "Color3" then
                                    newStates[index][name] = Vector3ToColor3(InterpMethod(Color3ToVector3(values[1]), Color3ToVector3(values[2]), Color3ToVector3(values[3]), Color3ToVector3(values[4]), t, 0, 0))
                                elseif GetType(value) ~= "boolean" then
                                    newStates[index][name] = InterpMethod(values[1], values[2], values[3], values[4], t, 0, 0)
                                end
                            end
                        end
                    end
                    Replay.ReplayTime = t * (f2.Time - f1.Time) + f1.Time
                else
                    t = 0
                    Replay.ReplayTime = f1.Time
                end
            end
            for name, value in pairs(newStates[index]) do
                if name == "NotDestroyed" then
                    if value then
                        if not clone:IsDescendantOf(game) then
                            clone.Parent = Replay.Settings.ReplayLocation
                        end
                        if clone:IsA("BasePart") then
                            clone.Transparency = Replay.CurrentState[index]["Transparency"] or clone.Transparency
                        end
                    elseif clone:IsA("BasePart") then
                        clone.Transparency = 1
                    end
                elseif GetType(value) == "StoredCFrame" then
                    clone[name] = StoreCFrameToCFrame(value)
                else
                    clone[name] = value
                end
            end
        end
        Replay.ReplayT = t
        Replay.ReplayFrame = frame
        CustomEvents.ReplayFrameChanged:Fire()
        return
	end

    function Replay:GoToTime(time: number, override: boolean?): nil
        local currentFrame: number = 1
        while Replay.Frames[currentFrame].Time < time and currentFrame < #Replay.Frames do
            currentFrame += 1
        end
        local f1: FrameType = Replay.Frames[currentFrame - 1]
		local f2: FrameType = Replay.Frames[currentFrame]
        if f1 then
            Replay:GoToFrame(currentFrame - 1, (time - f1.Time) / (f2.Time - f1.Time), override)
        else
            Replay:GoToFrame(currentFrame, 0, override)
        end
        return
    end

	function Replay:StartReplay(timescale: number): nil
		if Replay.Playing or Replay.Recording then return end
		Replay["Connections"] = {}
		if not Replay.ReplayVisible then
            Replay:ShowReplay(true)
        end
        if Replay.ReplayFrame > #Replay.Frames then
            Replay:GoToFrame(1, 0)
        end
		local startTime: number
        Replay.Playing = true
		if DEBUG then
			print("Replay Started")
		end
		CustomEvents.ReplayStarted:Fire()
		startTime = time() - (Replay.ReplayTime / timescale)
        local currentTime: number = 0
		Replay["Connections"][1] = RunService.RenderStepped:Connect(function()
            currentTime = (time() - startTime) * timescale
            if currentTime < Replay.Frames[#Replay.Frames].Time then
                Replay:GoToTime(currentTime, true)
            else
                Replay:GoToFrame(#Replay.Frames, 0, true)
                Replay:StopReplay()
            end
		end)
		return
	end

    function Replay:StopReplay(): nil
		if not Replay.Playing then return end
		CustomEvents.ReplayEnded:Fire()
		Replay["Connections"][1]:Disconnect()
		Replay["Connections"] = {}
		Replay.Playing = false
		if DEBUG then
			print("Replay Stopped")
		end
		return
	end

    function Replay:CreateViewport(parent: Instance): ViewportFrame
        local timescale: number = 1
        local dragStarted: boolean = false
        local wasPlaying: boolean = false
        local mouse: Mouse= game:GetService("Players").LocalPlayer:GetMouse()

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
        table.insert(ViewportFrameConnections, BackButton.MouseButton1Click:Connect(function()
            if Replay.Recording or #Replay.Frames < 1 then return end
            Replay:GoToFrame(1, 0, true)
            if not Replay.Playing then
                Replay:StartReplay(timescale)
            end
        end))
        local ForwardButton = Instance.new("ImageButton", BottomFrame)
        ForwardButton.AnchorPoint = Vector2.new(0.5, 0.5)
        ForwardButton.BackgroundTransparency = 1
        ForwardButton.Position = UDim2.fromScale(0.54, 0.5)
        ForwardButton.Size = UDim2.fromScale(1, 1)
        ForwardButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
        ForwardButton.Image = "rbxasset://textures/AnimationEditor/button_control_next.png"
        table.insert(ViewportFrameConnections, ForwardButton.MouseButton1Click:Connect(function()
            if Replay.Recording or #Replay.Frames < 1 then return end
            if Replay.Playing then
                Replay:StopReplay()
            end
            Replay:GoToFrame(#Replay.Frames, 0, true)
        end))
        local PlayButton = Instance.new("ImageButton", BottomFrame)
        PlayButton.AnchorPoint = Vector2.new(0.5, 0.5)
        PlayButton.BackgroundTransparency = 1
        PlayButton.Position = UDim2.fromScale(0.50, 0.5)
        PlayButton.Size = UDim2.fromScale(1, 1)
        PlayButton.SizeConstraint = Enum.SizeConstraint.RelativeYY
        PlayButton.Image = "rbxasset://textures/DeveloperFramework/MediaPlayerControls/play_button.png"
        table.insert(ViewportFrameConnections, PlayButton.MouseButton1Click:Connect(function()
            if Replay.Recording or #Replay.Frames < 1 then return end
            if Replay.Playing then
                Replay:StopReplay()
            else
                Replay:StartReplay(timescale)
            end
        end))
        table.insert(ViewportFrameConnections, Replay.ReplayStarted:Connect(function()
            PlayButton.Image = "rbxasset://textures/DeveloperFramework/MediaPlayerControls/pause_button.png"
        end))
        table.insert(ViewportFrameConnections, Replay.ReplayEnded:Connect(function()
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
            if #Replay.Frames < 1 then
                Time.Text = "0:00 / 0:00"
            else
                Time.Text = ConvertTime(Replay.ReplayTime) .. " / " .. ConvertTime(Replay.Frames[#Replay.Frames].Time)
            end
        end
        UpdateTime()
        local TimescaleInput = Instance.new("TextBox", BottomFrame)
        TimescaleInput.BorderSizePixel = 0
        TimescaleInput.AnchorPoint = Vector2.new(1, 0.5)
        TimescaleInput.BackgroundTransparency = 1
        TimescaleInput.Position = UDim2.fromScale(0.95, 0.5)
        TimescaleInput.Size = UDim2.fromScale(2, 0.5)
        TimescaleInput.SizeConstraint = Enum.SizeConstraint.RelativeYY
        TimescaleInput.FontFace = Font.fromName("SourceSansPro", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
        TimescaleInput.TextColor3 = Color3.new(1, 1, 1)
        TimescaleInput.TextScaled = true
        TimescaleInput.TextSize = 12
        TimescaleInput.Text = tostring(timescale)
        TimescaleInput.PlaceholderText = "Timescale"
        table.insert(ViewportFrameConnections, TimescaleInput.FocusLost:Connect(function()
            if not tonumber(TimescaleInput.Text) then
                TimescaleInput = tostring(timescale)
            else
                timescale = tonumber(TimescaleInput.Text)
                if Replay.Playing then
                    Replay:StopReplay()
                    Replay:StartReplay(timescale)
                end
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

        table.insert(ViewportFrameConnections, Timeline.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                if Replay.Recording or #Replay.Frames < 1 then return end
                wasPlaying = Replay.Playing
                dragStarted = true
                if wasPlaying then
                    Replay:StopReplay()
                end
                Replay:GoToTime(Replay.Frames[#Replay.Frames].Time * XToTime(input.Position.X))
            end
        end))
        table.insert(ViewportFrameConnections, mouse.Move:Connect(function()
            if not dragStarted then return end
            local mouseX = mouse.X
            Replay:GoToTime(Replay.Frames[#Replay.Frames].Time * XToTime(mouseX))
        end))
        table.insert(ViewportFrameConnections, mouse.Button1Up:Connect(function()
            if not dragStarted then return end
            dragStarted = false
            if wasPlaying then
                Replay:StartReplay(timescale)
            end
        end))

        local function UpdateTimeline()
            local scale: number = 1
            if #Replay.Frames > 1 then
                scale = Replay.ReplayTime / Replay.Frames[#Replay.Frames].Time
            end
            TimelineProgress.Size = UDim2.fromScale(scale, 1)
        end
        UpdateTimeline()
        table.insert(ViewportFrameConnections, Replay.ReplayFrameChanged:Connect(function()
            UpdateTimeline()
            UpdateTime()
        end))

        


        Replay.Settings.ReplayLocation = WorldModel
        if Replay.ReplayShown then
            Replay:UpdateReplayLocation()
        end
        return ViewportFrame
    end
	
	function Replay:Clear(): nil
        if Replay.ReplayVisible then
            Replay:HideReplay()
        end
		for _, connection in ipairs(Replay["Connections"]) do
			if connection ~= nil then
				connection:Disconnect()
			end
		end
		Replay["Connections"] = {}
		Replay["Frames"] = {}
		if DEBUG then
			print("Recording Cleared")
		end
		return
	end
	
	function Replay:Destroy(): nil
		Replay:Clear()
		for _, inst in pairs(Replay.ActiveClones) do
			inst:Destroy()
		end
        for _, inst in pairs(Replay.StaticClones) do
            inst:Destroy()
        end
		for _, event in pairs(CustomEvents) do
			event:Destroy()
		end
        for _, connection in pairs(ViewportFrameConnections) do
            connection:Disconnect()
        end
		
		table.clear(Replay)
		if DEBUG then
			print("Recording Destroyed")
		end
		return
	end
	
	
	
	return Replay
end



return m