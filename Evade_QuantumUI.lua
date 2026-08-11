--[[
    Evade 辅助脚本 v1.0 (Quantum UI 版)
    适配 PlaceId: 9872472334 (Evade) / GameId: 11818772280
    功能: Nextbot ESP / 玩家ESP / 物品ESP / 自动重生 / 移动修改 / 穿墙 / 飞行 / 全亮 / AntiAFK
    快捷键:
        RightShift - 隐藏/显示 UI
        T          - 传送到出生点 (Lobby)
        Y          - 切换 NoClip
        U          - 切换 Fly
    安全承诺: 不采集任何信息，不 loadstring 外部功能代码，所有逻辑本地实现。
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD
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
    warn("[Evade] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[Evade] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[Evade] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[Evade] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. ROBLOX SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = workspace
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

-- ══════════════════════════════════════════════════════════════════
-- 3. SETTINGS
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- Movement
    EV_WalkSpeed = false,
    EV_WalkSpeedValue = 16,
    EV_JumpPower = false,
    EV_JumpPowerValue = 50,
    EV_InfJump = false,
    EV_NoClip = false,
    EV_Fly = false,
    EV_FlySpeed = 80,
    EV_Gravity = false,
    EV_GravityValue = 196,

    -- ESP
    ESPEnabled = false,
    ESP_Nextbot = false,
    ESP_NextbotColor = Color3.fromRGB(255, 50, 50),
    ESP_Player = false,
    ESP_PlayerColor = Color3.fromRGB(0, 200, 255),
    ESP_Item = false,
    ESP_ItemColor = Color3.fromRGB(255, 215, 0),
    ESP_Door = false,
    ESP_DoorColor = Color3.fromRGB(0, 255, 120),
    ESP_Name = true,
    ESP_Distance = true,
    ESP_Box = false,
    ESP_Tracers = false,
    ESP_Refresh = 0.1,

    -- Visual
    EV_Fullbright = false,
    EV_NoFog = false,
    EV_FOV = false,
    EV_FOVValue = 70,
    EV_NoCameraShake = false,

    -- Auto
    EV_AutoRespawn = false,
    EV_AutoRevive = false,
    EV_AutoCollect = false,
    EV_AutoCollectRange = 10,
    EV_AutoOpenDoors = false,
    EV_AutoOpenDoorsRange = 12,

    -- Misc
    EV_AntiAFK = false,
    EV_LowGravity = false,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 全局变量
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false
local noclipConn = nil
local infJumpConn = nil
local flyConn = nil
local flyBV = nil
local flyBG = nil
local antiAFKConn = nil
local espConn = nil
local espFolder = nil
local gravityConn = nil
local fovConn = nil
local autoCollectConn = nil
local autoOpenDoorsConn = nil
local autoRespawnConn = nil

-- 保存原始Lighting状态
local savedLighting = {
    ClockTime = nil,
    Brightness = nil,
    Ambient = nil,
    OutdoorAmbient = nil,
    FogEnd = nil,
    FogStart = nil,
    Atmosphere = nil,
}

local lightingFolder = nil  -- 用于存储原始Lighting子对象

-- ══════════════════════════════════════════════════════════════════
-- 5. 通知辅助函数
-- ══════════════════════════════════════════════════════════════════
local function notify(title, content, duration, ntype)
    if Window then
        Window:Notify({
            Title    = title,
            Content  = content,
            Duration = duration or 3,
            Type     = ntype or "Info"
        })
    else
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title,
                Text = content,
                Duration = duration or 3
            })
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 6. 工具函数
-- ══════════════════════════════════════════════════════════════════
local function getChar()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHum()
    local char = getChar()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local char = getChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleportTo(pos)
    local root = getRoot()
    if not root then
        notify("传送失败", "找不到 HumanoidRootPart", 3, "Error")
        return false
    end
    local hum = getHum()
    pcall(function()
        root.CFrame = CFrame.new(pos)
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
        end
    end)
    return true
end

local function getLobbySpawn()
    -- 尝试找到出生点位置
    local spawns = Workspace:FindFirstChild("Spawns") or Workspace:FindFirstChild("SpawnLocations")
    if spawns then
        for _, sp in ipairs(spawns:GetChildren()) do
            if sp:IsA("SpawnLocation") or sp:IsA("BasePart") then
                return sp.Position + Vector3.new(0, 3, 0)
            end
        end
    end
    -- 备选: 返回一个较高的默认位置
    local root = getRoot()
    if root then
        return Vector3.new(root.Position.X, root.Position.Y + 50, root.Position.Z)
    end
    return Vector3.new(0, 100, 0)
end

-- ══════════════════════════════════════════════════════════════════
-- 7. ESP 功能
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end
end

local function createHighlight(parent, color, fillTrans, outlineTrans)
    local hl = Instance.new("Highlight")
    hl.Name = "Evade_ESP_Highlight"
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = fillTrans or 0.5
    hl.OutlineTransparency = outlineTrans or 0.2
    hl.Enabled = true
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = parent
    return hl
end

local function createESPBillboard(parent, text, color, yOffset)
    local bb = Instance.new("BillboardGui")
    bb.Name = "Evade_ESP_Billboard"
    bb.Size = UDim2.new(0, 200, 0, 50)
    bb.StudsOffset = Vector3.new(0, (yOffset or 3), 0)
    bb.AlwaysOnTop = true
    bb.Active = true

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 0, 20)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text
    textLabel.TextColor3 = color
    textLabel.TextStrokeTransparency = 0.5
    textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = 14
    textLabel.Parent = bb

    bb.Parent = parent
    return bb
