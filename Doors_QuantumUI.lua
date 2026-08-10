--[[
    Doors 辅助脚本 v3.0 (QuantumUI)
    基于 LX Doors v3 / LOLHAX 源码重写 - 完整功能移植
    功能：ESP、自动交互、自动躲藏、反实体、绕过、通知、矿井车、锚点解谜、移动、全亮等
    PlaceIds:
        6839808510 - Doors (Hotel)
        7894711641 - Doors (Floor 2 / Mines)
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD — 防止重复注入
-- ══════════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

if _G.QuantumUI_Instance then
    pcall(function() _G.QuantumUI_Instance:Destroy() end)
    _G.QuantumUI_Instance = nil
end
if _G.QuantumUI_Window then
    pcall(function() _G.QuantumUI_Window:Destroy() end)
    _G.QuantumUI_Window = nil
end
for _, child in ipairs(CoreGui:GetChildren()) do
    if child:IsA("ScreenGui") and child.Name:sub(1, 9) == "QuantumUI_" then
        pcall(function() child:Destroy() end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 1. LOAD LIBRARY
-- ══════════════════════════════════════════════════════════════════
local success, QuantumUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"))()
end)

if not success then
    warn("[Doors] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[Doors] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[Doors] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[Doors] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. ROBLOX SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Camera = workspace.CurrentCamera
local Workspace = workspace
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Lighting = game:GetService("Lighting")

-- ══════════════════════════════════════════════════════════════════
-- 3. DATA STRUCTURES — 来自 LX Doors v3 实体表
-- ══════════════════════════════════════════════════════════════════
local EntityTable = {
    ["Names"] = {"BackdoorRush", "BackdoorLookman", "RushMoving", "AmbushMoving", "Eyes", "JeffTheKiller", "A60", "A120"},
    ["SideNames"] = {"FigureRig", "GiggleCeiling", "GrumbleRig", "Snare"},
    ["ShortNames"] = {
        ["BackdoorRush"] = "Blitz",
        ["JeffTheKiller"] = "Jeff The Killer"
    },
    ["NotifyMessage"] = {
        ["GloombatSwarm"] = "Gloombats in next room!"
    },
    ["NotifyReason"] = {
        ["A60"] = { ["Image"] = "12350986086" },
        ["A120"] = { ["Image"] = "12351008553" },
        ["BackdoorRush"] = { ["Image"] = "11102256553" },
        ["RushMoving"] = { ["Image"] = "11102256553" },
        ["AmbushMoving"] = { ["Image"] = "10938726652" },
        ["Eyes"] = { ["Image"] = "10865377903", ["Spawned"] = true },
        ["BackdoorLookman"] = { ["Image"] = "16764872677", ["Spawned"] = true },
        ["JeffTheKiller"] = { ["Image"] = "98993343", ["Spawned"] = true },
        ["GloombatSwarm"] = { ["Image"] = "108578770251369", ["Spawned"] = true }
    },
    ["NoCheck"] = { "Eyes", "BackdoorLookman", "JeffTheKiller" },
    ["InfCrucifixVelocity"] = {
        ["RushMoving"] = { threshold = 52, minDistance = 55 },
        ["RushNew"] = { threshold = 52, minDistance = 55 },
        ["AmbushMoving"] = { threshold = 70, minDistance = 80 }
    },
    ["AutoWardrobe"] = {
        ["Entities"] = { "RushMoving", "AmbushMoving", "BackdoorRush", "A60", "A120" },
        ["Distance"] = {
            ["RushMoving"] = 135, ["BackdoorRush"] = 135,
            ["AmbushMoving"] = 155, ["A60"] = 200, ["A120"] = 200,
        },
        ["DistanceLoader"] = {
            ["RushMoving"] = 175, ["BackdoorRush"] = 175,
            ["AmbushMoving"] = 200, ["A60"] = 200, ["A120"] = 200,
        }
    }
}

local HidingPlaceName = {
    ["Hotel"] = "Closet", ["Backdoor"] = "Closet", ["Fools"] = "Closet",
    ["Rooms"] = "Locker", ["Mines"] = "Locker", ["Retro"] = "Closet"
}

local CutsceneExclude = { "FigureHotelChase", "Elevator1", "MinesFinale" }

local PromptTable = {
    GamePrompts = {},
    Aura = {
        ["ActivateEventPrompt"] = false, ["AwesomePrompt"] = true,
        ["FusesPrompt"] = true, ["HerbPrompt"] = false,
        ["LeverPrompt"] = true, ["LootPrompt"] = false,
        ["ModulePrompt"] = true, ["SkullPrompt"] = false,
        ["UnlockPrompt"] = true, ["ValvePrompt"] = false, ["PropPrompt"] = true
    },
    AuraObjects = { "Lock", "Button" },
    Clip = {
        "AwesomePrompt", "FusesPrompt", "HerbPrompt", "HidePrompt",
        "LeverPrompt", "LootPrompt", "ModulePrompt", "Prompt",
        "PushPrompt", "SkullPrompt", "UnlockPrompt", "ValvePrompt"
    },
    ClipObjects = { "LeverForGate", "LiveBreakerPolePickup", "LiveHintBook", "Button" },
    Excluded = {
        Prompt = { "HintPrompt", "InteractPrompt" },
        Parent = { "KeyObtainFake", "Padlock" },
        ModelAncestor = { "DoorFake" }
    }
}

local MinecartPathNodeColor = {
    Disabled = nil,
    Red = Color3.new(1, 0, 0), Yellow = Color3.new(1, 1, 0),
    Purple = Color3.new(1, 0, 1), Green = Color3.new(0, 1, 0),
    Cyan = Color3.new(0, 1, 1), Orange = Color3.new(1, 0.5, 0),
    White = Color3.new(1, 1, 1),
}

local MinecartPathfind = {}

-- LX Doors v3 实体距离表（用于 AutoHide 预测）
local EntityDistances = {
    ["RushMoving"] = 50, ["BackdoorRush"] = 50,
    ["AmbushMoving"] = 100, ["A60"] = 100, ["A120"] = 35
}

-- 锚点标识表
local AnchorIdentify = { ["A"] = 1, ["B"] = 2, ["C"] = 3, ["D"] = 4, ["E"] = 5, ["F"] = 6 }

-- 光源列表
local LightSources = {
    "Flashlight", "Candle", "Straplight", "Lighter",
    "LaserPointer", "Bulklight", "Glowsticks"
}

-- 杂物拾取表
local MiscPickups = {
    ["Glowsticks"] = "Glowstick", ["StarJug"] = "Barrel of Starlight",
    ["Lockpick"] = "Lock-Pick", ["Bandage"] = "Bandage",
    ["StarVial"] = "Vial of Starlight", ["SkeletonKey"] = "Skeleton Key",
    ["Crucifix"] = "Crucifix", ["CrucifixWall"] = "Crucifix",
    ["Flashlight"] = "Flashlight", ["Candle"] = "Candle",
    ["Straplight"] = "Straplight", ["Vitamins"] = "Vitamins",
    ["Lighter"] = "Lighter", ["Shears"] = "Shears",
    ["BatteryPack"] = "Battery Pack", ["BandagePack"] = "Bandage Pack",
    ["LaserPointer"] = "Laser Pointer", ["Bulklight"] = "Bulk Light",
    ["Battery"] = "Battery", ["Candy"] = "Candy"
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 预设颜色 & SETTINGS
-- ══════════════════════════════════════════════════════════════════
local PRESET_COLORS = {
    Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0),
    Color3.fromRGB(0, 0, 255), Color3.fromRGB(255, 255, 0),
    Color3.fromRGB(128, 0, 255), Color3.fromRGB(0, 255, 255),
    Color3.fromRGB(255, 128, 0), Color3.fromRGB(255, 255, 255),
}

local THEME_PRESETS = {
    DoorsPink = Color3.fromRGB(255, 150, 200),
    Cyan = Color3.fromRGB(0, 200, 255),
    Purple = Color3.fromRGB(180, 60, 255),
    Green = Color3.fromRGB(0, 255, 120),
    Red = Color3.fromRGB(255, 70, 90),
    Gold = Color3.fromRGB(255, 200, 50),
    Pink = Color3.fromRGB(255, 105, 180),
}

local SETTINGS = {
    -- ESP 主开关
    ESPEnabled = false,
    ESPName = true,
    ESPDistance = true,
    -- ESP 分类
    DoorsESP = false, CabinetESP = false, ChestESP = false,
    EntityESP = false, OtherESP = false, PlayerESP = false,
    BreakerESP = false, AnchorESP = false, BookESP = false,
    LeverESP = false, KeyESP = false, GoldESP = false,
    -- ESP 颜色
    DoorsESPColor = Color3.fromRGB(255, 255, 255),
    CabinetESPColor = Color3.fromRGB(19, 211, 13),
    ChestESPColor = Color3.fromRGB(131, 96, 168),
    EntityESPColor = Color3.fromRGB(255, 0, 0),
    OtherESPColor = Color3.fromRGB(255, 255, 0),
    PlayerESPColor = Color3.fromRGB(0, 200, 255),
    BreakerESPColor = Color3.fromRGB(255, 165, 0),
    AnchorESPColor = Color3.fromRGB(128, 64, 255),
    BookESPColor = Color3.fromRGB(255, 215, 0),
    LeverESPColor = Color3.fromRGB(255, 165, 0),
    KeyESPColor = Color3.fromRGB(255, 150, 200),
    GoldESPColor = Color3.fromRGB(255, 215, 0),
    ESPRefreshRate = 0.15,
    ESPFillTransparency = 0.5,
    ESPOutlineTransparency = 0.2,

    -- Removals（实体移除）
    NoScreech = false, NoA90 = false, NoHalt = false,
    RemoveSeekChase = false,
    NoScreechDamage = false, NoA90Damage = false, NoHaltDamage = false,
    NoTimothyJumpscare = false, NoGlitchJumpscare = false, NoVoidEffect = false,
    NoSeekEffects = false, NoHasteEffect = false, NoHidingVignette = false,
    NoReviveCutscene = false,

    -- Anti-Entity（反实体触碰）
    AntiGloombat = false, AntiGiggle = false, AntiSnare = false,
    AntiDupe = false, AntiEyes = false, AntiLookman = false,
    AntiChandelier = false, AntiSeekArms = false,
    AlwaysJump = false,

    -- Bypass
    CrouchSpoof = false, SpeedBypass = false, ACManipulate = false,

    -- Auto Interact
    AutoInteract = false, AutoInteractRange = 1,
    AutoInteractUseLockpickDoors = false, AutoInteractUseLockpickOther = false,
    AutoInteractIgnoreLightSources = false, AutoInteractIgnoreCanDie = false,

    -- Auto Hide
    AutoHide = false, AutoHideVisCheck = false,
    AutoHidePredictionTime = 0.5, AutoHidePredictionDistMult = 1,

    -- Auto Padlock / Anchor
    AutoPadlockSolve = false, AutoPadlockDistance = 25,
    AnchorAutoSolve = false,

    -- Minecart
    MinecartInteractSpam = false,

    -- Notifications
    NotifyEnabled = false, NotifySound = false, NotifySoundVolume = 2,
    NotifyAnchorCode = false, NotifyPadlockCode = false,
    NotifyEntities = false,
    NotifyEntityList = { Rush = true, Blitz = true, Ambush = true, Eyes = true,
        Lookman = true, Halt = true, Screech = true, GloombatSwarm = true,
        Dread = true, ["A-60"] = true, ["A-120"] = true },

    -- Candy / Misc Interact
    EatCandies = false, InstantInteract = false,
    EnableInteractions = false, InteractNoclip = false,
    IncreasedDistance = false, DoorRange = 20, NoDark = false, WasteItems = false,

    -- Movement
    SpeedBoost = 50, JumpPower = 100, InfJump = false,
    Noclip = false, Fly = false, FlySpeed = 80, NoclipNext = false,
    NoAcceleration = false,

    -- Visuals
    NoCamShake = false, NoLookBob = false,
    FieldOfView = 0, Ambience = false, AmbienceColor = Color3.fromRGB(255, 255, 255),
    NoFog = false, RushNodes = false,

    -- Audio
    SilentJammin = false, NoHasteSound = false,
    SilentInteracting = false, NoRandomAmbience = false, SilentGloombat = false,

    -- Misc
    AntiAFK = false, AntiRobloxVoid = false,
    RainbowBorder = false, RainbowSpeed = 1,
    AutoWardrobe = false, FakeRevive = false,
    InfCrucifixVelocity = false, MinecartPathESP = false,
    MinecartPathColor = "Yellow",

    -- Keybinds
    UIKeybind = Enum.KeyCode.RightShift,
    NoclipKeybind = Enum.KeyCode.V,
    FlyKeybind = Enum.KeyCode.F,
    ScreechSafeRoomKeybind = Enum.KeyCode.C,
    FakeReviveKeybind = Enum.KeyCode.X,
    AutoInteractKeybind = Enum.KeyCode.R,
    MinecartSpamKeybind = Enum.KeyCode.H,
    ACManipulateKeybind = Enum.KeyCode.T,
    EatCandiesKeybind = Enum.KeyCode.B,
}

-- ══════════════════════════════════════════════════════════════════
-- 5. 全局变量
-- ══════════════════════════════════════════════════════════════════
local espHighlights = {}
local espBillboards = {}
local entityNotified = {}
local entityPredictions = {}
local connections = {}
local isDestroyed = false
local Window = nil
local lastESPUpdate = 0
local lastEntityCheck = 0
local lastAutoWardrobeCheck = 0
local lastSpeedBypass = 0
local fakeReviveDebounce = false
local fakeReviveEnabled = false
local padlockCode = nil
local padlockCodeN = nil
local oldFogEnd = Lighting.FogEnd
local oldAccel = nil
local mainGame = nil
local currentRooms = nil

local ESP_Items = {
    ["Key"] = true, ["Book"] = true, ["Lighter"] = true,
    ["Lockpicks"] = true, ["Vitamins"] = true, ["Crucifix"] = true,
    ["SkeletonKey"] = true, ["Flashlight"] = true, ["Candle"] = true,
    ["Fuse"] = true, ["Shears"] = true, ["Battery"] = true,
    ["Paper"] = true, ["ElectricalKey"] = true, ["Shakelight"] = true,
    ["iPad"] = true,
}

local ESP_Entities = {
    ["Rush"] = true, ["Ambush"] = true, ["Figure"] = true,
    ["Seek"] = true, ["Screech"] = true, ["Eyes"] = true,
    ["Snare"] = true, ["A60"] = true, ["A120"] = true,
    ["BackdoorRush"] = true, ["BackdoorLookman"] = true,
    ["JeffTheKiller"] = true, ["GloombatSwarm"] = true,
    ["Giggle"] = true, ["Grumble"] = true, ["Dread"] = true,
    ["Halt"] = true,
}

-- 按键状态跟踪（用于 Hold 模式）
local keyStates = {}

-- ══════════════════════════════════════════════════════════════════
-- 6. FLOOR 检测
-- ══════════════════════════════════════════════════════════════════
local function getCurrentFloor()
    local success, result = pcall(function()
        local gameData = ReplicatedStorage:FindFirstChild("GameData")
        if gameData then
            local floor = gameData:FindFirstChild("Floor")
            if floor then return floor.Value end
        end
        return "Hotel"
    end)
    return success and result or "Hotel"
end

local function getRooms()
    local ok, res = pcall(function()
        return Workspace:FindFirstChild("CurrentRooms")
    end)
    if ok and res then return res end
    return nil
end

local function getCurrentRoomId()
    local ok, val = pcall(function() return LocalPlayer:GetAttribute("CurrentRoom") end)
    return ok and val or 0
end

-- ══════════════════════════════════════════════════════════════════
-- 7. 工具函数
-- ══════════════════════════════════════════════════════════════════
local function notify(title, content, duration, ntype, imageId)
    if Window then
        local notifyData = {
            Title    = title,
            Content  = content,
            Duration = duration or 3,
            Type     = ntype or "Info"
        }
        if imageId then
            notifyData.Image = "rbxassetid://" .. tostring(imageId)
        end
        pcall(function() Window:Notify(notifyData) end)
    else
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title, Text = content, Duration = duration or 3
            })
        end)
    end