end

local function isNextbot(obj)
    -- Nextbot识别: 名字包含nextbot, 或者有AI相关属性
    local name = string.lower(obj.Name or "")
    if string.find(name, "nextbot") or string.find(name, "bot") then return true end
    -- 检查是否有 Humanoid 且不是玩家
    local hum = obj:FindFirstChildOfClass("Humanoid")
    if hum and not Players:GetPlayerFromCharacter(obj) then
        -- 检查是否是NPC (有Animator, 移动部件等)
        local hrp = obj:FindFirstChild("HumanoidRootPart")
        if hrp and obj:IsA("Model") then
            return true
        end
    end
    -- 检查 Workspace.Nextbots 文件夹
    local nextbotsFolder = Workspace:FindFirstChild("Nextbots") or Workspace:FindFirstChild("AI")
    if nextbotsFolder and obj:IsDescendantOf(nextbotsFolder) then return true end
    return false
end

local function isItem(obj)
    local name = string.lower(obj.Name or "")
    if string.find(name, "money") or string.find(name, "cash") or string.find(name, "battery") then
        return true
    end
    if obj:IsA("Tool") and obj.Parent == Workspace then return true end
    if obj:FindFirstChild("Pickup") or obj:FindFirstChild("Collect") then return true end
    -- 检查 Workspace.Items 文件夹
    local itemsFolder = Workspace:FindFirstChild("Items") or Workspace:FindFirstChild("Pickups")
    if itemsFolder and obj:IsDescendantOf(itemsFolder) then return true end
    return false
end

local function isDoor(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
    local name = string.lower(obj.Name or "")
    if string.find(name, "door") then return true end
    if obj:FindFirstChild("Hinge") or obj:FindFirstChild("DoorHinge") then return true end
    local map = Workspace:FindFirstChild("Map")
    if map and obj:IsDescendantOf(map) then
        if obj:IsA("Model") and obj:FindFirstChild("Door") then return true end
        if obj:FindFirstChild("TouchInterest") and string.find(name, "door") then return true end
    end
    return false
end

local function runESPLoop()
    if not espFolder then
        espFolder = Instance.new("Folder")
        espFolder.Name = "Evade_ESP_Folder"
        espFolder.Parent = CoreGui
    end

    local function processObject(obj, objType, color)
        if not obj or not obj.Parent then return end
        -- 清理旧的ESP标记
        pcall(function()
            for _, c in ipairs(obj:GetChildren()) do
                if c.Name == "Evade_ESP_Highlight" or c.Name == "Evade_ESP_Billboard" then
                    c:Destroy()
                end
            end
        end)

        local model = obj:IsA("Model") and obj or obj.Parent:IsA("Model") and obj.Parent
        if not model then return end

        -- 距离计算
        local myRoot = getRoot()
        local distText = ""
        local targetPart = nil
        if model:IsA("Model") then
            targetPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildOfClass("BasePart")
        else
            targetPart = model
        end
        if myRoot and targetPart and targetPart:IsA("BasePart") then
            local dist = (myRoot.Position - targetPart.Position).Magnitude
            distText = string.format(" [%dm]", math.floor(dist))
        end

        -- Highlight
        if SETTINGS.ESP_Box then
            pcall(function() createHighlight(model, color, 0.6, 0.2) end)
        end

        -- 名称和距离
        if SETTINGS.ESP_Name or SETTINGS.ESP_Distance then
            local displayName = model.Name
            if objType == "Nextbot" then
                displayName = "⚠️ " .. model.Name
            elseif objType == "Player" then
                local p = Players:GetPlayerFromCharacter(model)
                if p then displayName = p.Name end
            elseif objType == "Item" then
                displayName = "💰 " .. model.Name
            elseif objType == "Door" then
                displayName = "🚪 " .. model.Name
            end
            local text = ""
            if SETTINGS.ESP_Name then text = text .. displayName end
            if SETTINGS.ESP_Distance then text = text .. distText end
            pcall(function() createESPBillboard(model, text, color, objType == "Player" and 4 or 2.5) end)
        end
    end

    -- Nextbot ESP
    if SETTINGS.ESP_Nextbot then
        pcall(function()
            local nextbotsFolder = Workspace:FindFirstChild("Nextbots") or Workspace:FindFirstChild("AI")
            if nextbotsFolder then
                for _, nb in ipairs(nextbotsFolder:GetChildren()) do
                    if nb:IsA("Model") then processObject(nb, "Nextbot", SETTINGS.ESP_NextbotColor) end
                end
            end
            -- 兜底: 扫描 Workspace
            for _, obj in ipairs(Workspace:GetChildren()) do
                if obj:IsA("Model") and isNextbot(obj) and obj ~= LocalPlayer.Character then
                    processObject(obj, "Nextbot", SETTINGS.ESP_NextbotColor)
                end
            end
        end)
    end

    -- Player ESP
    if SETTINGS.ESP_Player then
        pcall(function()
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    processObject(p.Character, "Player", SETTINGS.ESP_PlayerColor)
                end
            end
        end)
    end

    -- Item ESP
    if SETTINGS.ESP_Item then
        pcall(function()
            local itemsFolder = Workspace:FindFirstChild("Items") or Workspace:FindFirstChild("Pickups")
            if itemsFolder then
                for _, item in ipairs(itemsFolder:GetDescendants()) do
                    if item:IsA("BasePart") or item:IsA("Tool") then
                        processObject(item, "Item", SETTINGS.ESP_ItemColor)
                    end
                end
            end
            -- 兜底: 散落的工具和物品
            for _, obj in ipairs(Workspace:GetChildren()) do
                if (obj:IsA("Tool") or obj:IsA("BasePart")) and isItem(obj) then
                    processObject(obj, "Item", SETTINGS.ESP_ItemColor)
                end
            end
        end)
    end

    -- Door ESP
    if SETTINGS.ESP_Door then
        pcall(function()
            local map = Workspace:FindFirstChild("Map")
            local scanList = map and map:GetDescendants() or Workspace:GetDescendants()
            for _, obj in ipairs(scanList) do
                if isDoor(obj) then
                    processObject(obj, "Door", SETTINGS.ESP_DoorColor)
                end
            end
        end)
    end
end

local function toggleESP(enabled)
    if espConn then
        espConn:Disconnect()
        espConn = nil
    end
    if enabled then
        local lastRefresh = 0
        espConn = RunService.RenderStepped:Connect(function()
            if isDestroyed then return end
            local now = tick()
            if now - lastRefresh >= (SETTINGS.ESP_Refresh or 0.1) then
                lastRefresh = now
                pcall(runESPLoop)
            end
        end)
    else
        clearESP()
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 移动功能
-- ══════════════════════════════════════════════════════════════════
local function setWalkSpeed(enabled, value)
    local hum = getHum()
    if not hum then return end
    pcall(function()
        hum.WalkSpeed = enabled and value or 16
    end)
end

local function setJumpPower(enabled, value)
    local hum = getHum()
    if not hum then return end
    pcall(function()
        hum.JumpPower = enabled and value or 50
        hum.UseJumpPower = true
    end)
end

local function toggleInfJump(enabled)
    if infJumpConn then
        infJumpConn:Disconnect()
        infJumpConn = nil
    end
    if enabled then
        infJumpConn = UserInputService.UserJumpRequest:Connect(function()
            local hum = getHum()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
end

local function toggleNoclip(enabled)
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    if enabled then
        noclipConn = RunService.Stepped:Connect(function()
            local root = getRoot()
            if root then
                pcall(function()
                    root.CanCollide = false
                end)
                for _, part in ipairs(root.Parent:GetChildren()) do
                    if part:IsA("BasePart") and part ~= root then
                        pcall(function() part.CanCollide = false end)
                    end
                end
            end
        end)
    end
end

local function toggleFly(enabled, speed)
    if flyConn then
        flyConn:Disconnect()
        flyConn = nil
    end
    if flyBV then
        flyBV:Destroy()
        flyBV = nil
    end
    if flyBG then
        flyBG:Destroy()
        flyBG = nil
    end
    if enabled then
        local root = getRoot()
        if not root then return end
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        flyBV.Velocity = Vector3.zero
        flyBV.Parent = root

        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
        flyBG.P = 1e5
        flyBG.CFrame = root.CFrame
        flyBG.Parent = root

        flyConn = RunService.RenderStepped:Connect(function()
            if isDestroyed or not flyBV or not flyBV.Parent then return end
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local move = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0, 1, 0) end
            local spd = speed or 80
            if move.Magnitude > 0 then
                move = move.Unit * spd
            end
            flyBV.Velocity = move
            if root then
                flyBG.CFrame = CFrame.new(root.Position) * cam.CFrame.Rotation
            end
        end)
    end
end

local function toggleGravity(enabled, value)
    if gravityConn then
        gravityConn:Disconnect()
        gravityConn = nil
    end
    if enabled then
        Workspace.Gravity = value or 50
    else
        Workspace.Gravity = 196.2
    end
end

local function toggleFOV(enabled, value)
    if fovConn then
        fovConn:Disconnect()
        fovConn = nil
    end
    if enabled then
        fovConn = RunService.RenderStepped:Connect(function()
            local cam = Workspace.CurrentCamera
            if cam then
                cam.FieldOfView = value or 90
            end
        end)
    else
        local cam = Workspace.CurrentCamera
        if cam then cam.FieldOfView = 70 end
    end
end

local function toggleAntiAFK(enabled)
    if antiAFKConn then
        antiAFKConn:Disconnect()
        antiAFKConn = nil
    end
    if enabled then
        antiAFKConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            pcall(function()
                VirtualUser:Fire("kick")
            end)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 视觉功能
-- ══════════════════════════════════════════════════════════════════
local function toggleFullbright(enabled)
    if enabled then
        -- 保存原始状态
        if savedLighting.ClockTime == nil then
            savedLighting.ClockTime = Lighting.ClockTime
            savedLighting.Brightness = Lighting.Brightness
            savedLighting.Ambient = Lighting.Ambient
            savedLighting.OutdoorAmbient = Lighting.OutdoorAmbient
            savedLighting.FogEnd = Lighting.FogEnd
            savedLighting.FogStart = Lighting.FogStart
        end
        -- 移走原始Lighting子对象(如 Atmosphere, Sky, Bloom等)
        lightingFolder = Instance.new("Folder")
        lightingFolder.Name = "Evade_LightingBackup"
        lightingFolder.Parent = ReplicatedStorage
        for _, child in ipairs(Lighting:GetChildren()) do
            if not child:IsA("PostEffect") or true then
                pcall(function() child.Parent = lightingFolder end)
            end
        end
        -- 设置全亮参数
        Lighting.ClockTime = 14
        Lighting.Brightness = 3
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd = 999999
        Lighting.FogStart = 999999
    else
        -- 恢复
        Lighting.ClockTime = savedLighting.ClockTime or 14
        Lighting.Brightness = savedLighting.Brightness or 1
        Lighting.Ambient = savedLighting.Ambient or Color3.fromRGB(100, 100, 100)
        Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient or Color3.fromRGB(80, 80, 80)
        Lighting.FogEnd = savedLighting.FogEnd or 500
        Lighting.FogStart = savedLighting.FogStart or 0
        -- 还原子对象
        if lightingFolder then
            for _, child in ipairs(lightingFolder:GetChildren()) do
                pcall(function() child.Parent = Lighting end)
            end
            lightingFolder:Destroy()
            lightingFolder = nil
        end
    end
end

local function toggleNoFog(enabled)
    if enabled then
        if savedLighting.FogEnd == nil then
            savedLighting.FogEnd = Lighting.FogEnd
            savedLighting.FogStart = Lighting.FogStart
        end
        Lighting.FogEnd = 999999
        Lighting.FogStart = 999999
    else
        Lighting.FogEnd = savedLighting.FogEnd or 500
        Lighting.FogStart = savedLighting.FogStart or 0
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 自动功能
-- ══════════════════════════════════════════════════════════════════
local function toggleAutoCollect(enabled, range)
    if autoCollectConn then
        autoCollectConn:Disconnect()
        autoCollectConn = nil
    end
    if enabled then
        autoCollectConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            if not myRoot then return end
            local maxRange = range or SETTINGS.EV_AutoCollectRange or 10
            local itemsFolder = Workspace:FindFirstChild("Items") or Workspace:FindFirstChild("Pickups")
            local scanList = itemsFolder and itemsFolder:GetDescendants() or Workspace:GetChildren()
            for _, obj in ipairs(scanList) do
                if not obj or not obj.Parent then continue end
                local part = obj:IsA("BasePart") and obj or (obj:IsA("Model") and obj:FindFirstChildOfClass("BasePart"))
                if part and part:IsA("BasePart") then
                    local dist = (myRoot.Position - part.Position).Magnitude
                    if dist <= maxRange then
                        -- 尝试触发 ProximityPrompt
                        local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                        if not pp and obj.Parent then
                            pp = obj.Parent:FindFirstChildOfClass("ProximityPrompt")
                        end
                        if pp then
                            pcall(function() pp:InputHoldBegin() task.wait(0.05) pp:InputHoldEnd() end)
                        end
                        -- 尝试 Touch
                        pcall(function()
                            local touchTrans = Instance.new("TouchTransmitter")
                            touchTrans.Parent = part
                            firetouchinterest(myRoot, part, 0)
                            firetouchinterest(myRoot, part, 1)
                            touchTrans:Destroy()
                        end)
                        -- 尝试FireServer
                        local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:FindFirstChild("Events")
                        if remotes then
                            local pickupRemote = remotes:FindFirstChild("Pickup") or remotes:FindFirstChild("Collect") or remotes:FindFirstChild("PICKUP")
                            if pickupRemote and pickupRemote:IsA("RemoteEvent") then
                                pcall(function() pickupRemote:FireServer(obj) end)
                            end
                        end
                    end
                end
            end
        end)
    end