end

local function getChar()
    return LocalPlayer.Character
end

local function getRoot()
    local char = getChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = getChar()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getCollision()
    local char = getChar()
    return char and (char:FindFirstChild("Collision") or char:FindFirstChild("HumanoidRootPart"))
end

local function distanceFromCharacter(inst)
    local root = getRoot()
    if not root or not inst then return math.huge end
    local instPos
    if inst:IsA("BasePart") then
        instPos = inst.Position
    elseif inst:IsA("Model") then
        instPos = inst.PrimaryPart and inst.PrimaryPart.Position or inst:GetPivot().Position
    else
        local ancestor = inst:FindFirstAncestorWhichIsA("BasePart") or inst:FindFirstAncestorWhichIsA("Model")
        if ancestor then
            if ancestor:IsA("BasePart") then instPos = ancestor.Position
            elseif ancestor:IsA("Model") then instPos = ancestor.PrimaryPart and ancestor.PrimaryPart.Position or ancestor:GetPivot().Position
            end
        end
    end
    if not instPos then return math.huge end
    return (instPos - root.Position).Magnitude
end

local function hasItem(itemName)
    local char = getChar()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if char and char:FindFirstChild(itemName) then return char:FindFirstChild(itemName) end
    if backpack and backpack:FindFirstChild(itemName) then return backpack:FindFirstChild(itemName) end
    return nil
end

local function fireProximityPrompt(prompt)
    if not prompt then return end
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt)
        else
            firesignal(prompt.Triggered, LocalPlayer)
        end
    end)
end