end

local function toggleAutoOpenDoors(enabled, range)
    if autoOpenDoorsConn then
        autoOpenDoorsConn:Disconnect()
        autoOpenDoorsConn = nil
    end
    if enabled then
        autoOpenDoorsConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            if not myRoot then return end
            local maxRange = range or SETTINGS.EV_AutoOpenDoorsRange or 12
            local map = Workspace:FindFirstChild("Map") or Workspace
            for _, obj in ipairs(map:GetDescendants()) do
                if not obj or not obj.Parent then continue end
                local name = string.lower(obj.Name or "")
                if string.find(name, "door") then
                    local doorBase = obj:FindFirstChild("DoorBase") or obj:FindFirstChildOfClass("BasePart")
                    if doorBase and doorBase:IsA("BasePart") then
                        local dist = (myRoot.Position - doorBase.Position).Magnitude
                        if dist <= maxRange then
                            -- 触发ProximityPrompt
                            local pp = obj:FindFirstChildOfClass("ProximityPrompt")
                            if pp then
                                pcall(function() pp:InputHoldBegin() task.wait(0.05) pp:InputHoldEnd() end)
                            end
                            -- 尝试事件调用
                            local events = obj:FindFirstChild("Events")
                            if events then
                                local toggleEvent = events:FindFirstChild("Toggle") or events:FindFirstChild("Open")
                                if toggleEvent then
                                    pcall(function() toggleEvent:FireServer("Open") end)
                                end
                            end
                            -- 点击Detector
                            local click = obj:FindFirstChildOfClass("ClickDetector")
                            if click then
                                pcall(function()
                                    fireclickdetector(click)
                                end)
                            end
                        end
                    end
                end
            end
        end)
    end
end

local function toggleAutoRespawn(enabled)
    if autoRespawnConn then
        autoRespawnConn:Disconnect()
        autoRespawnConn = nil
    end
    if enabled then
        autoRespawnConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if hum and hum.Health <= 0 then
                pcall(function()
                    LocalPlayer:LoadCharacter()
                end)
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 创建 UI
-- ══════════════════════════════════════════════════════════════════
local GameName = "Evade"
local PlaceId   = game.PlaceId

Window = QuantumUI.new({
    Title    = "Evade",
    Subtitle = "Nextbot 逃生辅助 v1.0",
    ThemeColor = Color3.fromRGB(180, 60, 255),
    Transparency = 0.3,
    Size     = UDim2.new(0, 640, 0, 560),
    Keybind  = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: ESP ──
local ESP_Tab = Window:AddTab({
    Name = "ESP",
    Icon = "rbxassetid://6034287594",
})

ESP_Tab:AddSection({ Name = "ESP 总开关" })

ESP_Tab:AddToggle({
    Name     = "启用 ESP",
    Default  = false,
    Flag     = "EV_ESPEnabled",
    Callback = function(s)
        SETTINGS.ESPEnabled = s
        toggleESP(s)
        if s then
            notify("ESP", "ESP 已启动", 2, "Success")
        else
            notify("ESP", "ESP 已关闭", 1.5, "Info")
        end
    end,
})

ESP_Tab:AddSlider({
    Name      = "刷新间隔",
    Min       = 0.03, Max = 0.5, Default = 0.1, Increment = 0.01,
    Suffix    = "s",
    Flag      = "EV_ESPRefresh",
    Callback  = function(v) SETTINGS.ESP_Refresh = v end,
})

ESP_Tab:AddSection({ Name = "ESP 显示选项" })

ESP_Tab:AddToggle({
    Name     = "显示名称",
    Default  = true,
    Flag     = "EV_ESPName",
    Callback = function(s) SETTINGS.ESP_Name = s end,
})

ESP_Tab:AddToggle({
    Name     = "显示距离",
    Default  = true,
    Flag     = "EV_ESPDistance",
    Callback = function(s) SETTINGS.ESP_Distance = s end,
})

ESP_Tab:AddToggle({
    Name     = "高亮框 (Box)",
    Default  = false,
    Flag     = "EV_ESPBox",
    Callback = function(s) SETTINGS.ESP_Box = s end,
})

ESP_Tab:AddSection({ Name = "Nextbot (追踪者) ESP" })

ESP_Tab:AddToggle({
    Name     = "启用 Nextbot ESP",
    Default  = false,
    Flag     = "EV_ESPNextbot",
    Callback = function(s)
        SETTINGS.ESP_Nextbot = s
        if not SETTINGS.ESPEnabled and s then
            SETTINGS.ESPEnabled = true
            toggleESP(true)
        end
    end,
})

ESP_Tab:AddColorPicker({
    Name     = "Nextbot 颜色",
    Default  = Color3.fromRGB(255, 50, 50),
    Flag     = "EV_NextbotColor",
    Callback  = function(c) SETTINGS.ESP_NextbotColor = c end,
})

ESP_Tab:AddSection({ Name = "玩家 ESP" })

ESP_Tab:AddToggle({
    Name     = "启用 玩家 ESP",
    Default  = false,
    Flag     = "EV_ESPPlayer",
    Callback = function(s)
        SETTINGS.ESP_Player = s
        if not SETTINGS.ESPEnabled and s then
            SETTINGS.ESPEnabled = true
            toggleESP(true)
        end
    end,
})

ESP_Tab:AddColorPicker({
    Name     = "玩家 颜色",
    Default  = Color3.fromRGB(0, 200, 255),
    Flag     = "EV_PlayerColor",
    Callback  = function(c) SETTINGS.ESP_PlayerColor = c end,
})

ESP_Tab:AddSection({ Name = "物品 / 门 ESP" })

ESP_Tab:AddToggle({
    Name     = "启用 物品 ESP (Money/Battery)",
    Default  = false,
    Flag     = "EV_ESPItem",
    Callback = function(s)
        SETTINGS.ESP_Item = s
        if not SETTINGS.ESPEnabled and s then
            SETTINGS.ESPEnabled = true
            toggleESP(true)
        end
    end,
})

ESP_Tab:AddColorPicker({
    Name     = "物品 颜色",
    Default  = Color3.fromRGB(255, 215, 0),
    Flag     = "EV_ItemColor",
    Callback  = function(c) SETTINGS.ESP_ItemColor = c end,
})

ESP_Tab:AddToggle({
    Name     = "启用 门 ESP",
    Default  = false,
    Flag     = "EV_ESPDoor",
    Callback = function(s)
        SETTINGS.ESP_Door = s
        if not SETTINGS.ESPEnabled and s then
            SETTINGS.ESPEnabled = true
            toggleESP(true)
        end
    end,
})

ESP_Tab:AddColorPicker({
    Name     = "门 颜色",
    Default  = Color3.fromRGB(0, 255, 120),
    Flag     = "EV_DoorColor",
    Callback  = function(c) SETTINGS.ESP_DoorColor = c end,
})

ESP_Tab:AddButton({
    Name = "🧹 清除所有 ESP 对象",
    Callback = function()
        clearESP()
        notify("ESP", "已清除所有 ESP 标记", 2, "Info")
    end,
})

-- ── TAB 2: 移动修改 ──
local MoveTab = Window:AddTab({
    Name = "移动",
    Icon = "rbxassetid://6034466796",
})

MoveTab:AddSection({ Name = "移动速度" })

MoveTab:AddToggle({
    Name     = "WalkSpeed",
    Default  = false,
    Flag     = "EV_WalkSpeedEnabled",
    Callback = function(s)
        SETTINGS.EV_WalkSpeed = s
        setWalkSpeed(s, SETTINGS.EV_WalkSpeedValue)
    end,
})

MoveTab:AddSlider({
    Name      = "WalkSpeed 值",
    Min       = 16, Max = 300, Default = 35, Increment = 1,
    Flag      = "EV_WalkSpeedValue",
    Callback  = function(v)
        SETTINGS.EV_WalkSpeedValue = v
        if SETTINGS.EV_WalkSpeed then
            setWalkSpeed(true, v)
        end
    end,
})

MoveTab:AddSection({ Name = "跳跃" })

MoveTab:AddToggle({
    Name     = "JumpPower",
    Default  = false,
    Flag     = "EV_JumpPowerEnabled",
    Callback = function(s)
        SETTINGS.EV_JumpPower = s
        setJumpPower(s, SETTINGS.EV_JumpPowerValue)
    end,
})

MoveTab:AddSlider({
    Name      = "JumpPower 值",
    Min       = 50, Max = 200, Default = 100, Increment = 1,
    Flag      = "EV_JumpPowerValue",
    Callback  = function(v)
        SETTINGS.EV_JumpPowerValue = v
        if SETTINGS.EV_JumpPower then
            setJumpPower(true, v)
        end
    end,
})

MoveTab:AddToggle({
    Name     = "InfJump (无限跳)",
    Default  = false,
    Flag     = "EV_InfJump",
    Callback = function(s)
        SETTINGS.EV_InfJump = s
        toggleInfJump(s)
    end,
})

MoveTab:AddSection({ Name = "重力 / FOV" })

MoveTab:AddToggle({
    Name     = "低重力 (Low Gravity)",
    Default  = false,
    Flag     = "EV_LowGravity",
    Callback = function(s)
        SETTINGS.EV_LowGravity = s
        toggleGravity(s, SETTINGS.EV_GravityValue)
    end,
})

MoveTab:AddSlider({
    Name      = "重力值",
    Min       = 10, Max = 196, Default = 50, Increment = 1,
    Flag      = "EV_GravityValue",
    Callback  = function(v)
        SETTINGS.EV_GravityValue = v
        if SETTINGS.EV_LowGravity then
            toggleGravity(true, v)
        end
    end,
})

MoveTab:AddToggle({
    Name     = "自定义 FOV",
    Default  = false,
    Flag     = "EV_FOV",
    Callback = function(s)
        SETTINGS.EV_FOV = s
        toggleFOV(s, SETTINGS.EV_FOVValue)
    end,
})

MoveTab:AddSlider({
    Name      = "FOV 值",
    Min       = 60, Max = 120, Default = 90, Increment = 1,
    Suffix    = "°",
    Flag      = "EV_FOVValue",
    Callback  = function(v)
        SETTINGS.EV_FOVValue = v
        if SETTINGS.EV_FOV then
            toggleFOV(true, v)
        end
    end,
})

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({
    Name     = "NoClip (穿墙)",
    Default  = false,
    Flag     = "EV_NoClip",
    Callback = function(s)
        SETTINGS.EV_NoClip = s
        toggleNoclip(s)
    end,
})

MoveTab:AddToggle({
    Name     = "Fly (飞行)",
    Default  = false,
    Flag     = "EV_Fly",
    Callback = function(s)
        SETTINGS.EV_Fly = s
        toggleFly(s, SETTINGS.EV_FlySpeed)
        if not s then
            notify("飞行已关闭", "", 1.5, "Info")
        end
    end,
})

MoveTab:AddSlider({
    Name      = "Fly Speed",
    Min       = 10, Max = 300, Default = 80, Increment = 5,
    Flag      = "EV_FlySpeed",
    Callback  = function(v)
        SETTINGS.EV_FlySpeed = v
        if SETTINGS.EV_Fly then
            toggleFly(true, v)
        end
    end,
})

-- ── TAB 3: 视觉 ──
local VisualTab = Window:AddTab({
    Name = "视觉",
    Icon = "rbxassetid://6035153470",
})

VisualTab:AddSection({ Name = "视觉功能" })

VisualTab:AddToggle({
    Name     = "全亮 (Fullbright)",
    Default  = false,
    Flag     = "EV_Fullbright",
    Callback = function(s)
        SETTINGS.EV_Fullbright = s
        toggleFullbright(s)
    end,
})

VisualTab:AddToggle({
    Name     = "无雾 (No Fog)",
    Default  = false,
    Flag     = "EV_NoFog",
    Callback = function(s)
        SETTINGS.EV_NoFog = s
        toggleNoFog(s)
    end,
})

-- ── TAB 4: 自动功能 ──
local AutoTab = Window:AddTab({
    Name = "自动",
    Icon = "rbxassetid://6031280882",
})

AutoTab:AddSection({ Name = "复活 / 重生" })

AutoTab:AddToggle({
    Name     = "自动重生 (死亡立即复活)",
    Default  = false,
    Flag     = "EV_AutoRespawn",
    Callback = function(s)
        SETTINGS.EV_AutoRespawn = s
        toggleAutoRespawn(s)
    end,
})

AutoTab:AddSection({ Name = "自动收集" })

AutoTab:AddToggle({
    Name     = "自动拾取物品 (Money/Battery)",
    Default  = false,
    Flag     = "EV_AutoCollect",
    Callback = function(s)
        SETTINGS.EV_AutoCollect = s
        toggleAutoCollect(s, SETTINGS.EV_AutoCollectRange)
    end,
})

AutoTab:AddSlider({
    Name      = "拾取范围",
    Min       = 3, Max = 30, Default = 10, Increment = 1,
    Suffix    = "studs",
    Flag      = "EV_AutoCollectRange",
    Callback  = function(v)
        SETTINGS.EV_AutoCollectRange = v
        if SETTINGS.EV_AutoCollect then
            toggleAutoCollect(true, v)
        end
    end,
})

AutoTab:AddSection({ Name = "自动开门" })

AutoTab:AddToggle({
    Name     = "自动开门",
    Default  = false,
    Flag     = "EV_AutoOpenDoors",
    Callback = function(s)
        SETTINGS.EV_AutoOpenDoors = s
        toggleAutoOpenDoors(s, SETTINGS.EV_AutoOpenDoorsRange)
    end,
})

AutoTab:AddSlider({
    Name      = "开门范围",
    Min       = 3, Max = 30, Default = 12, Increment = 1,
    Suffix    = "studs",
    Flag      = "EV_AutoOpenDoorsRange",
    Callback  = function(v)
        SETTINGS.EV_AutoOpenDoorsRange = v
        if SETTINGS.EV_AutoOpenDoors then
            toggleAutoOpenDoors(true, v)
        end
    end,
})

-- ── TAB 5: 杂项 ──
local MiscTab = Window:AddTab({
    Name = "杂项",
    Icon = "rbxassetid://6031280882",
})

MiscTab:AddSection({ Name = "传送" })

MiscTab:AddButton({
    Name = "🏠 传送到出生点 (Lobby)",
    Callback = function()
        local pos = getLobbySpawn()
        if teleportTo(pos) then
            notify("传送", "已传送到出生点", 2, "Success")
        end
    end,
})

MiscTab:AddSection({ Name = "当前坐标" })

local coordsLabel = MiscTab:AddLabel({ Text = "X: 0.00  Y: 0.00  Z: 0.00" })
task.spawn(function()
    RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root and coordsLabel then
            local p = root.Position
            coordsLabel:SetText(string.format("X: %.2f   Y: %.2f   Z: %.2f", p.X, p.Y, p.Z))
        end
    end)
end)

MiscTab:AddButton({
    Name = "打印当前坐标 (控制台)",
    Callback = function()
        local root = getRoot()
        if root then
            local p = root.Position
            print(("[Evade] 当前坐标: Vector3.new(%.3f, %.3f, %.3f)"):format(p.X, p.Y, p.Z))
            notify("坐标", string.format("X:%.2f Y:%.2f Z:%.2f\n已输出控制台", p.X, p.Y, p.Z), 3, "Info")
        end
    end,
})

MiscTab:AddButton({
    Name = "复制 Vector3 坐标",
    Callback = function()
        local root = getRoot()
        if root then
            local p = root.Position
            local s = string.format("Vector3.new(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
            if setclipboard then
                setclipboard(s)
                notify("已复制", s, 2, "Success")
            else
                notify("失败", "执行器不支持剪贴板", 2, "Error")
            end
        end
    end,
})

MiscTab:AddSection({ Name = "功能" })

MiscTab:AddToggle({
    Name     = "Anti-AFK",
    Default  = false,
    Flag     = "EV_AntiAFK",
    Callback = function(s)
        SETTINGS.EV_AntiAFK = s
        toggleAntiAFK(s)
    end,
})

MiscTab:AddButton({
    Name = "💀 重置角色 (自杀)",
    Callback = function()
        local char = getChar()
        if char then
            pcall(function()
                char:FindFirstChildOfClass("Humanoid").Health = 0
            end)
        end
    end,
})

MiscTab:AddSection({ Name = "信息" })

MiscTab:AddParagraph({
    Title   = "Evade 辅助 v1.0",
    Content = table.concat({
        "游戏: Evade (Nextbot 逃生)",
        "PlaceId: " .. tostring(PlaceId),
        "",
        "功能列表:",
        "• Nextbot ESP (红色警告高亮)",
        "• 玩家 ESP (蓝色高亮)",
        "• 物品 ESP (钱/电池金色高亮)",
        "• 门 ESP (绿色高亮)",
        "• ESP 显示: 名称/距离/高亮框",
        "• 移动修改 (WalkSpeed/JumpPower/InfJump)",
        "• 低重力 + 自定义 FOV",
        "• NoClip 穿墙 + Fly 飞行",
        "• 全亮 + 无雾",
        "• 自动重生 + 自动拾取 + 自动开门",
        "• Anti-AFK + 坐标获取",
        "",
        "快捷键:",
        "  RightShift - 隐藏/显示 UI",
        "  T - 传送到出生点",
        "  Y - 切换 NoClip",
        "  U - 切换 Fly",
        "",
        "注意:",
        "  Nextbot ESP 建议保持开启",
        "  被追时开 NoClip/Fly 快速逃脱",
        "  自动拾取范围建议 8~15 studs",
        "  自动开门会经过所有门自动开启",
    }, "\n"),
})

-- ── 快捷键绑定 ──
local keybinds = {
    [Enum.KeyCode.T] = function()
        local pos = getLobbySpawn()
        if teleportTo(pos) then
            notify("T 快捷键", "→ 出生点", 1.5, "Info")
        end
    end,
    [Enum.KeyCode.Y] = function()
        local newState = not SETTINGS.EV_NoClip
        SETTINGS.EV_NoClip = newState
        toggleNoclip(newState)
        notify("Y 快捷键", newState and "NoClip 已开启" or "NoClip 已关闭", 1.5, newState and "Success" or "Info")
    end,
    [Enum.KeyCode.U] = function()
        local newState = not SETTINGS.EV_Fly
        SETTINGS.EV_Fly = newState
        toggleFly(newState, SETTINGS.EV_FlySpeed)
        notify("U 快捷键", newState and "Fly 已开启" or "Fly 已关闭", 1.5, newState and "Success" or "Info")
    end,
}

local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local key = input.KeyCode
    for k, cb in pairs(keybinds) do
        if key == k then
            task.spawn(cb)
            break
        end
    end
end)

-- 角色重生时恢复移动设置
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if isDestroyed then return end
    setWalkSpeed(SETTINGS.EV_WalkSpeed, SETTINGS.EV_WalkSpeedValue)
    setJumpPower(SETTINGS.EV_JumpPower, SETTINGS.EV_JumpPowerValue)
    if SETTINGS.EV_NoClip then toggleNoclip(true) end
    if SETTINGS.EV_InfJump then toggleInfJump(true) end
end)