local function isCabinet(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("cabinet") or name:find("wardrobe") or name:find("locker")
        or name:find("closet") or name:find("toolshed") or name:find("bed")
        or name:find("dumpster") or name:find("vent")
end

local function isChest(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("chest") or name:find("drawer") or name:find("box")
        or name:find("toolbox") or name:find("table") or name:find("desk")
end

local function isDoor(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name == "door" or name:find("door")
end

local function isLever(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("lever") or name:find("switch") or name:find("valve")
        or name:find("timerlever") or name:find("leverforgate")
end

local function isGold(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("gold") or name:find("goldpile")
end

local function isMinecartTrack(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("minecart") or name:find("track") or name:find("minecarttrack")
end

-- 锚点解谜函数
local function solveAnchor(code, offset)
    local result = ""
    local numTable = {}
    table.insert(numTable, 1, string.sub(tostring(code), 1, 1))
    table.insert(numTable, 2, string.sub(tostring(code), 2, 2))
    table.insert(numTable, 3, string.sub(tostring(code), 3, 3))
    for i, num in ipairs(numTable) do
        num = tonumber(num) or 0
        num = num + offset
        if num > 9 then num = num - 10
        elseif num < 0 then num = num + 10 end
        numTable[i] = num
    end
    for _, num in ipairs(numTable) do
        result = result .. tostring(num)
    end
    return result
end

-- ══════════════════════════════════════════════════════════════════
-- 8. ESP 核心（Highlight + BillboardGui）
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    for _, hl in pairs(espHighlights) do
        pcall(function() hl:Destroy() end)
    end
    for _, bb in pairs(espBillboards) do
        pcall(function() bb:Destroy() end)
    end
    espHighlights = {}
    espBillboards = {}
end

local function createHighlight(part, color, name, textLabel)
    if not part or not part:IsA("Instance") then return nil end
    local adornee = part:IsA("Model") and part or (part.Parent and part.Parent:IsA("Model") and part.Parent or part)
    local key = adornee
    local existing = espHighlights[key]
    if existing then
        existing.FillColor = color
        existing.OutlineColor = color
        existing.FillTransparency = SETTINGS.ESPFillTransparency
        existing.OutlineTransparency = SETTINGS.ESPOutlineTransparency
        existing.Enabled = true
        return existing
    end
    local hl = Instance.new("Highlight")
    hl.Name = "DoorsESP_" .. (name or "Item")
    hl.Adornee = adornee
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = SETTINGS.ESPFillTransparency
    hl.OutlineTransparency = SETTINGS.ESPOutlineTransparency
    hl.Enabled = true
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = CoreGui
    espHighlights[key] = hl

    if textLabel and SETTINGS.ESPName then
        local bb = Instance.new("BillboardGui")
        bb.Name = "DoorsESP_BB_" .. (name or "Item")
        bb.Adornee = adornee
        bb.AlwaysOnTop = true
        bb.Size = UDim2.new(0, 200, 0, 50)
        bb.StudsOffset = Vector3.new(0, 2, 0)
        bb.Parent = CoreGui

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 1
        tl.Font = Enum.Font.SourceSans
        tl.TextSize = 18
        tl.TextColor3 = color
        tl.TextStrokeTransparency = 0.4
        tl.Text = textLabel
        tl.Parent = bb

        espBillboards[key] = bb
    end
    return hl
end

local function removeESPFor(inst)
    if not inst then return end
    local adornee = inst:IsA("Model") and inst or (inst.Parent and inst.Parent:IsA("Model") and inst.Parent or inst)
    if espHighlights[adornee] then
        pcall(function() espHighlights[adornee]:Destroy() end)
        espHighlights[adornee] = nil
    end
    if espBillboards[adornee] then
        pcall(function() espBillboards[adornee]:Destroy() end)
        espBillboards[adornee] = nil
    end
end

local function updateESP()
    if isDestroyed then return end
    local now = tick()
    if now - lastESPUpdate < SETTINGS.ESPRefreshRate then return end
    lastESPUpdate = now

    local success, err = pcall(function()
        local enabledAny = SETTINGS.DoorsESP or SETTINGS.CabinetESP or SETTINGS.ChestESP
            or SETTINGS.EntityESP or SETTINGS.OtherESP or SETTINGS.PlayerESP
            or SETTINGS.MinecartPathESP or SETTINGS.BookESP or SETTINGS.BreakerESP
            or SETTINGS.AnchorESP or SETTINGS.LeverESP or SETTINGS.KeyESP or SETTINGS.GoldESP
        if not enabledAny then
            for part, hl in pairs(espHighlights) do
                if hl then hl.Enabled = false end
            end
            for part, bb in pairs(espBillboards) do
                if bb then bb.Enabled = false end
            end
            return
        end

        for _, v in pairs(Workspace:GetDescendants()) do
            if isDestroyed then return end
            local name = v.Name
            local lname = name:lower()

            -- 物品 / Key / Book / Breaker
            if SETTINGS.DoorsESP and ESP_Items[name] then
                if v:IsA("BasePart") or v:IsA("Model") then
                    createHighlight(v, SETTINGS.DoorsESPColor, name, name)
                end
            end

            if SETTINGS.KeyESP and (name == "KeyObtain" or name == "ElectricalKeyObtain") then
                if v:IsA("Model") then
                    createHighlight(v, SETTINGS.KeyESPColor, "Door Key", "Door Key")
                end
            end

            if SETTINGS.BookESP and name == "LiveHintBook" then
                if v:IsA("Model") then
                    createHighlight(v, SETTINGS.BookESPColor, "Book", "Library Book")
                end
            end

            if SETTINGS.BreakerESP and (name == "LiveBreakerPolePickup" or name == "FuseObtain") then
                if v:IsA("Model") then
                    createHighlight(v, SETTINGS.BreakerESPColor, "Breaker", name == "FuseObtain" and "Generator Fuse" or "Breaker Pole")
                end
            end

            if SETTINGS.AnchorESP and name == "MinesAnchor" then
                if v:IsA("Model") then
                    createHighlight(v, SETTINGS.AnchorESPColor, "Anchor", "Anchor")
                end
            end

            if SETTINGS.CabinetESP and isCabinet(v) then
                if v:IsA("Model") or v:IsA("BasePart") then
                    createHighlight(v, SETTINGS.CabinetESPColor, "Cabinet", "Cabinet")
                end
            end

            if SETTINGS.ChestESP and isChest(v) then
                if v:IsA("Model") or v:IsA("BasePart") then
                    createHighlight(v, SETTINGS.ChestESPColor, "Chest", "Chest")
                end
            end

            if SETTINGS.EntityESP then
                local function checkEntityName(ename)
                    for k in pairs(ESP_Entities) do
                        if ename:lower():find(k:lower()) then return true end
                    end
                    return false
                end
                if checkEntityName(name) then
                    if v:IsA("Model") or v:IsA("BasePart") then
                        local hlColor = SETTINGS.EntityESPColor
                        local shortName = EntityTable.ShortNames[name]
                        local displayName = shortName or name
                        createHighlight(v, hlColor, name, displayName)
                    end
                end
            end

            if SETTINGS.OtherESP then
                if isDoor(v) and (v:IsA("Model") or v:IsA("BasePart")) then
                    createHighlight(v, SETTINGS.OtherESPColor, "Door", "Door")
                end
                if (isLever(v) or name == "LeverForGate" or name == "TimerLever") and (v:IsA("Model") or v:IsA("BasePart")) then
                    createHighlight(v, SETTINGS.LeverESPColor, "Lever", "Lever")
                end
                if isGold(v) and (v:IsA("Model") or v:IsA("BasePart")) then
                    createHighlight(v, SETTINGS.GoldESPColor, "Gold", "Gold Pile")
                end
            end

            if SETTINGS.LeverESP and (name == "LeverForGate" or name == "TimerLever" or name == "MinesGenerator") then
                if v:IsA("Model") then
                    createHighlight(v, SETTINGS.LeverESPColor, "Lever", name)
                end
            end

            if SETTINGS.MinecartPathESP and isMinecartTrack(v) then
                if v:IsA("Model") or v:IsA("BasePart") then
                    local pathColor = MinecartPathNodeColor[SETTINGS.MinecartPathColor] or MinecartPathNodeColor.Yellow
                    createHighlight(v, pathColor, "MinecartPath", "Minecart")
                end
            end
        end

        -- Player ESP
        if SETTINGS.PlayerESP then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    createHighlight(plr.Character, SETTINGS.PlayerESPColor, "Player", plr.Name)
                end
            end
        end

        -- 清理无效引用
        for part, hl in pairs(espHighlights) do
            if not part or not part.Parent then
                pcall(function() hl:Destroy() end)
                espHighlights[part] = nil
            end
        end
        for part, bb in pairs(espBillboards) do
            if not part or not part.Parent then
                pcall(function() bb:Destroy() end)
                espBillboards[part] = nil
            end
        end
    end)
    if not success then warn("[Doors] ESP Update error:", err) end
end

-- ══════════════════════════════════════════════════════════════════
-- 9. Entity 通知 & 检测
-- ══════════════════════════════════════════════════════════════════
local function checkEntityNotifications()
    if isDestroyed or not SETTINGS.NotifyEnabled or not SETTINGS.NotifyEntities then return end
    local now = tick()
    if now - lastEntityCheck < 0.5 then return end
    lastEntityCheck = now

    pcall(function()
        for _, v in pairs(Workspace:GetDescendants()) do
            local name = v.Name
            local isEntity = false
            for _, ename in ipairs(EntityTable.Names) do
                if name:lower():find(ename:lower()) then isEntity = true; break end
            end
            for _, sname in ipairs(EntityTable.SideNames) do
                if name:lower():find(sname:lower()) then isEntity = true; break end
            end
            if isEntity and not entityNotified[name] then
                entityNotified[name] = true
                local notifyData = EntityTable.NotifyReason[name]
                local shortName = EntityTable.ShortNames[name] or name
                local msg = EntityTable.NotifyMessage[name] or (shortName .. " 已出现!")
                local imageId = notifyData and notifyData.Image

                -- 检查是否在通知白名单
                local shouldNotify = false
                for entityKey, enabled in pairs(SETTINGS.NotifyEntityList) do
                    if enabled and (name:lower():find(entityKey:lower()) or shortName:lower():find(entityKey:lower())) then
                        shouldNotify = true; break
                    end
                end
                if shouldNotify then
                    notify("⚠️ 实体警告", msg, 5, "Warning", imageId)
                    if SETTINGS.NotifySound then
                        pcall(function()
                            local snd = Instance.new("Sound")
                            snd.SoundId = "rbxassetid://3318713980"
                            snd.Volume = SETTINGS.NotifySoundVolume
                            snd.Parent = CoreGui
                            snd:Play()
                            game:GetService("Debris"):AddItem(snd, 3)
                        end)
                    end
                end
            end
        end

        for name, _ in pairs(entityNotified) do
            local found = false
            for _, v in pairs(Workspace:GetDescendants()) do
                if v.Name == name then found = true; break end
            end
            if not found then entityNotified[name] = nil end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 10. Entity 拦截（hookmetamethod FireServer 拦截）
-- ══════════════════════════════════════════════════════════════════
local function setupEntityInterceptors()
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(v, ...)
            local method = getnamecallmethod()
            local args = {...}
            if method == "FireServer" and not isDestroyed then
                if v.Name == "Crouch" and SETTINGS.CrouchSpoof then
                    args[1] = true
                    return oldNamecall(v, unpack(args))
                elseif v.Name == "Underwater" then
                    args[1] = false
                    return oldNamecall(v, unpack(args))
                elseif v.Name == "Screech" and SETTINGS.NoScreechDamage then
                    local tool = getChar() and getChar():FindFirstChildWhichIsA("Tool")
                    args[1] = not (tool and tool.Name == "Crucifix") ~= nil
                    return oldNamecall(v, unpack(args))
                elseif v.Name == "A90" and SETTINGS.NoA90Damage then
                    args[1] = "didnt"
                    return oldNamecall(v, unpack(args))
                elseif v.Name == "ShadeResult" and SETTINGS.NoHaltDamage then
                    return
                end
            elseif method == "Destroy" then
                if v.Name == "PathfindNodes" then return end
            end
            return oldNamecall(v, ...)
        end))
    end)

    -- Screech / A90 模块 hook（使用 hookfunction）
    pcall(function()
        local ok, mod = pcall(function()
            return require(LocalPlayer.PlayerGui.MainUI.Initiator.Main_Game.RemoteListener.Modules.Screech)
        end)
        if ok and mod then
            local oldScreech
            oldScreech = hookfunction(mod, newcclosure(function(...)
                if isDestroyed or not SETTINGS.NoScreech then return oldScreech(...) end
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
                    if rf and rf:FindFirstChild("Screech") then
                        rf.Screech:FireServer(true)
                    end
                end)
                return
            end))
        end
    end)

    pcall(function()
        local ok, mod = pcall(function()
            return require(LocalPlayer.PlayerGui.MainUI.Initiator.Main_Game.RemoteListener.Modules.A90)
        end)
        if ok and mod then
            local oldA90
            oldA90 = hookfunction(mod, newcclosure(function(...)
                if isDestroyed or not SETTINGS.NoA90 then return oldA90(...) end
                pcall(function()
                    local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
                    if rf and rf:FindFirstChild("A90") then
                        rf.A90:FireServer("didnt")
                    end
                end)
                return
            end))
        end
    end)

    pcall(function()
        local ok, mod = pcall(function()
            return require(LocalPlayer.PlayerGui.MainUI.Initiator.Main_Game.RemoteListener.Modules.SpiderJumpscare)
        end)
        if ok and mod then
            local oldTim
            oldTim = hookfunction(mod, newcclosure(function(...)
                if isDestroyed or not SETTINGS.NoTimothyJumpscare then return oldTim(...) end
                return
            end))
        end
    end)

    pcall(function()
        local ok, mod = pcall(function()
            return require(ReplicatedStorage.ModulesClient.ReviveCutscene)
        end)
        if ok and mod then
            local oldRev
            oldRev = hookfunction(mod, newcclosure(function(...)
                if isDestroyed or not SETTINGS.NoReviveCutscene then return oldRev(...) end
                return
            end))
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 11. Anti-Entity（CanTouch 操控）
-- ══════════════════════════════════════════════════════════════════
local function applyAntiEntities()
    pcall(function()
        local rooms = getRooms()
        if not rooms then return end
        for _, v in pairs(rooms:GetDescendants()) do
            if v:IsA("Model") or v:IsA("BasePart") then
                if v.Name == "GiggleCeiling" and v:FindFirstChild("Hitbox") then
                    v.Hitbox.CanTouch = not SETTINGS.AntiGiggle
                elseif v.Name == "Snare" and v:FindFirstChild("Hitbox") then
                    v.Hitbox.CanTouch = not SETTINGS.AntiSnare
                elseif v.Name == "ChandelierObstruction" and v:FindFirstChild("HurtPart") then
                    v.HurtPart.CanTouch = not SETTINGS.AntiChandelier
                elseif v.Name == "Seek_Arm" and v:FindFirstChild("AnimatorPart") then
                    v.AnimatorPart.CanTouch = not SETTINGS.AntiSeekArms
                elseif v.Name == "DoorFake" and v:FindFirstChild("Hidden") then
                    v.Hidden.CanTouch = not SETTINGS.AntiDupe
                    if v:FindFirstChild("LockPart") and v.LockPart:FindFirstChild("UnlockPrompt") then
                        v.LockPart.UnlockPrompt.Enabled = not SETTINGS.AntiDupe
                    end
                elseif v.Name == "GloomEgg" and v:FindFirstChild("Egg") then
                    v.Egg.CanTouch = not SETTINGS.AntiGloombat
                end
            end
        end
    end)
end

local function setupAntiEntityWatcher()
    local conn
    conn = Workspace.DescendantAdded:Connect(function(desc)
        if isDestroyed then return end
        pcall(function()
            if desc.Name == "GiggleCeiling" then
                local hb = desc:WaitForChild("Hitbox", 5)
                if hb then hb.CanTouch = not SETTINGS.AntiGiggle end
            elseif desc.Name == "Snare" then
                local hb = desc:WaitForChild("Hitbox", 5)
                if hb then hb.CanTouch = not SETTINGS.AntiSnare end
            elseif desc.Name == "ChandelierObstruction" then
                local hp = desc:WaitForChild("HurtPart", 5)
                if hp then hp.CanTouch = not SETTINGS.AntiChandelier end
            elseif desc.Name == "Seek_Arm" then
                local ap = desc:WaitForChild("AnimatorPart", 5)
                if ap then ap.CanTouch = not SETTINGS.AntiSeekArms end
            elseif desc.Name == "DoorFake" then
                local hd = desc:WaitForChild("Hidden", 5)
                if hd then hd.CanTouch = not SETTINGS.AntiDupe end
            elseif desc.Name == "GloomEgg" then
                local egg = desc:WaitForChild("Egg", 5)
                if egg then egg.CanTouch = not SETTINGS.AntiGloombat end
            end
        end)
    end)
    table.insert(connections, conn)
end

-- Anti-Eyes / Anti-Lookman（强制低头）
local function setupAntiEyesLookman()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local char = getChar()
        if not char or char:GetAttribute("Hiding") then return end

        if SETTINGS.AntiEyes then
            for _, v in pairs(Workspace:GetChildren()) do
                if v.Name == "Eyes" and v:FindFirstChild("Core") and v.Core:FindFirstChild("Ambience") and v.Core.Ambience.Playing then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
                        if rf and rf:FindFirstChild("MotorReplication") then
                            rf.MotorReplication:FireServer(-650)
                        end
                    end)
                    break
                end
            end
        end

        if SETTINGS.AntiLookman then
            for _, v in pairs(Workspace:GetChildren()) do
                if v.Name == "BackdoorLookman" and v:FindFirstChild("Core") and v.Core:FindFirstChild("Ambience") and v.Core.Ambience.Playing then
                    pcall(function()
                        local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
                        if rf and rf:FindFirstChild("MotorReplication") then
                            rf.MotorReplication:FireServer(-650)
                        end
                    end)
                    break
                end
            end
        end
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 12. AutoWardrobe（自动躲藏）
-- ══════════════════════════════════════════════════════════════════
local function setupAutoWardrobe()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.AutoWardrobe then return end
        local now = tick()
        if now - lastAutoWardrobeCheck < 0.3 then return end
        lastAutoWardrobeCheck = now

        local root = getRoot()
        if not root then return end
        local currentFloor = getCurrentFloor()
        local hidingName = HidingPlaceName[currentFloor] or "Closet"

        pcall(function()
            for _, entityName in ipairs(EntityTable.AutoWardrobe.Entities) do
                local foundEntity = nil
                for _, v in pairs(Workspace:GetDescendants()) do
                    if v.Name:lower():find(entityName:lower()) then
                        if v:IsA("Model") or v:IsA("BasePart") then
                            foundEntity = v
                            break
                        end
                    end
                end

                if foundEntity then
                    local distance = EntityTable.AutoWardrobe.Distance[entityName] or 150
                    local dist = distanceFromCharacter(foundEntity)
                    if dist <= distance then
                        local nearestHiding = nil
                        local nearestDist = math.huge
                        for _, v in pairs(Workspace:GetDescendants()) do
                            if v.Name:lower():find(hidingName:lower()) then
                                if v:IsA("Model") or v:IsA("BasePart") then
                                    local d = distanceFromCharacter(v)
                                    if d < nearestDist then
                                        nearestDist = d
                                        nearestHiding = v
                                    end
                                end
                            end
                        end
                        if nearestHiding then
                            local prompt = nearestHiding:FindFirstChildWhichIsA("ProximityPrompt", true)
                            if prompt then
                                fireProximityPrompt(prompt)
                            end
                        end
                    end
                end
            end
        end)
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 13. AutoHide（基于实体预测自动躲藏）
-- ══════════════════════════════════════════════════════════════════
local function getHidingSpot()
    local rooms = getRooms()
    local currentId = getCurrentRoomId()
    if not rooms or not currentId then return nil end
    local room = rooms:FindFirstChild(tostring(currentId)) or rooms:FindFirstChild(currentId)
    if not room then return nil end

    local closest, prompt
    local root = getRoot()
    if not root then return nil end

    pcall(function()
        local assets = room:FindFirstChild("Assets")
        if assets then
            for _, v in pairs(assets:GetChildren()) do
                if v:IsA("Model") and (v.Name == "Locker_Large" or v.Name == "Wardrobe"
                    or v.Name == "Toolshed" or v.Name == "Bed" or v.Name == "Rooms_Locker"
                    or v.Name == "Rooms_Locker_Fridge" or v.Name == "Backdoor_Wardrobe") then
                    if v:FindFirstChild("HidePrompt") and v:FindFirstChild("HiddenPlayer") then
                        if not v.HiddenPlayer.Value and not v:FindFirstChild("HideEntityOnSpot", true) then
                            local pp = v.PrimaryPart and (v.PrimaryPart.Position - root.Position).Magnitude or math.huge
                            if not closest or pp < (closest.PrimaryPart.Position - root.Position).Magnitude then
                                closest = v
                                prompt = v.HidePrompt
                            end
                        end
                    end
                end
            end
        end
    end)
    return prompt
end

local function setupAutoHide()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.AutoHide then return end
        pcall(function()
            local rooms = getRooms()
            if not rooms then return end
            for _, v in pairs(Workspace:GetChildren()) do
                if EntityDistances[v.Name] and v:IsA("Model") then
                    local part = v.PrimaryPart
                    if not part then
                        local main = v:FindFirstChild("Main") or v:FindFirstChild("RushNew")
                        if main and main:IsA("BasePart") then part = main end
                    end
                    if not part then return end

                    -- 计算速度向量做预测
                    local lastPos = entityPredictions[v] or part.Position
                    local prediction = (part.Position - lastPos)
                    entityPredictions[v] = part.Position

                    if prediction.Magnitude > 0.1 then
                        local char = getChar()
                        if char and not char:GetAttribute("Hiding") then
                            local col = getCollision()
                            if col then
                                local predictionPos = part.Position + prediction * 3 * SETTINGS.AutoHidePredictionTime
                                local horizDist = Vector3.new(prediction.X, 0, prediction.Z).Magnitude
                                if horizDist > 1 then
                                    local dist = (predictionPos - col.Position).Magnitude
                                    local maxDist = (EntityDistances[v.Name] or 50) * SETTINGS.AutoHidePredictionDistMult
                                    if dist <= maxDist then
                                        local prompt = getHidingSpot()
                                        if prompt then
                                            fireProximityPrompt(prompt)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 14. AutoInteract（自动交互）
-- ══════════════════════════════════════════════════════════════════
local function findLoot(origin)
    if not origin then return end
    local col = getCollision()
    if not col then return end
    local range = SETTINGS.AutoInteractRange

    pcall(function()
        for _, loot in pairs(origin:GetChildren()) do
            if loot.Name == "GoldPile" and loot:FindFirstChild("Hitbox") and loot:FindFirstChild("LootPrompt") then
                if (loot.Hitbox.Position - col.Position).Magnitude < loot.LootPrompt.MaxActivationDistance * range then
                    fireProximityPrompt(loot.LootPrompt)
                end
            elseif loot.Name == "KeyObtain" and loot:FindFirstChild("Hitbox") and loot:FindFirstChild("ModulePrompt") then
                if not (hasItem("Key") or hasItem("KeyBackdoor")) then
                    if (loot.Hitbox.Position - col.Position).Magnitude < loot.ModulePrompt.MaxActivationDistance * range then
                        fireProximityPrompt(loot.ModulePrompt)
                    end
                end
            elseif loot.Name == "Battery" and loot:FindFirstChild("Main") and loot:FindFirstChild("ModulePrompt") then
                if (loot.Main.Position - col.Position).Magnitude < loot.ModulePrompt.MaxActivationDistance * range then
                    fireProximityPrompt(loot.ModulePrompt)
                end
            elseif MiscPickups[loot.Name] and loot:FindFirstChild("Main") and loot:FindFirstChild("ModulePrompt") then
                if not (table.find(LightSources, loot.Name) and SETTINGS.AutoInteractIgnoreLightSources) then
                    if (loot.Main.Position - col.Position).Magnitude < loot.ModulePrompt.MaxActivationDistance * range then
                        fireProximityPrompt(loot.ModulePrompt)
                    end
                end
            elseif loot.Name == "Candy" and loot:FindFirstChild("Main") and loot:FindFirstChild("ModulePrompt") then
                if SETTINGS.AutoInteractIgnoreCanDie and loot:FindFirstChild("Meshes/DOORS_EvilCandy_Cube", true) then
                else
                    if (loot.Main.Position - col.Position).Magnitude < loot.ModulePrompt.MaxActivationDistance * range then
                        fireProximityPrompt(loot.ModulePrompt)
                    end
                end
            end
        end
    end)
end

local function setupAutoInteract()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.AutoInteract then return end
        if not keyStates[SETTINGS.AutoInteractKeybind] then return end

        pcall(function()
            local rooms = getRooms()
            if not rooms then return end
            local currentId = getCurrentRoomId()
            local room = rooms:FindFirstChild(tostring(currentId)) or rooms:FindFirstChild(currentId)
            if not room then return end
            local col = getCollision()
            if not col then return end
            local range = SETTINGS.AutoInteractRange

            for _, v in pairs(room:GetChildren()) do
                if v:IsA("Model") then
                    if v.Name == "Door" and v:FindFirstChild("Lock") and v.Lock:FindFirstChild("UnlockPrompt") then
                        local item = (SETTINGS.AutoInteractUseLockpickDoors and hasItem("Lockpick")) or hasItem("Key") or (getChar() and getChar():FindFirstChild("KeyBackdoor"))
                        if item then
                            if (v.Lock.Position - col.Position).Magnitude < v.Lock.UnlockPrompt.MaxActivationDistance * range then
                                fireProximityPrompt(v.Lock.UnlockPrompt)
                            end
                        end
                    elseif v.Name == "AlarmClock" and v:FindFirstChild("Main") and v:FindFirstChild("ModulePrompt") then
                        if (v.Main.Position - col.Position).Magnitude < v.ModulePrompt.MaxActivationDistance * range then
                            fireProximityPrompt(v.ModulePrompt)
                        end
                    elseif v.Name == "PickupItem" and v:FindFirstChild("Handle") and v:FindFirstChild("ModulePrompt") then
                        if not hasItem("LibraryHintPaper") then
                            if (v.Handle.Position - col.Position).Magnitude < v.ModulePrompt.MaxActivationDistance * range then
                                fireProximityPrompt(v.ModulePrompt)
                            end
                        end
                    elseif v.Name == "LiveBreakerPolePickup" and v:FindFirstChild("Base") then
                        local prompt
                        for _, p in pairs(v:GetChildren()) do
                            if p:IsA("ProximityPrompt") and p.RequiresLineOfSight then prompt = p; break end
                        end
                        if prompt and (v.Base.Position - col.Position).Magnitude < prompt.MaxActivationDistance * range then
                            fireProximityPrompt(prompt)
                        end
                    elseif v.Name == "Wax_Door" and v:FindFirstChild("SkullLock") and getChar():FindFirstChild("SkeletonKey") then
                        if v.SkullLock.SkullPrompt.Enabled and (v.SkullLock.Position - col.Position).Magnitude < v.SkullLock.SkullPrompt.MaxActivationDistance * range then
                            fireProximityPrompt(v.SkullLock.SkullPrompt)
                        end
                    end
                end
            end

            local assets = room:FindFirstChild("Assets")
            if assets then
                findLoot(assets)
                for _, root2 in pairs(assets:GetChildren()) do
                    if root2.Name == "Locker_Small" and root2:FindFirstChild("Door") and root2.Door:FindFirstChild("ActivateEventPrompt") then
                        if not root2.Door.ActivateEventPrompt:GetAttribute("Interactions") then
                            if (root2.Door.Position - col.Position).Magnitude < root2.Door.ActivateEventPrompt.MaxActivationDistance * range then
                                fireProximityPrompt(root2.Door.ActivateEventPrompt)
                            end
                        end
                    elseif (root2.Name == "Toolbox" or root2.Name == "ChestBox" or root2.Name == "Toolshed_Small") and root2:FindFirstChild("ActivateEventPrompt") then
                        if not root2.ActivateEventPrompt:GetAttribute("Interactions") then
                            if (root2.Main.Position - col.Position).Magnitude < root2.ActivateEventPrompt.MaxActivationDistance * range then
                                fireProximityPrompt(root2.ActivateEventPrompt)
                            end
                        end
                    elseif root2.Name == "LeverForGate" and root2:FindFirstChild("ActivateEventPrompt") then
                        if not root2.ActivateEventPrompt:GetAttribute("Interactions") then
                            if (root2.Main.Position - col.Position).Magnitude < root2.ActivateEventPrompt.MaxActivationDistance * range then
                                fireProximityPrompt(root2.ActivateEventPrompt)
                            end
                        end
                    elseif root2.Name == "VentGrate" and root2:FindFirstChild("AwesomePrompt") then
                        if root2.AwesomePrompt.Enabled and (root2.SquareGrate.Position - col.Position).Magnitude < root2.AwesomePrompt.MaxActivationDistance * range then
                            fireProximityPrompt(root2.AwesomePrompt)
                        end
                    elseif root2.Name == "Modular_Bookshelf" and root2:FindFirstChild("LiveHintBook") then
                        if (root2.LiveHintBook.Base.Position - col.Position).Magnitude < root2.LiveHintBook.ActivateEventPrompt.MaxActivationDistance * range then
                            fireProximityPrompt(root2.LiveHintBook.ActivateEventPrompt)
                        end
                    elseif root2.Name == "MinesGenerator" then
                        local fuse = hasItem("GeneratorFuse")
                        if fuse and root2:FindFirstChild("Fuses") then
                            for _, fi in pairs(root2.Fuses:GetChildren()) do
                                if fi:FindFirstChild("FusesPrompt") and fi:FindFirstChild("Fuse") then
                                    if (fi.Fuse.Position - col.Position).Magnitude < fi.FusesPrompt.MaxActivationDistance * range then
                                        fireProximityPrompt(fi.FusesPrompt)
                                    end
                                    break
                                end
                            end
                        end
                    elseif root2.Name == "MinesGateButton" and root2:FindFirstChild("Button") and root2:FindFirstChild("Light") then
                        if root2.Light.Transparency < 1 then
                            if (root2.Button.Position - col.Position).Magnitude < root2.Button.ActivateEventPrompt.MaxActivationDistance * range then
                                fireProximityPrompt(root2.Button.ActivateEventPrompt)
                            end
                        end
                    end
                end
            end

            -- 出口门
            local doorExit = room:FindFirstChild("Backdoors_Exit") or room:FindFirstChild("RoomsDoor_Exit")
            if doorExit and doorExit:FindFirstChild("Door") and doorExit.Door:FindFirstChild("EnterPrompt") then
                if (doorExit.Door.Position - col.Position).Magnitude < doorExit.Door.EnterPrompt.MaxActivationDistance * range then
                    fireProximityPrompt(doorExit.Door.EnterPrompt)
                end
            end

            -- Drops
            if Workspace:FindFirstChild("Drops") then
                findLoot(Workspace.Drops)
            end
        end)
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 15. AutoPadlockSolve（自动图书馆密码锁）
-- ══════════════════════════════════════════════════════════════════
local function setupPadlockCodeFinder()
    task.spawn(function()
        while not isDestroyed and not padlockCodeN do
            task.wait(0.5)
            pcall(function()
                local paper = hasItem("LibraryHintPaper")
                if not paper then
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer then
                            paper = (plr.Character and plr.Character:FindFirstChild("LibraryHintPaper"))
                                or (plr:FindFirstChild("Backpack") and plr.Backpack:FindFirstChild("LibraryHintPaper"))
                            if paper then break end
                        end
                    end
                end

                local rooms = getRooms()
                if paper and paper:FindFirstChild("UI") and rooms then
                    local room50 = rooms:FindFirstChild("50")
                    if room50 and room50:FindFirstChild("Door") and room50.Door:FindFirstChild("Padlock") then
                        local code = ""
                        for _, x in pairs(paper.UI:GetChildren()) do
                            if tonumber(x.Name) then
                                for _, y in pairs(LocalPlayer.PlayerGui.PermUI.Hints:GetChildren()) do
                                    if y.Name == "Icon" and y.ImageRectOffset == x.ImageRectOffset then
                                        code = code .. y.TextLabel.Text
                                    end
                                end
                            end
                            if #code == 5 then
                                if SETTINGS.NotifyPadlockCode then
                                    notify("🔐 密码锁代码", "密码: '" .. code .. "'", 10, "Success")
                                    print("[Doors] 密码锁代码: " .. code)
                                end
                                padlockCodeN = code
                                padlockCode = code
                            end
                            if padlockCode then break end
                        end
                    end
                end
            end)
        end
    end)
end

local function setupAutoPadlockSolver()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.AutoPadlockSolve or not padlockCode then return end
        pcall(function()
            local currentId = getCurrentRoomId()
            if currentId > 51 then return end
            local rooms = getRooms()
            if not rooms then return end
            local room50 = rooms:FindFirstChild("50")
            if not room50 or not room50:FindFirstChild("Door") then return end
            local padlock = room50.Door:FindFirstChild("Padlock")
            if not padlock or not padlock:FindFirstChild("Main") then return end
            local col = getCollision()
            if not col then return end
            if (col.Position - padlock.Main.Position).Magnitude < SETTINGS.AutoPadlockDistance then
                local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
                if rf and rf:FindFirstChild("PL") then
                    rf.PL:FireServer(padlockCode)
                end
            end
        end)
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 16. MinecartInteractSpam（矿井车连点）
-- ══════════════════════════════════════════════════════════════════
local function setupMinecartSpam()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.MinecartInteractSpam then return end
        if not keyStates[SETTINGS.MinecartSpamKeybind] then return end
        pcall(function()
            local rooms = getRooms()
            if not rooms then return end
            local currentId = getCurrentRoomId()
            local room = rooms:FindFirstChild(tostring(currentId)) or rooms:FindFirstChild(currentId)
            if not room then return end
            local col = getCollision()
            if not col then return end

            local assets = room:FindFirstChild("Assets")
            if assets then
                if assets:FindFirstChild("MinecartSet") then
                    for _, mc in pairs(assets.MinecartSet:GetChildren()) do
                        if mc:FindFirstChild("Cart") and mc:FindFirstChild("Main") then
                            if (col.Position - mc.Main.Position).Magnitude < mc.Cart.PushPrompt.MaxActivationDistance * 2 then
                                fireProximityPrompt(mc.Cart.PushPrompt)
                            end
                        end
                    end
                end
                if assets:FindFirstChild("MinecartTracks") then
                    for _, track in pairs(assets.MinecartTracks:GetChildren()) do
                        if track:FindFirstChild("MinecartSet") then
                            for _, mc in pairs(track.MinecartSet:GetChildren()) do
                                if mc.Name == "MinecartMoving" and mc:FindFirstChild("Main") and mc:FindFirstChild("Cart") then
                                    if (col.Position - mc.Main.Position).Magnitude < mc.Cart.PushPrompt.MaxActivationDistance * 2 then
                                        fireProximityPrompt(mc.Cart.PushPrompt)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 17. AnchorAutoSolve（锚点自动解谜）
-- ══════════════════════════════════════════════════════════════════
local function setupAnchorAutoSolve()
    task.spawn(function()
        while not isDestroyed do
            task.wait(1)
            pcall(function()
                if not SETTINGS.AnchorAutoSolve then return end
                local rooms = getRooms()
                if not rooms then return end
                for _, room in pairs(rooms:GetChildren()) do
                    local nestHandler = room:FindFirstChild("_NestHandler", true)
                    if nestHandler and nestHandler:FindFirstChild("Console") then
                        for _, anchor in pairs(nestHandler:GetChildren()) do
                            if anchor.Name == "MinesAnchor" and not anchor:GetAttribute("Activated") then
                                if anchor:FindFirstChild("AnchorBase") and anchor:FindFirstChild("AnchorRemote") then
                                    local col = getCollision()
                                    if col and (col.Position - anchor.AnchorBase.Position).Magnitude < 12 then
                                        local code = LocalPlayer.PlayerGui.MainUI.MainFrame:FindFirstChild("AnchorHintFrame")
                                        if code and code:FindFirstChild("Code") then
                                            anchor.AnchorRemote:InvokeServer(tostring(code.Code.Text))
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 18. FakeRevive / InfCrucifixVelocity
-- ══════════════════════════════════════════════════════════════════
local function setupFakeRevive()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.FakeRevive then return end
        local hum = getHumanoid()
        if not hum then return end
        if fakeReviveEnabled and fakeReviveDebounce then
            fakeReviveDebounce = false
            pcall(function()
                hum.Health = 100
                hum.MaxHealth = 100
                hum:ChangeState(Enum.HumanoidStateType.Running)
                LocalPlayer:SetAttribute("Alive", true)
            end)
        end
        fakeReviveEnabled = hum.Health <= 0
    end)
    table.insert(connections, conn)
end

local function setupInfCrucifixVelocity()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.InfCrucifixVelocity then return end
        local root = getRoot()
        if not root then return end
        pcall(function()
            for _, entityName in ipairs({"RushMoving", "AmbushMoving", "A60", "A120"}) do
                local ec = EntityTable.InfCrucifixVelocity[entityName]
                if not ec then
                    local altName = entityName:gsub("Moving", "New")
                    ec = EntityTable.InfCrucifixVelocity[altName]
                end
                if ec then
                    local foundEntity = nil
                    for _, v in pairs(Workspace:GetDescendants()) do
                        if v.Name:lower():find(entityName:lower()) then
                            if v:IsA("Model") or v:IsA("BasePart") then
                                foundEntity = v
                                break
                            end
                        end
                    end
                    if foundEntity then
                        local dist = distanceFromCharacter(foundEntity)
                        if dist <= (ec.minDistance or 50) then
                            local velocity = ec.threshold or 50
                            root.Velocity = Vector3.new(0, velocity, 0)
                        end
                    end
                end
            end
        end)
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 19. SpeedBypass / CrouchSpoof / ACManipulate
-- ══════════════════════════════════════════════════════════════════
local function setupSpeedBypass()
    task.spawn(function()
        while not isDestroyed do
            task.wait(0.23)
            if not SETTINGS.SpeedBypass then
            else
                pcall(function()
                    local char = getChar()
                    if not char then return end
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local collision = char:FindFirstChild("Collision")
                    if collision then
                        local cloned = char:FindFirstChild("_CollisionClone")
                        if not cloned and collision:FindFirstChild("CollisionCrouch") then
                            cloned = collision:Clone()
                            cloned.Name = "_CollisionClone"
                            cloned.Massless = true
                            cloned.CanCollide = false
                            cloned.CanQuery = false
                            cloned.Parent = char
                            pcall(function() cloned.CollisionCrouch:Destroy() end)
                        end
                        if cloned then
                            cloned.Massless = false
                            task.wait(0.23)
                            if hrp and hrp.Anchored then
                                cloned.Massless = true
                                task.wait(1)
                            end
                            cloned.Massless = true
                        end
                    end
                end)
            end
        end
    end)
end

local function setupACManipulate()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.ACManipulate then return end
        if not keyStates[SETTINGS.ACManipulateKeybind] then return end
        pcall(function()
            local char = getChar()
            if not char then return end
            char:PivotTo(char:GetPivot() + Camera.CFrame.LookVector * Vector3.new(1, 0, 1) * -100)
        end)
    end)
    table.insert(connections, conn)
end

local function applyCrouchSpoof()
    pcall(function()
        local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
        if rf and rf:FindFirstChild("Crouch") then
            rf.Crouch:FireServer(SETTINGS.CrouchSpoof)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 20. 移动 & 交互
-- ══════════════════════════════════════════════════════════════════
local function updateSpeed()
    if isDestroyed then return end
    local hum = getHumanoid()
    if hum then
        hum.WalkSpeed = 17 + SETTINGS.SpeedBoost
        hum.JumpPower = SETTINGS.JumpPower
    end
end

local function setupNoclip()
    local conn
    conn = RunService.Stepped:Connect(function()
        if isDestroyed then return end
        if not (SETTINGS.Noclip or (SETTINGS.InteractNoclip and SETTINGS.InstantInteract)) then return end
        local char = getChar()
        if not char then return end
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
                v.CanCollide = false
            end
        end
    end)
    table.insert(connections, conn)
end

local function setupInfJump()
    local conn
    conn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp or isDestroyed then return end
        if not SETTINGS.InfJump then return end
        if input.KeyCode == Enum.KeyCode.Space then
            local hum = getHumanoid()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)
    table.insert(connections, conn)
end

local function setupFly()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        if not SETTINGS.Fly then return end
        local root = getRoot()
        local hum = getHumanoid()
        if not root or not hum then return end
        local keys = {
            W = UserInputService:IsKeyDown(Enum.KeyCode.W),
            S = UserInputService:IsKeyDown(Enum.KeyCode.S),
            A = UserInputService:IsKeyDown(Enum.KeyCode.A),
            D = UserInputService:IsKeyDown(Enum.KeyCode.D),
            Space = UserInputService:IsKeyDown(Enum.KeyCode.Space),
            Shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift),
        }
        local speed = SETTINGS.FlySpeed
        if keys.Shift then speed = speed * 2 end
        local cf = Camera.CFrame
        local direction = Vector3.new()
        if keys.W then direction = direction + cf.LookVector end
        if keys.S then direction = direction - cf.LookVector end
        if keys.A then direction = direction - cf.RightVector end
        if keys.D then direction = direction + cf.RightVector end
        if keys.Space then direction = direction + Vector3.new(0, 1, 0) end
        if direction.Magnitude > 0 then
            direction = direction.Unit * speed * 0.016
        end
        root.Velocity = direction * 60
        hum.PlatformStand = true
        hum.GravityScale = 0
    end)
    table.insert(connections, conn)
end

local function stopFly()
    local hum = getHumanoid()
    if hum then
        hum.PlatformStand = false
        hum.GravityScale = 1
    end
end

local function setupSpeedConnection()
    local conn
    conn = RunService.Heartbeat:Connect(updateSpeed)
    table.insert(connections, conn)
end

local function setupAntiAFK()
    pcall(function()
        LocalPlayer.Idled:Connect(function()
            if not isDestroyed and SETTINGS.AntiAFK then
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, nil)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, nil)
            end
        end)
    end)
end

local function setupNoDark()
    if not SETTINGS.NoDark then return end
    pcall(function()
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(200, 200, 200)
        Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
        Lighting.FogEnd = 10000
        for _, eff in pairs(Lighting:GetChildren()) do
            if eff:IsA("ColorCorrectionEffect") or eff:IsA("BlurEffect") or eff:IsA("BloomEffect") then
                eff.Enabled = false
            end
        end
    end)
end

local function setupInstantInteract()
    if not SETTINGS.InstantInteract then return end
    pcall(function()
        local maxDist = SETTINGS.IncreasedDistance and SETTINGS.DoorRange or 10
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("ProximityPrompt") then
                if SETTINGS.IncreasedDistance then
                    pcall(function() v.MaxActivationDistance = SETTINGS.DoorRange end)
                    pcall(function() v.HoldDuration = 0 end)
                end
            end
        end
        local conn
        conn = Workspace.DescendantAdded:Connect(function(desc)
            if isDestroyed then return end
            if desc:IsA("ProximityPrompt") and SETTINGS.IncreasedDistance then
                pcall(function() desc.MaxActivationDistance = SETTINGS.DoorRange end)
                pcall(function() desc.HoldDuration = 0 end)
            end
        end)
        table.insert(connections, conn)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 21. EatCandies（自动吃糖）
-- ══════════════════════════════════════════════════════════════════
local function setupEatCandies()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed or not SETTINGS.EatCandies then return end
        if not keyStates[SETTINGS.EatCandiesKeybind] then return end
        pcall(function()
            local backpack = LocalPlayer:FindFirstChild("Backpack")
            local candy = backpack and backpack:FindFirstChild("Candy")
            if candy and candy:FindFirstChild("Remote") and not candy:FindFirstChild("Meshes/DOORS_EvilCandy_Cube", true) then
                candy.Parent = getChar()
            end
            local char = getChar()
            if char then
                local charCandy = char:FindFirstChild("Candy")
                if charCandy and charCandy:FindFirstChild("Remote") and not charCandy:FindFirstChild("Meshes/DOORS_EvilCandy_Cube", true) then
                    charCandy.Remote:FireServer()
                end
            end
        end)
    end)
    table.insert(connections, conn)
end

-- ══════════════════════════════════════════════════════════════════
-- 22. Visuals / Audio
-- ══════════════════════════════════════════════════════════════════
local function setupVisuals()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        pcall(function()
            -- FieldOfView
            if SETTINGS.FieldOfView > 0 then
                Camera.FieldOfView = SETTINGS.FieldOfView
            end
            -- NoAcceleration
            local char = getChar()
            if char and char:FindFirstChild("HumanoidRootPart") then
                if SETTINGS.NoAcceleration then
                    char.HumanoidRootPart.CustomPhysicalProperties = PhysicalProperties.new(100, 0.7, 0, 1, 1)
                elseif oldAccel then
                    char.HumanoidRootPart.CustomPhysicalProperties = oldAccel
                end
            end
        end)
    end)
    table.insert(connections, conn)