-- ── 清理函数 ──
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    if inputConn then inputConn:Disconnect() end
    if charAddedConn then charAddedConn:Disconnect() end
    if noclipConn then noclipConn:Disconnect() end
    if infJumpConn then infJumpConn:Disconnect() end
    if flyConn then flyConn:Disconnect() end
    if antiAFKConn then antiAFKConn:Disconnect() end
    if espConn then espConn:Disconnect() end
    if gravityConn then gravityConn:Disconnect() end
    if fovConn then fovConn:Disconnect() end
    if autoCollectConn then autoCollectConn:Disconnect() end
    if autoOpenDoorsConn then autoOpenDoorsConn:Disconnect() end
    if autoRespawnConn then autoRespawnConn:Disconnect() end

    if flyBV then flyBV:Destroy() end
    if flyBG then flyBG:Destroy() end

    clearESP()

    SETTINGS.EV_WalkSpeed = false
    SETTINGS.EV_JumpPower = false
    SETTINGS.EV_InfJump = false
    SETTINGS.EV_NoClip = false
    SETTINGS.EV_Fly = false
    SETTINGS.EV_AntiAFK = false
    SETTINGS.EV_LowGravity = false
    SETTINGS.EV_FOV = false
    SETTINGS.EV_Fullbright = false
    SETTINGS.EV_NoFog = false
    SETTINGS.EV_AutoCollect = false
    SETTINGS.EV_AutoOpenDoors = false
    SETTINGS.EV_AutoRespawn = false
    SETTINGS.ESPEnabled = false

    setWalkSpeed(false, 16)
    setJumpPower(false, 50)
    toggleGravity(false)
    toggleFOV(false)
    toggleFullbright(false)
    toggleNoFog(false)

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Evade",
            Text  = "脚本已卸载",
            Duration = 2
        })
    end)
end

_G.Evade_Cleanup = cleanup

-- ── 完成通知 ──
task.wait(0.5)
notify("Evade v1.0", "Evade 辅助已加载\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[Evade] %s (PlaceId: %d) 辅助加载完成", GameName, PlaceId))