end

local function applyNoFog()
    pcall(function()
        if SETTINGS.NoFog then
            Lighting.FogEnd = 9999
            local atm = Lighting:FindFirstChildWhichIsA("Atmosphere")
            if atm then atm.Density = 0 end
        else
            Lighting.FogEnd = oldFogEnd
        end
    end)
end

local function applyAmbience()
    pcall(function()
        Lighting.GlobalShadows = not SETTINGS.Ambience
        if SETTINGS.Ambience then
            Lighting.OutdoorAmbient = SETTINGS.AmbienceColor
        else
            Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
        end
    end)
end

local function setupRushNodes()
    pcall(function()
        local rooms = getRooms()
        if not rooms then return end
        for _, room in pairs(rooms:GetChildren()) do
            local pn = room:FindFirstChild("PathfindNodes")
            if pn then
                for _, node in pairs(pn:GetChildren()) do
                    if node:IsA("BasePart") then
                        node.Transparency = SETTINGS.RushNodes and 0 or 1
                    end
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 23. Misc 辅助 & 销毁
-- ══════════════════════════════════════════════════════════════════
local function rejoin()
    notify("Rejoin", "正在重新加入...", 3, "Info")
    local ts = game:GetService("TeleportService")
    ts:Teleport(game.PlaceId, LocalPlayer)
end

local function playAgain()
    pcall(function()
        local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
        if rf and rf:FindFirstChild("PlayAgain") then rf.PlayAgain:FireServer() end
    end)
end

local function goLobby()
    pcall(function()
        local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
        if rf and rf:FindFirstChild("Lobby") then rf.Lobby:FireServer() end
    end)
end

local function revive()
    pcall(function()
        local rf = ReplicatedStorage:FindFirstChild("RemotesFolder")
        if rf and rf:FindFirstChild("Revive") then rf.Revive:FireServer() end
    end)
end

local function destroyScript()
    if isDestroyed then return end
    isDestroyed = true
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    connections = {}
    stopFly()
    clearESP()
    if Window then pcall(function() Window:Destroy() end) end
    if _G.QuantumUI_Window then _G.QuantumUI_Window = nil end
    -- 恢复光照
    pcall(function()
        Lighting.GlobalShadows = true
        Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
        Lighting.FogEnd = oldFogEnd
    end)
    pcall(function() StarterGui:SetCore("SendNotification", {
        Title = "销毁", Text = "脚本已彻底销毁", Duration = 2
    }) end)
    print("[Doors] 脚本已彻底销毁")
end

-- ══════════════════════════════════════════════════════════════════
-- 24. 构建 Quantum UI 界面
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title = "Doors 辅助 v3.0",
    Subtitle = "QuantumUI - LXv3 Port",
    ThemeColor = Color3.fromRGB(255, 150, 200),
    Transparency = 0.3,
    Size = UDim2.new(0, 720, 0, 580),
    Keybind = SETTINGS.UIKeybind,
})

_G.QuantumUI_Window = Window

task.wait(0.3)

-- ========== TAB 1: ESP ==========
local ESPTab = Window:AddTab({ Name = "ESP", Icon = "rbxassetid://6034509993" })

ESPTab:AddSection({ Name = "👁️ ESP 主开关" })

ESPTab:AddToggle({
    Name = "ESP 主开关",
    Default = SETTINGS.ESPEnabled,
    Flag = "ESP_Enabled",
    Callback = function(val)
        SETTINGS.ESPEnabled = val
        if val then SETTINGS.DoorsESP = true end
        notify("ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "显示名称",
    Default = SETTINGS.ESPName,
    Flag = "ESP_Name",
    Callback = function(val) SETTINGS.ESPName = val end
})

ESPTab:AddSection({ Name = "📦 物品分类 ESP" })

ESPTab:AddToggle({
    Name = "物品 ESP (Key/Book/...)",
    Default = SETTINGS.DoorsESP,
    Flag = "ESP_Items",
    Callback = function(val) SETTINGS.DoorsESP = val end
})

ESPTab:AddToggle({
    Name = "钥匙 ESP (KeyObtain)",
    Default = SETTINGS.KeyESP,
    Flag = "ESP_Key",
    Callback = function(val) SETTINGS.KeyESP = val end
})

ESPTab:AddToggle({
    Name = "书本 ESP (Library Book)",
    Default = SETTINGS.BookESP,
    Flag = "ESP_Book",
    Callback = function(val) SETTINGS.BookESP = val end
})

ESPTab:AddToggle({
    Name = "断路器/保险丝 ESP",
    Default = SETTINGS.BreakerESP,
    Flag = "ESP_Breaker",
    Callback = function(val) SETTINGS.BreakerESP = val end
})

ESPTab:AddToggle({
    Name = "锚点 ESP (Anchor)",
    Default = SETTINGS.AnchorESP,
    Flag = "ESP_Anchor",
    Callback = function(val) SETTINGS.AnchorESP = val end
})

ESPTab:AddToggle({
    Name = "拉杆 ESP (Lever/Generator)",
    Default = SETTINGS.LeverESP,
    Flag = "ESP_Lever",
    Callback = function(val) SETTINGS.LeverESP = val end
})

ESPTab:AddToggle({
    Name = "柜子 ESP (Cabinet)",
    Default = SETTINGS.CabinetESP,
    Flag = "ESP_Cabinet",
    Callback = function(val) SETTINGS.CabinetESP = val end
})

ESPTab:AddToggle({
    Name = "宝箱 ESP (Chest)",
    Default = SETTINGS.ChestESP,
    Flag = "ESP_Chest",
    Callback = function(val) SETTINGS.ChestESP = val end
})

ESPTab:AddToggle({
    Name = "实体 ESP (Entity)",
    Default = SETTINGS.EntityESP,
    Flag = "ESP_Entity",
    Callback = function(val) SETTINGS.EntityESP = val end
})

ESPTab:AddToggle({
    Name = "其他 ESP (Door/Lever/Gold)",
    Default = SETTINGS.OtherESP,
    Flag = "ESP_Other",
    Callback = function(val) SETTINGS.OtherESP = val end
})

ESPTab:AddToggle({
    Name = "玩家 ESP (Player)",
    Default = SETTINGS.PlayerESP,
    Flag = "ESP_Player",
    Callback = function(val) SETTINGS.PlayerESP = val end
})

ESPTab:AddSection({ Name = "⛏️ 矿井车路径 ESP" })

ESPTab:AddToggle({
    Name = "Minecart Path ESP",
    Default = SETTINGS.MinecartPathESP,
    Flag = "ESP_MinecartPath",
    Callback = function(val) SETTINGS.MinecartPathESP = val end
})

ESPTab:AddDropdown({
    Name = "路径颜色",
    Items = {"Yellow", "Red", "Green", "Cyan", "Orange", "Purple", "White"},
    Default = "Yellow",
    Flag = "ESP_MinecartColor",
    Callback = function(selected) SETTINGS.MinecartPathColor = selected end
})

ESPTab:AddSection({ Name = "🎨 ESP 颜色" })

ESPTab:AddColorPicker({
    Name = "物品颜色",
    Default = SETTINGS.DoorsESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_ItemsColor",
    Callback = function(c) SETTINGS.DoorsESPColor = c end
})

ESPTab:AddColorPicker({
    Name = "钥匙颜色",
    Default = SETTINGS.KeyESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_KeyColor",
    Callback = function(c) SETTINGS.KeyESPColor = c end
})

ESPTab:AddColorPicker({
    Name = "实体颜色",
    Default = SETTINGS.EntityESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_EntityColor",
    Callback = function(c) SETTINGS.EntityESPColor = c end
})

ESPTab:AddColorPicker({
    Name = "柜子颜色",
    Default = SETTINGS.CabinetESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_CabinetColor",
    Callback = function(c) SETTINGS.CabinetESPColor = c end
})

ESPTab:AddColorPicker({
    Name = "宝箱颜色",
    Default = SETTINGS.ChestESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_ChestColor",
    Callback = function(c) SETTINGS.ChestESPColor = c end
})

ESPTab:AddColorPicker({
    Name = "玩家颜色",
    Default = SETTINGS.PlayerESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_PlayerColor",
    Callback = function(c) SETTINGS.PlayerESPColor = c end
})

ESPTab:AddSection({ Name = "⚙️ ESP 参数" })

ESPTab:AddSlider({
    Name = "ESP 刷新速率",
    Min = 0.05, Max = 1, Default = SETTINGS.ESPRefreshRate, Increment = 0.05,
    Suffix = " s",
    Flag = "ESP_Refresh",
    Callback = function(val) SETTINGS.ESPRefreshRate = val end
})

ESPTab:AddSlider({
    Name = "填充透明度",
    Min = 0, Max = 1, Default = SETTINGS.ESPFillTransparency, Increment = 0.05,
    Flag = "ESP_FillTrans",
    Callback = function(val) SETTINGS.ESPFillTransparency = val end
})

ESPTab:AddSlider({
    Name = "描边透明度",
    Min = 0, Max = 1, Default = SETTINGS.ESPOutlineTransparency, Increment = 0.05,
    Flag = "ESP_OutlineTrans",
    Callback = function(val) SETTINGS.ESPOutlineTransparency = val end
})

-- ========== TAB 2: Automation ==========
local AutoTab = Window:AddTab({ Name = "Automation", Icon = "rbxassetid://6034281467" })

AutoTab:AddSection({ Name = "🤝 自动交互" })

AutoTab:AddToggle({
    Name = "Automatic Interact",
    Default = SETTINGS.AutoInteract,
    Flag = "Auto_Interact",
    Callback = function(val)
        SETTINGS.AutoInteract = val
        notify("自动交互", val and "已启用 (按住快捷键)" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AutoTab:AddKeybind({
    Name = "Auto Interact 快捷键 (Hold)",
    Default = SETTINGS.AutoInteractKeybind,
    Flag = "KB_AutoInteract",
    ChangedCallback = function(key) SETTINGS.AutoInteractKeybind = key end
})

AutoTab:AddToggle({
    Name = "使用 Lockpick (门)",
    Default = SETTINGS.AutoInteractUseLockpickDoors,
    Flag = "Auto_LockpickDoors",
    Callback = function(val) SETTINGS.AutoInteractUseLockpickDoors = val end
})

AutoTab:AddToggle({
    Name = "使用 Lockpick (其他)",
    Default = SETTINGS.AutoInteractUseLockpickOther,
    Flag = "Auto_LockpickOther",
    Callback = function(val) SETTINGS.AutoInteractUseLockpickOther = val end
})

AutoTab:AddToggle({
    Name = "忽略光源",
    Default = SETTINGS.AutoInteractIgnoreLightSources,
    Flag = "Auto_IgnoreLight",
    Callback = function(val) SETTINGS.AutoInteractIgnoreLightSources = val end
})

AutoTab:AddToggle({
    Name = "忽略 Can-Die 糖果",
    Default = SETTINGS.AutoInteractIgnoreCanDie,
    Flag = "Auto_IgnoreCanDie",
    Callback = function(val) SETTINGS.AutoInteractIgnoreCanDie = val end
})

AutoTab:AddSlider({
    Name = "Range Multiplier",
    Min = 1, Max = 2, Default = SETTINGS.AutoInteractRange, Increment = 0.1,
    Suffix = "x",
    Flag = "Auto_Range",
    Callback = function(val) SETTINGS.AutoInteractRange = val end
})

AutoTab:AddSection({ Name = "🫥 自动躲藏" })

AutoTab:AddToggle({
    Name = "Automatic Hide",
    Default = SETTINGS.AutoHide,
    Flag = "Auto_Hide",
    Callback = function(val)
        SETTINGS.AutoHide = val
        notify("自动躲藏", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AutoTab:AddToggle({
    Name = "Prediction Visible Check",
    Default = SETTINGS.AutoHideVisCheck,
    Flag = "Auto_HideVisCheck",
    Callback = function(val) SETTINGS.AutoHideVisCheck = val end
})

AutoTab:AddSlider({
    Name = "Prediction Time",
    Min = 0.1, Max = 1.5, Default = SETTINGS.AutoHidePredictionTime, Increment = 0.05,
    Suffix = " s",
    Flag = "Auto_HidePredictTime",
    Callback = function(val) SETTINGS.AutoHidePredictionTime = val end
})

AutoTab:AddSlider({
    Name = "Distance Multiplier",
    Min = 0.8, Max = 1.5, Default = SETTINGS.AutoHidePredictionDistMult, Increment = 0.1,
    Suffix = "x",
    Flag = "Auto_HideDistMult",
    Callback = function(val) SETTINGS.AutoHidePredictionDistMult = val end
})

AutoTab:AddSection({ Name = "🚂 矿井车 & 锚点" })

AutoTab:AddToggle({
    Name = "Minecart Interact Spam",
    Default = SETTINGS.MinecartInteractSpam,
    Flag = "Auto_Minecart",
    Callback = function(val) SETTINGS.MinecartInteractSpam = val end
})

AutoTab:AddKeybind({
    Name = "Minecart Spam 快捷键 (Hold)",
    Default = SETTINGS.MinecartSpamKeybind,
    Flag = "KB_Minecart",
    ChangedCallback = function(key) SETTINGS.MinecartSpamKeybind = key end
})

AutoTab:AddToggle({
    Name = "Anchor Automatic Solve",
    Default = SETTINGS.AnchorAutoSolve,
    Flag = "Auto_Anchor",
    Callback = function(val)
        SETTINGS.AnchorAutoSolve = val
        notify("锚点解谜", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AutoTab:AddSection({ Name = "🔐 密码锁" })

AutoTab:AddToggle({
    Name = "Automatic Library Padlock",
    Default = SETTINGS.AutoPadlockSolve,
    Flag = "Auto_Padlock",
    Callback = function(val)
        SETTINGS.AutoPadlockSolve = val
        notify("密码锁", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AutoTab:AddSlider({
    Name = "Padlock Distance",
    Min = 10, Max = 50, Default = SETTINGS.AutoPadlockDistance, Increment = 1,
    Suffix = " studs",
    Flag = "Auto_PadlockDist",
    Callback = function(val) SETTINGS.AutoPadlockDistance = math.floor(val) end
})

AutoTab:AddSection({ Name = "🍬 自动吃糖" })

AutoTab:AddToggle({
    Name = "Automatic Candy Use",
    Default = SETTINGS.EatCandies,
    Flag = "Auto_Candy",
    Callback = function(val) SETTINGS.EatCandies = val end
})

AutoTab:AddKeybind({
    Name = "Eat Candies 快捷键 (Hold)",
    Default = SETTINGS.EatCandiesKeybind,
    Flag = "KB_Candy",
    ChangedCallback = function(key) SETTINGS.EatCandiesKeybind = key end
})

-- ========== TAB 3: Notifications ==========
local NotifyTab = Window:AddTab({ Name = "Notify", Icon = "rbxassetid://6034996037" })

NotifyTab:AddSection({ Name = "🔔 通知系统" })

NotifyTab:AddToggle({
    Name = "通知主开关",
    Default = SETTINGS.NotifyEnabled,
    Flag = "Notify_Enabled",
    Callback = function(val)
        SETTINGS.NotifyEnabled = val
        notify("通知系统", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

NotifyTab:AddToggle({
    Name = "通知声音",
    Default = SETTINGS.NotifySound,
    Flag = "Notify_Sound",
    Callback = function(val) SETTINGS.NotifySound = val end
})

NotifyTab:AddSlider({
    Name = "声音音量",
    Min = 1, Max = 10, Default = SETTINGS.NotifySoundVolume, Increment = 0.5,
    Flag = "Notify_SoundVol",
    Callback = function(val) SETTINGS.NotifySoundVolume = val end
})

NotifyTab:AddSection({ Name = "📋 通知类型" })

NotifyTab:AddToggle({
    Name = "Anchor Code 通知",
    Default = SETTINGS.NotifyAnchorCode,
    Flag = "Notify_Anchor",
    Callback = function(val) SETTINGS.NotifyAnchorCode = val end
})

NotifyTab:AddToggle({
    Name = "Padlock Code 通知",
    Default = SETTINGS.NotifyPadlockCode,
    Flag = "Notify_Padlock",
    Callback = function(val) SETTINGS.NotifyPadlockCode = val end
})

NotifyTab:AddToggle({
    Name = "实体出现通知",
    Default = SETTINGS.NotifyEntities,
    Flag = "Notify_Entities",
    Callback = function(val)
        SETTINGS.NotifyEntities = val
        entityNotified = {}
    end
})

NotifyTab:AddParagraph({
    Title = "实体通知白名单",
    Content = table.concat({
        "Rush / Blitz / Ambush / Eyes",
        "Lookman / Halt / Screech",
        "Gloombat Swarm / Dread",
        "A-60 / A-120",
        "默认全部启用，可在 SETTINGS 中调整",
    }, "\n")
})

NotifyTab:AddSection({ Name = "🧪 测试" })

NotifyTab:AddButton({
    Name = "🔔 测试通知",
    Callback = function()
        notify("测试通知", "Lorem ipsum dolor sit amet", 2.5, "Info")
    end
})

-- ========== TAB 4: Exploit ==========
local ExploitTab = Window:AddTab({ Name = "Exploit", Icon = "rbxassetid://6034287594" })

ExploitTab:AddSection({ Name = "🛡️ Anti-Entity（反实体触碰）" })

ExploitTab:AddToggle({
    Name = "Anti-Gloombat Egg",
    Default = SETTINGS.AntiGloombat,
    Flag = "Anti_Gloombat",
    Callback = function(val)
        SETTINGS.AntiGloombat = val
        applyAntiEntities()
        notify("Anti-Gloombat", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Giggle",
    Default = SETTINGS.AntiGiggle,
    Flag = "Anti_Giggle",
    Callback = function(val)
        SETTINGS.AntiGiggle = val
        applyAntiEntities()
        notify("Anti-Giggle", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Snare",
    Default = SETTINGS.AntiSnare,
    Flag = "Anti_Snare",
    Callback = function(val)
        SETTINGS.AntiSnare = val
        applyAntiEntities()
        notify("Anti-Snare", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Dupe",
    Default = SETTINGS.AntiDupe,
    Flag = "Anti_Dupe",
    Callback = function(val)
        SETTINGS.AntiDupe = val
        applyAntiEntities()
        notify("Anti-Dupe", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Eyes (强制低头)",
    Default = SETTINGS.AntiEyes,
    Flag = "Anti_Eyes",
    Callback = function(val)
        SETTINGS.AntiEyes = val
        notify("Anti-Eyes", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Lookman (强制低头)",
    Default = SETTINGS.AntiLookman,
    Flag = "Anti_Lookman",
    Callback = function(val)
        SETTINGS.AntiLookman = val
        notify("Anti-Lookman", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Chandelier",
    Default = SETTINGS.AntiChandelier,
    Flag = "Anti_Chandelier",
    Callback = function(val)
        SETTINGS.AntiChandelier = val
        applyAntiEntities()
        notify("Anti-Chandelier", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Seek Arms",
    Default = SETTINGS.AntiSeekArms,
    Flag = "Anti_SeekArms",
    Callback = function(val)
        SETTINGS.AntiSeekArms = val
        applyAntiEntities()
        notify("Anti-Seek Arms", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Always Enable Jumping",
    Default = SETTINGS.AlwaysJump,
    Flag = "Anti_AlwaysJump",
    Callback = function(val)
        SETTINGS.AlwaysJump = val
        pcall(function()
            local char = getChar()
            if char then char:SetAttribute("CanJump", val) end
        end)
        notify("Always Jump", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddSection({ Name = "🚫 Removals（实体移除）" })

ExploitTab:AddToggle({
    Name = "No Screech",
    Default = SETTINGS.NoScreech,
    Flag = "Rmv_NoScreech",
    Callback = function(val)
        SETTINGS.NoScreech = val
        notify("No Screech", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "No A-90",
    Default = SETTINGS.NoA90,
    Flag = "Rmv_NoA90",
    Callback = function(val)
        SETTINGS.NoA90 = val
        notify("No A-90", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "No Halt (Shade)",
    Default = SETTINGS.NoHalt,
    Flag = "Rmv_NoHalt",
    Callback = function(val)
        SETTINGS.NoHalt = val
        notify("No Halt", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Remove Seek Chase",
    Default = SETTINGS.RemoveSeekChase,
    Flag = "Rmv_SeekChase",
    Callback = function(val)
        SETTINGS.RemoveSeekChase = val
        notify("Remove Seek Chase", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddSection({ Name = "💀 Damage Removals" })

ExploitTab:AddToggle({
    Name = "No Screech Damage",
    Default = SETTINGS.NoScreechDamage,
    Flag = "Rmv_NoScreechDmg",
    Callback = function(val) SETTINGS.NoScreechDamage = val end
})

ExploitTab:AddToggle({
    Name = "No A-90 Damage",
    Default = SETTINGS.NoA90Damage,
    Flag = "Rmv_NoA90Dmg",
    Callback = function(val) SETTINGS.NoA90Damage = val end
})

ExploitTab:AddToggle({
    Name = "No Halt Damage",
    Default = SETTINGS.NoHaltDamage,
    Flag = "Rmv_NoHaltDmg",
    Callback = function(val) SETTINGS.NoHaltDamage = val end
})

ExploitTab:AddSection({ Name = "🎬 Jumpscare Removals" })

ExploitTab:AddToggle({
    Name = "Remove Timothy Jumpscare",
    Default = SETTINGS.NoTimothyJumpscare,
    Flag = "Rmv_Timothy",
    Callback = function(val) SETTINGS.NoTimothyJumpscare = val end
})

ExploitTab:AddToggle({
    Name = "Remove Glitch Jumpscare",
    Default = SETTINGS.NoGlitchJumpscare,
    Flag = "Rmv_Glitch",
    Callback = function(val) SETTINGS.NoGlitchJumpscare = val end
})

ExploitTab:AddToggle({
    Name = "Remove Void Effect",
    Default = SETTINGS.NoVoidEffect,
    Flag = "Rmv_Void",
    Callback = function(val) SETTINGS.NoVoidEffect = val end
})

ExploitTab:AddToggle({
    Name = "Remove Seek Effects",
    Default = SETTINGS.NoSeekEffects,
    Flag = "Rmv_SeekEffects",
    Callback = function(val) SETTINGS.NoSeekEffects = val end
})

ExploitTab:AddToggle({
    Name = "No Revive Cutscene",
    Default = SETTINGS.NoReviveCutscene,
    Flag = "Rmv_ReviveCut",
    Callback = function(val) SETTINGS.NoReviveCutscene = val end
})

ExploitTab:AddToggle({
    Name = "No Haste Effects",
    Default = SETTINGS.NoHasteEffect,
    Flag = "Rmv_HasteEffect",
    Callback = function(val) SETTINGS.NoHasteEffect = val end
})

ExploitTab:AddToggle({
    Name = "No Hiding Vignette",
    Default = SETTINGS.NoHidingVignette,
    Flag = "Rmv_HideVignette",
    Callback = function(val) SETTINGS.NoHidingVignette = val end
})

ExploitTab:AddSection({ Name = "🔓 Bypass" })

ExploitTab:AddToggle({
    Name = "Crouch Spoof",
    Default = SETTINGS.CrouchSpoof,
    Flag = "Byp_Crouch",
    Callback = function(val)
        SETTINGS.CrouchSpoof = val
        applyCrouchSpoof()
        notify("Crouch Spoof", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Speed Bypass",
    Default = SETTINGS.SpeedBypass,
    Flag = "Byp_Speed",
    Callback = function(val)
        SETTINGS.SpeedBypass = val
        notify("Speed Bypass", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddToggle({
    Name = "Anti-Cheat Manipulation",
    Default = SETTINGS.ACManipulate,
    Flag = "Byp_ACMani",
    Callback = function(val)
        SETTINGS.ACManipulate = val
        notify("AC Manipulation", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ExploitTab:AddKeybind({
    Name = "AC Manipulate 快捷键 (Hold)",
    Default = SETTINGS.ACManipulateKeybind,
    Flag = "KB_ACMani",
    ChangedCallback = function(key) SETTINGS.ACManipulateKeybind = key end
})

-- ========== TAB 5: Interaction ==========
local InteractTab = Window:AddTab({ Name = "Interaction", Icon = "rbxassetid://6031280882" })

InteractTab:AddSection({ Name = "🤝 交互设置" })

InteractTab:AddToggle({
    Name = "即时交互",
    Default = SETTINGS.InstantInteract,
    Flag = "Int_Instant",
    Callback = function(val)
        SETTINGS.InstantInteract = val
        notify("即时交互", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if val then setupInstantInteract() end
    end
})

InteractTab:AddToggle({
    Name = "启用所有交互",
    Default = SETTINGS.EnableInteractions,
    Flag = "Int_EnableAll",
    Callback = function(val) SETTINGS.EnableInteractions = val end
})

InteractTab:AddToggle({
    Name = "交互穿墙",
    Default = SETTINGS.InteractNoclip,
    Flag = "Int_Noclip",
    Callback = function(val) SETTINGS.InteractNoclip = val end
})

InteractTab:AddToggle({
    Name = "增加交互距离",
    Default = SETTINGS.IncreasedDistance,
    Flag = "Int_IncreasedDist",
    Callback = function(val)
        SETTINGS.IncreasedDistance = val
        if val then setupInstantInteract() end
    end
})

InteractTab:AddSlider({
    Name = "门交互范围",
    Min = 8, Max = 40, Default = SETTINGS.DoorRange, Increment = 1,
    Suffix = " studs",
    Flag = "Int_DoorRange",
    Callback = function(val) SETTINGS.DoorRange = math.floor(val) end
})

InteractTab:AddSection({ Name = "💡 环境设置" })

InteractTab:AddToggle({
    Name = "反黑暗 (NoDark / Fullbright)",
    Default = SETTINGS.NoDark,
    Flag = "Int_NoDark",
    Callback = function(val)
        SETTINGS.NoDark = val
        notify("反黑暗", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if val then setupNoDark() end
    end
})

InteractTab:AddToggle({
    Name = "浪费物品 (WasteItems)",
    Default = SETTINGS.WasteItems,
    Flag = "Int_WasteItems",
    Callback = function(val) SETTINGS.WasteItems = val end
})

-- ========== TAB 6: Movement ==========
local MovementTab = Window:AddTab({ Name = "Movement", Icon = "rbxassetid://6030952461" })

MovementTab:AddSection({ Name = "🏃 基础移动" })

MovementTab:AddSlider({
    Name = "速度加成 (总速度=17+值)",
    Min = 0, Max = 200, Default = SETTINGS.SpeedBoost, Increment = 1,
    Flag = "Move_SpeedBoost",
    Callback = function(val) SETTINGS.SpeedBoost = val; updateSpeed() end
})

MovementTab:AddSlider({
    Name = "跳跃力",
    Min = 50, Max = 200, Default = SETTINGS.JumpPower, Increment = 1,
    Flag = "Move_JumpPower",
    Callback = function(val) SETTINGS.JumpPower = val; updateSpeed() end
})

MovementTab:AddToggle({
    Name = "无限跳跃",
    Default = SETTINGS.InfJump,
    Flag = "Move_InfJump",
    Callback = function(val) SETTINGS.InfJump = val end
})

MovementTab:AddToggle({
    Name = "No Acceleration",
    Default = SETTINGS.NoAcceleration,
    Flag = "Move_NoAccel",
    Callback = function(val) SETTINGS.NoAcceleration = val end
})

MovementTab:AddSection({ Name = "🪁 穿墙/飞行" })

MovementTab:AddToggle({
    Name = "穿墙 (Noclip)",
    Default = SETTINGS.Noclip,
    Flag = "Move_Noclip",
    Callback = function(val) SETTINGS.Noclip = val end
})

MovementTab:AddToggle({
    Name = "飞行 (Fly)",
    Default = SETTINGS.Fly,
    Flag = "Move_Fly",
    Callback = function(val)
        SETTINGS.Fly = val
        if not val then stopFly() end
    end
})

MovementTab:AddSlider({
    Name = "飞行速度",
    Min = 10, Max = 200, Default = SETTINGS.FlySpeed, Increment = 5,
    Flag = "Move_FlySpeed",
    Callback = function(val) SETTINGS.FlySpeed = val end
})

MovementTab:AddToggle({
    Name = "下一房间自动穿墙",
    Default = SETTINGS.NoclipNext,
    Flag = "Move_NoclipNext",
    Callback = function(val) SETTINGS.NoclipNext = val end
})

-- ========== TAB 7: Visuals ==========
local VisualsTab = Window:AddTab({ Name = "Visuals", Icon = "rbxassetid://6034509993" })

VisualsTab:AddSection({ Name = "🎥 视图" })

VisualsTab:AddSlider({
    Name = "Field of View",
    Min = 0, Max = 120, Default = SETTINGS.FieldOfView, Increment = 1,
    Flag = "Vis_FOV",
    Callback = function(val) SETTINGS.FieldOfView = val end
})

VisualsTab:AddToggle({
    Name = "No Camera Shake",
    Default = SETTINGS.NoCamShake,
    Flag = "Vis_NoCamShake",
    Callback = function(val) SETTINGS.NoCamShake = val end
})

VisualsTab:AddToggle({
    Name = "No Look Bobbing",
    Default = SETTINGS.NoLookBob,
    Flag = "Vis_NoLookBob",
    Callback = function(val) SETTINGS.NoLookBob = val end
})

VisualsTab:AddSection({ Name = "🌍 世界" })

VisualsTab:AddToggle({
    Name = "Ambience (更改环境色)",
    Default = SETTINGS.Ambience,
    Flag = "Vis_Ambience",
    Callback = function(val)
        SETTINGS.Ambience = val
        applyAmbience()
    end
})

VisualsTab:AddColorPicker({
    Name = "Ambience 颜色",
    Default = SETTINGS.AmbienceColor,
    Presets = PRESET_COLORS,
    Flag = "Vis_AmbienceColor",
    Callback = function(c)
        SETTINGS.AmbienceColor = c
        applyAmbience()
    end
})

VisualsTab:AddToggle({
    Name = "Remove Fog",
    Default = SETTINGS.NoFog,
    Flag = "Vis_NoFog",
    Callback = function(val)
        SETTINGS.NoFog = val
        applyNoFog()
    end
})

VisualsTab:AddToggle({
    Name = "Show Rush Nodes",
    Default = SETTINGS.RushNodes,
    Flag = "Vis_RushNodes",
    Callback = function(val)
        SETTINGS.RushNodes = val
        setupRushNodes()
    end
})

VisualsTab:AddSection({ Name = "🔊 音频" })

VisualsTab:AddToggle({
    Name = "Silent Jammin Modifier",
    Default = SETTINGS.SilentJammin,
    Flag = "Aud_Jammin",
    Callback = function(val) SETTINGS.SilentJammin = val end
})

VisualsTab:AddToggle({
    Name = "No Haste Sounds",
    Default = SETTINGS.NoHasteSound,
    Flag = "Aud_NoHaste",
    Callback = function(val) SETTINGS.NoHasteSound = val end
})

VisualsTab:AddToggle({
    Name = "No Interacting Sound",
    Default = SETTINGS.SilentInteracting,
    Flag = "Aud_NoInteract",
    Callback = function(val) SETTINGS.SilentInteracting = val end
})

VisualsTab:AddToggle({
    Name = "No Random Ambience",
    Default = SETTINGS.NoRandomAmbience,
    Flag = "Aud_NoAmbience",
    Callback = function(val) SETTINGS.NoRandomAmbience = val end
})

VisualsTab:AddToggle({
    Name = "Silent Gloombats",
    Default = SETTINGS.SilentGloombat,
    Flag = "Aud_SilentGloombat",
    Callback = function(val) SETTINGS.SilentGloombat = val end
})

-- ========== TAB 8: Features ==========
local FeatureTab = Window:AddTab({ Name = "Features", Icon = "rbxassetid://6034281467" })

FeatureTab:AddSection({ Name = "🤖 AutoWardrobe (自动躲柜子)" })

FeatureTab:AddToggle({
    Name = "AutoWardrobe",
    Default = SETTINGS.AutoWardrobe,
    Flag = "Feat_AutoWardrobe",
    Callback = function(val)
        SETTINGS.AutoWardrobe = val
        notify("AutoWardrobe", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

FeatureTab:AddParagraph({
    Title = "AutoWardrobe 说明",
    Content = table.concat({
        "检测到 Rush/Ambush/A60/A120/BackdoorRush 接近时",
        "自动进入最近的柜子/储物柜躲避",
        "",
        "Hotel/Backdoor/Fools → Closet",
        "Mines/Rooms → Locker",
    }, "\n")
})

FeatureTab:AddSection({ Name = "💀 FakeRevive (假复活)" })

FeatureTab:AddToggle({
    Name = "FakeRevive",
    Default = SETTINGS.FakeRevive,
    Flag = "Feat_FakeRevive",
    Callback = function(val)
        SETTINGS.FakeRevive = val
        notify("FakeRevive", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

FeatureTab:AddKeybind({
    Name = "FakeRevive 快捷键",
    Default = SETTINGS.FakeReviveKeybind,
    Flag = "KB_FakeRevive",
    ChangedCallback = function(key) SETTINGS.FakeReviveKeybind = key end
})

FeatureTab:AddSection({ Name = "✝️ InfCrucifixVelocity" })

FeatureTab:AddToggle({
    Name = "InfCrucifixVelocity",
    Default = SETTINGS.InfCrucifixVelocity,
    Flag = "Feat_Crucifix",
    Callback = function(val)
        SETTINGS.InfCrucifixVelocity = val
        notify("InfCrucifixVelocity", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

FeatureTab:AddParagraph({
    Title = "InfCrucifixVelocity 说明",
    Content = table.concat({
        "实体接近时给予向上速度，模拟十字架效果",
        "Rush/Blitz: 52 studs/s, 55 触发距离",
        "Ambush: 70 studs/s, 80 触发距离",
    }, "\n")
})

FeatureTab:AddSection({ Name = "🌀 Anti-Roblox Void" })

FeatureTab:AddToggle({
    Name = "No Roblox Void",
    Default = SETTINGS.AntiRobloxVoid,
    Flag = "Feat_NoVoid",
    Callback = function(val)
        SETTINGS.AntiRobloxVoid = val
        notify("Anti Void", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

-- ========== TAB 9: Keybinds ==========
local KeybindsTab = Window:AddTab({ Name = "Keybinds", Icon = "rbxassetid://6034996037" })

KeybindsTab:AddSection({ Name = "⌨️ 快捷键绑定" })

KeybindsTab:AddKeybind({
    Name = "UI 切换",
    Default = SETTINGS.UIKeybind,
    Flag = "KB_UI",
    ChangedCallback = function(key) SETTINGS.UIKeybind = key end
})

KeybindsTab:AddKeybind({
    Name = "穿墙 (Noclip)",
    Default = SETTINGS.NoclipKeybind,
    Flag = "KB_Noclip",
    ChangedCallback = function(key) SETTINGS.NoclipKeybind = key end
})

KeybindsTab:AddKeybind({
    Name = "飞行 (Fly)",
    Default = SETTINGS.FlyKeybind,
    Flag = "KB_Fly",
    ChangedCallback = function(key) SETTINGS.FlyKeybind = key end
})

KeybindsTab:AddKeybind({
    Name = "Screech 安全屋",
    Default = SETTINGS.ScreechSafeRoomKeybind,
    Flag = "KB_ScreechSafe",
    ChangedCallback = function(key) SETTINGS.ScreechSafeRoomKeybind = key end
})

KeybindsTab:AddParagraph({
    Title = "按键说明",
    Content = table.concat({
        "UI切换键 - 显示/隐藏 UI 面板",
        "穿墙键 - 开关 Noclip 模式",
        "飞行键 - 开关 Fly 模式",
        "Screech键 - 进入最近柜子",
        "FakeRevive键 - 手动假复活",
        "AutoInteract键(Hold) - 自动交互",
        "Minecart键(Hold) - 矿井车连点",
        "ACManipulate键(Hold) - 反作弊操控",
        "EatCandy键(Hold) - 自动吃糖",
        "WASD - 飞行方向控制",
        "Shift (飞行中) - 加速飞行",
    }, "\n")
})

-- ========== TAB 10: Misc ==========
local MiscTab = Window:AddTab({ Name = "Misc", Icon = "rbxassetid://6023243660" })

MiscTab:AddSection({ Name = "🔧 常规设置" })

MiscTab:AddToggle({
    Name = "反挂机 (AntiAFK)",
    Default = SETTINGS.AntiAFK,
    Flag = "Misc_AntiAFK",
    Callback = function(val)
        SETTINGS.AntiAFK = val
        notify("反挂机", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

MiscTab:AddSection({ Name = "🔘 按钮" })

MiscTab:AddButton({
    Name = "🔄 重新加入 (Rejoin)",
    Callback = function() rejoin() end
})

MiscTab:AddButton({
    Name = "▶️ Play Again",
    Callback = function() playAgain() end
})

MiscTab:AddButton({
    Name = "🏠 Lobby",
    Callback = function() goLobby() end
})

MiscTab:AddButton({
    Name = "💉 Revive",
    Callback = function() revive() end
})

MiscTab:AddButton({
    Name = "💀 销毁脚本 (Destroy)",
    Callback = function() destroyScript() end
})

MiscTab:AddSection({ Name = "🌈 彩虹边框" })

MiscTab:AddToggle({
    Name = "彩虹边框动画",
    Default = SETTINGS.RainbowBorder,
    Flag = "Misc_Rainbow",
    Callback = function(state)
        SETTINGS.RainbowBorder = state
        pcall(function() QuantumUI.RainbowEnabled = state end)
    end
})

MiscTab:AddSlider({
    Name = "彩虹速度",
    Min = 0.1, Max = 5, Default = SETTINGS.RainbowSpeed, Increment = 0.1,
    Suffix = "x",
    Flag = "Misc_RainbowSpeed",
    Callback = function(value)
        SETTINGS.RainbowSpeed = value
        pcall(function() QuantumUI.RainbowSpeed = value end)
    end
})

MiscTab:AddSection({ Name = "🎨 主题预设" })

MiscTab:AddDropdown({
    Name = "预设主题色",
    Items = {"DoorsPink", "Cyan", "Purple", "Green", "Red", "Gold", "Pink"},
    Default = "DoorsPink",
    Flag = "Misc_Theme",
    Callback = function(selected)
        local color = THEME_PRESETS[selected]
        if color then
            pcall(function()
                Window.ThemeColor = color
                QuantumUI.ThemeColor = color
                if Window.RefreshTheme then Window:RefreshTheme() end
            end)
            notify("主题", "已切换: " .. selected, 2, "Success")
        end
    end
})

MiscTab:AddSection({ Name = "🏢 楼层信息" })

MiscTab:AddParagraph({
    Title = "支持楼层",
    Content = table.concat({
        "Hotel - 酒店 (原始楼层)",
        "Mines - 矿井 (Floor 2)",
        "Rooms - 房间",
        "Backdoor - 后门",
        "Fools - 愚人 (Super Hard Mode)",
        "Retro - 复古酒店",
    }, "\n")
})

MiscTab:AddSection({ Name = "📖 About" })

MiscTab:AddParagraph({
    Title = "Doors 辅助 v3.0 Features",
    Content = table.concat({
        "✨ ESP 系统:",
        "  - Door/Key/Lever/Item/Book/Breaker",
        "  - Anchor/Entity/Cabinet/Chest/Gold/Player",
        "  - Minecart Path ESP",
        "",
        "🤖 自动化:",
        "  - AutoInteract 自动交互",
        "  - AutoHide 实体预测躲藏",
        "  - AutoPadlock 密码锁解谜",
        "  - AnchorAutoSolve 锚点解谜",
        "  - MinecartInteractSpam 矿井车",
        "  - AutoWardrobe 自动躲柜",
        "",
        "🛡️ Anti-Entity (8 种)",
        "🚫 Removals (Screech/A90/Halt/Seek)",
        "🔓 Bypass (Crouch/Speed/ACManip)",
        "",
        "🎥 Visuals & 🔊 Audio",
        "🏃 移动作弊 (Speed/Jump/Noclip/Fly)",
        "",
        "PlaceId: 6839808510 / 7894711641",
        "源码基于 LX Doors v3 (LOLHAX)",
    }, "\n")
})

-- ══════════════════════════════════════════════════════════════════
-- 25. 主初始化
-- ══════════════════════════════════════════════════════════════════
task.wait(0.5)

-- 缓存旧加速度
pcall(function()
    local char = getChar()
    if char and char:FindFirstChild("HumanoidRootPart") then
        oldAccel = char.HumanoidRootPart.CustomPhysicalProperties
    end
end)

pcall(function() QuantumUI.RainbowEnabled = SETTINGS.RainbowBorder end)
pcall(function() QuantumUI.RainbowSpeed = SETTINGS.RainbowSpeed end)

-- 启动主循环
local espConn = RunService.Heartbeat:Connect(updateESP)
table.insert(connections, espConn)

local notifyConn = RunService.Heartbeat:Connect(checkEntityNotifications)
table.insert(connections, notifyConn)

setupNoclip()
setupInfJump()
setupFly()
setupSpeedConnection()
setupAntiAFK()
setupEntityInterceptors()
setupAntiEntityWatcher()
setupAntiEyesLookman()
setupAutoWardrobe()
setupAutoHide()
setupAutoInteract()
setupMinecartSpam()
setupFakeRevive()
setupInfCrucifixVelocity()
setupSpeedBypass()
setupACManipulate()
setupEatCandies()
setupVisuals()
setupPadlockCodeFinder()
setupAutoPadlockSolver()
setupAnchorAutoSolve()

-- 应用初始状态
applyAntiEntities()

-- ══════════════════════════════════════════════════════════════════
-- 26. 快捷键处理（包括 Hold 模式按键状态）
-- ══════════════════════════════════════════════════════════════════
local inputBeganConn
inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if isDestroyed then return end
    local key = input.KeyCode
    if not gameProcessed then
        keyStates[key] = true
    end

    if gameProcessed then return end

    if key == SETTINGS.NoclipKeybind then
        SETTINGS.Noclip = not SETTINGS.Noclip
        if Window and Window.Flags and Window.Flags["Move_Noclip"] then
            pcall(function() Window.Flags["Move_Noclip"]:Set(SETTINGS.Noclip) end)
        end
        notify("穿墙", SETTINGS.Noclip and "已启用" or "已禁用", 2, SETTINGS.Noclip and "Success" or "Warning")
    elseif key == SETTINGS.FlyKeybind then
        SETTINGS.Fly = not SETTINGS.Fly
        if Window and Window.Flags and Window.Flags["Move_Fly"] then
            pcall(function() Window.Flags["Move_Fly"]:Set(SETTINGS.Fly) end)
        end
        notify("飞行", SETTINGS.Fly and "已启用" or "已禁用", 2, SETTINGS.Fly and "Success" or "Warning")
        if not SETTINGS.Fly then stopFly() end
    elseif key == SETTINGS.ScreechSafeRoomKeybind then
        pcall(function()
            local char = getChar()
            if not char then return end
            local currentFloor = getCurrentFloor()
            local hidingName = HidingPlaceName[currentFloor] or "Closet"
            local closestCabinet = nil
            local closestDist = math.huge
            for _, v in pairs(Workspace:GetDescendants()) do
                if isCabinet(v) and (v:IsA("Model") or v:IsA("BasePart")) then
                    local pp = v:FindFirstChildOfClass("ProximityPrompt", true)
                    local pos = v:IsA("BasePart") and v.Position or (v.PrimaryPart and v.PrimaryPart.Position)
                    if pos and char.PrimaryPart then
                        local dist = (pos - char.PrimaryPart.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestCabinet = pp or v
                        end
                    end
                end
            end
            if closestCabinet and closestCabinet:IsA("ProximityPrompt") then
                fireProximityPrompt(closestCabinet)
                notify("安全屋", "已触发最近柜子", 2, "Success")
            else
                notify("安全屋", "附近未找到柜子", 2, "Warning")
            end
        end)
    elseif key == SETTINGS.FakeReviveKeybind then
        if SETTINGS.FakeRevive then
            local hum = getHumanoid()
            if hum then
                fakeReviveDebounce = true
                hum.Health = 100
                hum.MaxHealth = 100
                hum:ChangeState(Enum.HumanoidStateType.Running)
                LocalPlayer:SetAttribute("Alive", true)
                notify("FakeRevive", "已手动复活", 2, "Success")
            end
        end
    end
end)
table.insert(connections, inputBeganConn)

local inputEndedConn
inputEndedConn = UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if isDestroyed then return end
    keyStates[input.KeyCode] = false
end)
table.insert(connections, inputEndedConn)

-- ══════════════════════════════════════════════════════════════════
-- 27. 加载完成通知
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
notify("✅ Doors 辅助 v3.0 加载完成!",
    "QuantumUI 版本 v3.0\n" ..
    "基于 LX Doors v3 完整重写\n" ..
    "按 " .. tostring(SETTINGS.UIKeybind.Name) .. " 切换 UI 显示\n" ..
    "支持楼层: Hotel/Mines/Rooms/Backdoor/Fools/Retro\n" ..
    "PlaceId: 6839808510 / 7894711641",
    6, "Success")

print("========================================")
print(" Doors 辅助 v3.0 (QuantumUI) 加载完成")
print("   基于 LX Doors v3 (LOLHAX) 完整移植")
print("   UI切换    - " .. tostring(SETTINGS.UIKeybind.Name))
print("   穿墙      - " .. tostring(SETTINGS.NoclipKeybind.Name))
print("   飞行      - " .. tostring(SETTINGS.FlyKeybind.Name))
print("   Screech   - " .. tostring(SETTINGS.ScreechSafeRoomKeybind.Name))
print("   FakeRevive- " .. tostring(SETTINGS.FakeReviveKeybind.Name))
print("   AutoInter - " .. tostring(SETTINGS.AutoInteractKeybind.Name))
print("   Minecart  - " .. tostring(SETTINGS.MinecartSpamKeybind.Name))
print("   ACManip   - " .. tostring(SETTINGS.ACManipulateKeybind.Name))
print("   EatCandy  - " .. tostring(SETTINGS.EatCandiesKeybind.Name))
print("   楼层支持  - Hotel/Mines/Rooms/Backdoor/Fools/Retro")
print("   PlaceId   - 6839808510 / 7894711641")
print("========================================")
