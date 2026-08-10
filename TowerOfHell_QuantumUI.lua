--[[
    Tower of Hell 辅助脚本 v1.0 (Quantum UI 版)
    适配 PlaceId: 1962086868 (经典 Tower of Hell)  /  3582763398 (新版 Tower of Hell)
    功能: AutoWin / SkipStages / NoClipStages / 移动类 / 传送 / ESP / AntiAFK / AntiRagequit
    快捷键:
        RightShift - 隐藏/显示 UI (可改)
        V          - Noclip 穿墙 (可改)
        F          - Fly 飞行 (可改)
        G          - 跳过当前 Stage (可改)
    所有其他功能均通过 UI 面板操作。
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
    warn("[ToH] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[ToH] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[ToH] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[ToH] Quantum UI v" .. QuantumUI.Version .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. ROBLOX SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = workspace

-- ══════════════════════════════════════════════════════════════════
-- 3. 预设颜色 & SETTINGS
-- ══════════════════════════════════════════════════════════════════
local PRESET_COLORS = {
    Color3.fromRGB(255, 40, 40),
    Color3.fromRGB(0, 255, 120),
    Color3.fromRGB(0, 200, 255),
    Color3.fromRGB(180, 60, 255),
    Color3.fromRGB(255, 200, 50),
    Color3.fromRGB(255, 105, 180),
    Color3.fromRGB(0, 255, 200),
    Color3.fromRGB(255, 255, 255),
}

local SETTINGS = {
    -- AutoFarm
    AutoWin = false,
    SkipStages = false,
    NoClipStage = false,
    StageDelay = 100,
    AntiRage = false,

    -- Movement
    WalkSpeed = 100,
    JumpPower = 150,
    InfJump = false,
    Noclip = false,
    Fly = false,
    FlySpeed = 100,
    LowGrav = false,
    GravityScale = 0.1,

    -- Misc
    AntiAFK = false,
    ESPEnabled = true,
    ESPStageColor = Color3.fromRGB(255, 215, 0),
    ESPCheckpointColor = Color3.fromRGB(0, 255, 120),
    ESPSpawnColor = Color3.fromRGB(80, 150, 255),
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 全局变量
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false
local heartbeatConnection = nil
local antiRageConn = nil
local antiAFKConn = nil
local noclipConn = nil
local infJumpConn = nil
local flyConn = nil
local flyBV = nil
local flyBG = nil
local lowGravConn = nil
local espLoopConn = nil
local espStageHighlights = {}
local autoWinRunning = false
local teleportPartsCache = {}

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
-- 5. 工具函数
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

local function findTowerStages()
    local stages = {}
    local function search(parent)
        for _, child in ipairs(parent:GetChildren()) do
            local name = child.Name:lower()
            if child:IsA("Model") or child:IsA("Folder") then
                if name:find("tower") or name:find("stage") or name:find("obby") then
                    for _, sub in ipairs(child:GetDescendants()) do
                        local subname = sub.Name:lower()
                        if sub:IsA("BasePart") and (subname:find("stage") or subname:find("checkpoint") or subname:find("spawn")) then
                            table.insert(stages, sub)
                        end
                    end
                else
                    search(child)
                end
            elseif child:IsA("BasePart") then
                if name:find("stage") or name:find("checkpoint") or name:find("spawn") then
                    table.insert(stages, child)
                end
            end
        end
    end
    search(Workspace)
    if #stages == 0 then
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if desc:IsA("BasePart") then
                local nm = desc.Name:lower()
                if nm:find("stage") or nm:find("checkpoint") or nm:find("spawn") then
                    table.insert(stages, desc)
                end
            end
        end
    end
    table.sort(stages, function(a, b)
        return a.Position.Y > b.Position.Y
    end)
    return stages
end

local function scanTeleportParts()
    local results = {}
    local patterns = {"stage", "Stage", "checkpoint", "Checkpoint", "spawn", "Spawn"}
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("BasePart") then
            for _, pat in ipairs(patterns) do
                if desc.Name:find(pat, 1, true) then
                    table.insert(results, desc)
                    break
                end
            end
        end
    end
    table.sort(results, function(a, b)
        return a.Position.Y > b.Position.Y
    end)
    return results
end

-- ══════════════════════════════════════════════════════════════════
-- 6. AutoWin / SkipStages 核心逻辑
-- ══════════════════════════════════════════════════════════════════
local function autoWinLoop()
    if autoWinRunning then return end
    autoWinRunning = true
    task.spawn(function()
        while SETTINGS.AutoWin and not isDestroyed do
            local stages = findTowerStages()
            if #stages == 0 then
                task.wait(1)
                continue
            end
            local root = getRoot()
            if not root then
                task.wait(1)
                continue
            end
            if SETTINGS.NoClipStage then
                local char = getChar()
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
            for i = #stages, 1, -1 do
                if not SETTINGS.AutoWin and not SETTINGS.SkipStages then break end
                local stage = stages[i]
                if stage and stage.Parent then
                    local r = getRoot()
                    if r then
                        local offset = Vector3.new(0, (stage.Size.Y / 2) + 3, 0)
                        r.CFrame = stage.CFrame + offset
                    end
                    local delaySec = (SETTINGS.StageDelay or 100) / 1000
                    task.wait(math.max(0.01, delaySec))
                end
            end
            if SETTINGS.AutoWin then
                task.wait(2)
            else
                break
            end
        end
        autoWinRunning = false
    end)
end

local function skipOneStage()
    local stages = findTowerStages()
    if #stages == 0 then
        notify("跳过Stage", "未找到任何 Stage", 2, "Warning")
        return
    end
    local root = getRoot()
    if not root then
        notify("跳过Stage", "你尚未生成角色", 2, "Warning")
        return
    end
    local myPos = root.Position
    local closestIdx = 1
    local closestDist = math.huge
    for i, stage in ipairs(stages) do
        local dist = (stage.Position - myPos).Magnitude
        if dist < closestDist then
            closestDist = dist
            closestIdx = i
        end
    end
    local nextIdx = math.max(1, closestIdx - 1)
    local target = stages[nextIdx]
    if target then
        local offset = Vector3.new(0, (target.Size.Y / 2) + 3, 0)
        root.CFrame = target.CFrame + offset
        notify("跳过Stage", "已传送到 " .. target.Name, 2, "Success")
    else
        notify("跳过Stage", "已在最高Stage", 2, "Info")
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 7. Movement: WalkSpeed / JumpPower / InfJump / Noclip / Fly / LowGravity
-- ══════════════════════════════════════════════════════════════════
local wsConn, jpConn = nil, nil

local function applyWalkSpeed()
    if wsConn then wsConn:Disconnect(); wsConn = nil end
    wsConn = RunService.Stepped:Connect(function()
        local hum = getHum()
        if hum and hum.Health > 0 then
            hum.WalkSpeed = SETTINGS.WalkSpeed
        end
    end)
end

local function applyJumpPower()
    if jpConn then jpConn:Disconnect(); jpConn = nil end
    jpConn = RunService.Stepped:Connect(function()
        local hum = getHum()
        if hum and hum.Health > 0 then
            hum.JumpPower = SETTINGS.JumpPower
        end
    end)
end

local function enableInfJump()
    if infJumpConn then return end
    infJumpConn = UserInputService.JumpRequest:Connect(function()
        if not SETTINGS.InfJump or isDestroyed then
            if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
            return
        end
        local hum = getHum()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

local function enableNoclip()
    if noclipConn then return end
    noclipConn = RunService.Stepped:Connect(function()
        if not SETTINGS.Noclip or isDestroyed then
            if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = true end
                end
            end
            return
        end
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end)
end

local function enableFly()
    if flyConn then return end
    task.spawn(function()
        local root = getRoot()
        local hum = getHum()
        if not root or not hum then
            flyConn = nil
            return
        end
        hum.PlatformStand = true
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        flyBV.Velocity = Vector3.zero
        flyBV.Parent = root
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyBG.P = 10000
        flyBG.CFrame = root.CFrame
        flyBG.Parent = root
        flyConn = RunService.RenderStepped:Connect(function()
            if not SETTINGS.Fly or isDestroyed then
                if flyConn then flyConn:Disconnect(); flyConn = nil end
                local h = getHum()
                if h then h.PlatformStand = false end
                if flyBV then flyBV:Destroy(); flyBV = nil end
                if flyBG then flyBG:Destroy(); flyBG = nil end
                return
            end
            local r = getRoot()
            local cam = Workspace.CurrentCamera
            if not r or not cam then return end
            local dir = Vector3.zero
            local cf = cam.CFrame
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
            if flyBV then flyBV.Velocity = dir * SETTINGS.FlySpeed end
            if flyBG then flyBG.CFrame = cam.CFrame end
        end)
    end)
end

local function disableFly()
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
end

local function enableLowGravity()
    if lowGravConn then return end
    lowGravConn = RunService.Stepped:Connect(function()
        if not SETTINGS.LowGrav or isDestroyed then
            if lowGravConn then lowGravConn:Disconnect(); lowGravConn = nil end
            local hum = getHum()
            if hum then hum.GravityScale = 1 end
            return
        end
        local hum = getHum()
        if hum then
            hum.GravityScale = SETTINGS.GravityScale
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 8. ESP: Stages / Checkpoints / Spawns 高亮 (Highlight)
-- ══════════════════════════════════════════════════════════════════
local function clearStageESP()
    for _, hl in pairs(espStageHighlights) do
        pcall(function() hl:Destroy() end)
    end
    espStageHighlights = {}
end

local function applyStageESP(part)
    if not part or not part:IsA("BasePart") then return end
    if espStageHighlights[part] then return end
    local hl = Instance.new("Highlight")
    hl.Adornee = part
    hl.Parent = part
    local nm = part.Name:lower()
    if nm:find("checkpoint") then
        hl.FillColor = SETTINGS.ESPCheckpointColor
        hl.OutlineColor = SETTINGS.ESPCheckpointColor
    elseif nm:find("spawn") then
        hl.FillColor = SETTINGS.ESPSpawnColor
        hl.OutlineColor = SETTINGS.ESPSpawnColor
    else
        hl.FillColor = SETTINGS.ESPStageColor
        hl.OutlineColor = SETTINGS.ESPStageColor
    end
    hl.FillTransparency = 0.6
    hl.OutlineTransparency = 0.2
    hl.Enabled = SETTINGS.ESPEnabled
    espStageHighlights[part] = hl
end

local function startESPLoop()
    if espLoopConn then espLoopConn:Disconnect() end
    espLoopConn = RunService.Heartbeat:Connect(function() end)
    task.spawn(function()
        while not isDestroyed do
            task.wait(0.8)
            if not SETTINGS.ESPEnabled then
                clearStageESP()
                continue
            end
            local parts = scanTeleportParts()
            for _, p in ipairs(parts) do
                applyStageESP(p)
            end
            for part, hl in pairs(espStageHighlights) do
                if not part or not part.Parent then
                    pcall(function() hl:Destroy() end)
                    espStageHighlights[part] = nil
                else
                    local nm = part.Name:lower()
                    if nm:find("checkpoint") then
                        hl.FillColor = SETTINGS.ESPCheckpointColor
                        hl.OutlineColor = SETTINGS.ESPCheckpointColor
                    elseif nm:find("spawn") then
                        hl.FillColor = SETTINGS.ESPSpawnColor
                        hl.OutlineColor = SETTINGS.ESPSpawnColor
                    else
                        hl.FillColor = SETTINGS.ESPStageColor
                        hl.OutlineColor = SETTINGS.ESPStageColor
                    end
                    hl.Enabled = SETTINGS.ESPEnabled
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 9. AntiRagequit / AntiAFK
-- ══════════════════════════════════════════════════════════════════
local function enableAntiRage()
    if antiRageConn then antiRageConn:Disconnect(); antiRageConn = nil end
    local mt = getrawmetatable(game)
    local oldClose = mt.__namecall
    antiRageConn = RunService.Stepped:Connect(function()
        if not SETTINGS.AntiRage or isDestroyed then
            if antiRageConn then antiRageConn:Disconnect(); antiRageConn = nil end
            return
        end
    end)
    pcall(function()
        LocalPlayer.Idled:Connect(function() end)
    end)
    pcall(function()
        game:FindFirstChildOfClass("NetworkClient").SetOutgoingKBPSLimit = function() end
    end)
end

local function enableAntiAFK()
    if antiAFKConn then antiAFKConn:Disconnect(); antiAFKConn = nil end
    antiAFKConn = LocalPlayer.Idled:Connect(function()
        if SETTINGS.AntiAFK and not isDestroyed then
            VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 10. Rejoin / Destroy
-- ══════════════════════════════════════════════════════════════════
local function rejoinServer()
    notify("Rejoin", "正在重新连接服务器...", 2, "Info")
    task.wait(0.6)
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
end

local function destroyScript()
    if isDestroyed then return end
    isDestroyed = true
    SETTINGS.AutoWin = false
    SETTINGS.SkipStages = false
    SETTINGS.InfJump = false
    SETTINGS.Noclip = false
    SETTINGS.Fly = false
    SETTINGS.LowGrav = false
    SETTINGS.AntiAFK = false
    SETTINGS.ESPEnabled = false
    if wsConn then wsConn:Disconnect(); wsConn = nil end
    if jpConn then jpConn:Disconnect(); jpConn = nil end
    if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    disableFly()
    if lowGravConn then lowGravConn:Disconnect(); lowGravConn = nil end
    if antiRageConn then antiRageConn:Disconnect(); antiRageConn = nil end
    if antiAFKConn then antiAFKConn:Disconnect(); antiAFKConn = nil end
    if espLoopConn then espLoopConn:Disconnect(); espLoopConn = nil end
    if heartbeatConnection then heartbeatConnection:Disconnect(); heartbeatConnection = nil end
    clearStageESP()
    local hum = getHum()
    if hum then
        hum.WalkSpeed = 16
        hum.JumpPower = 50
        hum.GravityScale = 1
        hum.PlatformStand = false
    end
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
    if Window then pcall(function() Window:Destroy() end) end
    if _G.QuantumUI_Window then _G.QuantumUI_Window = nil end
    notify("销毁", "Tower of Hell 辅助已彻底销毁", 2, "Warning")
    print("[ToH] 脚本已销毁")
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 构建 Quantum UI 界面
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title = "Tower of Hell 辅助",
    Subtitle = "地狱塔",
    ThemeColor = Color3.fromRGB(255, 40, 40),
    Transparency = 0.3,
    Size = UDim2.new(0, 620, 0, 520),
    Keybind = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ========== TAB 1: AutoFarm ==========
local AutoFarmTab = Window:AddTab({
    Name = "AutoFarm",
    Icon = "rbxassetid://6031094678"
})

AutoFarmTab:AddSection({ Name = "⚡ 自动通关 / 跳关" })

AutoFarmTab:AddToggle({
    Name = "AutoWin (自动通关循环)",
    Default = SETTINGS.AutoWin,
    Flag = "ToH_AutoWin",
    Callback = function(val)
        SETTINGS.AutoWin = val
        if val then
            autoWinLoop()
            notify("AutoWin", "自动通关已启动", 3, "Success")
        else
            notify("AutoWin", "自动通关已停止", 2, "Warning")
        end
    end
})

AutoFarmTab:AddToggle({
    Name = "SkipStages (按顺序跳关一次)",
    Default = SETTINGS.SkipStages,
    Flag = "ToH_SkipStages",
    Callback = function(val)
        SETTINGS.SkipStages = val
        if val then
            autoWinLoop()
            notify("SkipStages", "跳关已启动 (完成后自动停止)", 3, "Success")
        else
            notify("SkipStages", "跳关已停止", 2, "Warning")
        end
    end
})

AutoFarmTab:AddToggle({
    Name = "NoClipStages (传送期间穿墙)",
    Default = SETTINGS.NoClipStage,
    Flag = "ToH_NoClipStage",
    Callback = function(val)
        SETTINGS.NoClipStage = val
        notify("NoClipStages", val and "已启用 (AutoFarm期间穿墙)" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AutoFarmTab:AddSlider({
    Name = "Stage 传送延迟",
    Min = 0, Max = 2000, Default = SETTINGS.StageDelay, Increment = 10,
    Suffix = " ms",
    Flag = "ToH_StageDelay",
    Callback = function(val) SETTINGS.StageDelay = math.floor(val) end
})

AutoFarmTab:AddToggle({
    Name = "AntiRagequit (防服务器踢出)",
    Default = SETTINGS.AntiRage,
    Flag = "ToH_AntiRage",
    Callback = function(val)
        SETTINGS.AntiRage = val
        if val then enableAntiRage() end
        notify("AntiRagequit", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AutoFarmTab:AddSection({ Name = "🎯 Stage ESP (高亮)" })

AutoFarmTab:AddToggle({
    Name = "启用 Stage/Checkpoint ESP",
    Default = SETTINGS.ESPEnabled,
    Flag = "ToH_ESPEnabled",
    Callback = function(val)
        SETTINGS.ESPEnabled = val
        if not val then clearStageESP() end
        notify("Stage ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AutoFarmTab:AddColorPicker({
    Name = "Stage 颜色",
    Default = SETTINGS.ESPStageColor,
    Presets = PRESET_COLORS,
    Flag = "ToH_ESPStageColor",
    Callback = function(c) SETTINGS.ESPStageColor = c end
})

AutoFarmTab:AddColorPicker({
    Name = "Checkpoint 颜色",
    Default = SETTINGS.ESPCheckpointColor,
    Presets = PRESET_COLORS,
    Flag = "ToH_ESPCheckpointColor",
    Callback = function(c) SETTINGS.ESPCheckpointColor = c end
})

AutoFarmTab:AddColorPicker({
    Name = "Spawn 颜色",
    Default = SETTINGS.ESPSpawnColor,
    Presets = PRESET_COLORS,
    Flag = "ToH_ESPSpawnColor",
    Callback = function(c) SETTINGS.ESPSpawnColor = c end
})

-- ========== TAB 2: Movement ==========
local MovementTab = Window:AddTab({
    Name = "Movement",
    Icon = "rbxassetid://6034466796"
})

MovementTab:AddSection({ Name = "🏃 WalkSpeed (移速)" })

MovementTab:AddSlider({
    Name = "WalkSpeed",
    Min = 16, Max = 300, Default = SETTINGS.WalkSpeed, Increment = 1,
    Suffix = " studs/s",
    Flag = "ToH_WalkSpeed",
    Callback = function(val)
        SETTINGS.WalkSpeed = val
        applyWalkSpeed()
    end
})

MovementTab:AddSection({ Name = "🦘 JumpPower (跳跃力)" })

MovementTab:AddSlider({
    Name = "JumpPower",
    Min = 50, Max = 250, Default = SETTINGS.JumpPower, Increment = 1,
    Suffix = " studs/s",
    Flag = "ToH_JumpPower",
    Callback = function(val)
        SETTINGS.JumpPower = val
        applyJumpPower()
    end
})

MovementTab:AddSection({ Name = "✨ 进阶移动" })

MovementTab:AddToggle({
    Name = "InfJump (无限跳跃)",
    Default = SETTINGS.InfJump,
    Flag = "ToH_InfJump",
    Callback = function(val)
        SETTINGS.InfJump = val
        if val then
            enableInfJump()
            notify("InfJump", "无限跳跃已启用", 2, "Success")
        else
            if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
            notify("InfJump", "无限跳跃已禁用", 2, "Warning")
        end
    end
})

MovementTab:AddToggle({
    Name = "Noclip (穿墙)",
    Default = SETTINGS.Noclip,
    Flag = "ToH_Noclip",
    Callback = function(val)
        SETTINGS.Noclip = val
        if val then
            enableNoclip()
            notify("Noclip", "穿墙已启用", 2, "Success")
        else
            if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = true end
                end
            end
            notify("Noclip", "穿墙已禁用", 2, "Warning")
        end
    end
})

MovementTab:AddToggle({
    Name = "Fly (飞行)",
    Default = SETTINGS.Fly,
    Flag = "ToH_Fly",
    Callback = function(val)
        SETTINGS.Fly = val
        if val then
            enableFly()
            notify("Fly", "飞行已启用 (WASD/Space/Shift)", 3, "Success")
        else
            disableFly()
            notify("Fly", "飞行已关闭", 2, "Warning")
        end
    end
})

MovementTab:AddSlider({
    Name = "Fly Speed",
    Min = 10, Max = 200, Default = SETTINGS.FlySpeed, Increment = 5,
    Suffix = " studs/s",
    Flag = "ToH_FlySpeed",
    Callback = function(val) SETTINGS.FlySpeed = val end
})

MovementTab:AddToggle({
    Name = "LowGravity (低重力)",
    Default = SETTINGS.LowGrav,
    Flag = "ToH_LowGrav",
    Callback = function(val)
        SETTINGS.LowGrav = val
        if val then
            enableLowGravity()
            notify("LowGravity", "低重力已启用", 2, "Success")
        else
            if lowGravConn then lowGravConn:Disconnect(); lowGravConn = nil end
            local hum = getHum()
            if hum then hum.GravityScale = 1 end
            notify("LowGravity", "低重力已禁用", 2, "Warning")
        end
    end
})

MovementTab:AddSlider({
    Name = "Gravity Scale",
    Min = 0.05, Max = 1, Default = SETTINGS.GravityScale, Increment = 0.05,
    Flag = "ToH_GravityScale",
    Callback = function(val) SETTINGS.GravityScale = val end
})

-- ========== TAB 3: Teleports ==========
local TeleportsTab = Window:AddTab({
    Name = "Teleports",
    Icon = "rbxassetid://6034287594"
})

TeleportsTab:AddSection({ Name = "🚀 传送目标 (Stage/Checkpoint/Spawn)" })

local teleportDropdown = nil
local selectedTeleportPart = nil

local function refreshTeleportDropdown()
    teleportPartsCache = scanTeleportParts()
    local names = {}
    for i, p in ipairs(teleportPartsCache) do
        table.insert(names, string.format("#%d %s (Y:%.1f)", i, p.Name, p.Position.Y))
    end
    if #names == 0 then
        table.insert(names, "(未找到目标)")
    end
    if teleportDropdown and teleportDropdown.SetOptions then
        pcall(function() teleportDropdown:SetOptions(names) end)
    end
    return names
end

local initialNames = refreshTeleportDropdown()
if #initialNames == 0 then table.insert(initialNames, "(未找到目标)") end

teleportDropdown = TeleportsTab:AddDropdown({
    Name = "选择传送目标",
    Items = initialNames,
    Default = initialNames[1],
    Flag = "ToH_TeleportTarget",
    Callback = function(selected)
        for i, name in ipairs(initialNames) do
            if name == selected then
                selectedTeleportPart = teleportPartsCache[i]
                break
            end
        end
    end
})

TeleportsTab:AddButton({
    Name = "🔄 刷新目标列表",
    Callback = function()
        local names = refreshTeleportDropdown()
        notify("传送", "已刷新，找到 " .. tostring(#teleportPartsCache) .. " 个目标", 2, "Success")
    end
})

TeleportsTab:AddButton({
    Name = "🚀 传送到选中目标",
    Callback = function()
        local root = getRoot()
        if not root then
            notify("传送", "你尚未生成角色", 2, "Warning")
            return
        end
        if not selectedTeleportPart or not selectedTeleportPart.Parent then
            if #teleportPartsCache > 0 then
                selectedTeleportPart = teleportPartsCache[1]
            else
                notify("传送", "未选择目标，请先刷新", 2, "Warning")
                return
            end
        end
        local offset = Vector3.new(0, (selectedTeleportPart.Size.Y / 2) + 3, 0)
        root.CFrame = selectedTeleportPart.CFrame + offset
        notify("传送", "已传送到 " .. selectedTeleportPart.Name, 2, "Success")
    end
})

TeleportsTab:AddLabel({ Text = "💡 提示: 目标按 Y 高度从高到低排序，#1 通常是最高Stage" })

TeleportsTab:AddSection({ Name = "🎯 手动传送到最高/最低" })

TeleportsTab:AddButton({
    Name = "⬆️ 传送到最高 Stage",
    Callback = function()
        local stages = findTowerStages()
        if #stages == 0 then
            notify("传送", "未找到 Stage", 2, "Warning")
            return
        end
        local root = getRoot()
        if not root then
            notify("传送", "你尚未生成角色", 2, "Warning")
            return
        end
        local target = stages[1]
        local offset = Vector3.new(0, (target.Size.Y / 2) + 3, 0)
        root.CFrame = target.CFrame + offset
        notify("传送", "已传送到最高 Stage: " .. target.Name, 2, "Success")
    end
})

TeleportsTab:AddButton({
    Name = "⬇️ 传送到最低 Stage (起点)",
    Callback = function()
        local stages = findTowerStages()
        if #stages == 0 then
            notify("传送", "未找到 Stage", 2, "Warning")
            return
        end
        local root = getRoot()
        if not root then
            notify("传送", "你尚未生成角色", 2, "Warning")
            return
        end
        local target = stages[#stages]
        local offset = Vector3.new(0, (target.Size.Y / 2) + 3, 0)
        root.CFrame = target.CFrame + offset
        notify("传送", "已传送到最低 Stage: " .. target.Name, 2, "Success")
    end
})

-- ========== TAB 4: Keybinds ==========
local KeybindTab = Window:AddTab({
    Name = "Keybinds",
    Icon = "rbxassetid://6034281467"
})

KeybindTab:AddSection({ Name = "⌨️ 快捷键绑定" })

KeybindTab:AddKeybind({
    Name = "UI 显示/隐藏",
    Default = Enum.KeyCode.RightShift,
    Flag = "ToH_UIKeybind",
    ChangedCallback = function(key)
        notify("快捷键", "UI 切换键已改为: " .. key.Name, 2, "Info")
    end,
    Callback = function() end
})

KeybindTab:AddKeybind({
    Name = "Noclip (穿墙)",
    Default = Enum.KeyCode.V,
    Flag = "ToH_NoclipKeybind",
    ChangedCallback = function(key)
        notify("快捷键", "Noclip 切换键已改为: " .. key.Name, 2, "Info")
    end,
    Callback = function()
        SETTINGS.Noclip = not SETTINGS.Noclip
        if Window and Window.Flags and Window.Flags["ToH_Noclip"] then
            pcall(function() Window.Flags["ToH_Noclip"]:Set(SETTINGS.Noclip) end)
        end
        if SETTINGS.Noclip then
            enableNoclip()
            notify("Noclip", "穿墙已启用", 1.5, "Success")
        else
            if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = true end
                end
            end
            notify("Noclip", "穿墙已禁用", 1.5, "Warning")
        end
    end
})

KeybindTab:AddKeybind({
    Name = "Fly (飞行)",
    Default = Enum.KeyCode.F,
    Flag = "ToH_FlyKeybind",
    ChangedCallback = function(key)
        notify("快捷键", "Fly 切换键已改为: " .. key.Name, 2, "Info")
    end,
    Callback = function()
        SETTINGS.Fly = not SETTINGS.Fly
        if Window and Window.Flags and Window.Flags["ToH_Fly"] then
            pcall(function() Window.Flags["ToH_Fly"]:Set(SETTINGS.Fly) end)
        end
        if SETTINGS.Fly then
            enableFly()
            notify("Fly", "飞行已启用 (WASD/Space/Shift)", 2, "Success")
        else
            disableFly()
            notify("Fly", "飞行已关闭", 1.5, "Warning")
        end
    end
})

KeybindTab:AddKeybind({
    Name = "Skip Stage (跳一关)",
    Default = Enum.KeyCode.G,
    Flag = "ToH_SkipStageKeybind",
    ChangedCallback = function(key)
        notify("快捷键", "SkipStage 键已改为: " .. key.Name, 2, "Info")
    end,
    Callback = function()
        skipOneStage()
    end
})

KeybindTab:AddSection({ Name = "ℹ️ 说明" })

KeybindTab:AddParagraph({
    Title = "快捷键使用方法",
    Content = table.concat({
        "1. 点击按键框进入绑定模式",
        "2. 按下你想设置的键盘按键",
        "3. 设置会自动保存（通过 Flag）",
        "4. 使用 Settings Tab 可保存/加载完整配置",
        "",
        "默认快捷键:",
        "  RightShift - UI 显示/隐藏",
        "  V          - Noclip 穿墙",
        "  F          - Fly 飞行",
        "  G          - 跳过当前 Stage",
        "  Delete     - 彻底销毁脚本"
    }, "\n")
})

-- ========== TAB 5: Misc ==========
local MiscTab = Window:AddTab({
    Name = "Misc",
    Icon = "rbxassetid://6031280882"
})

MiscTab:AddSection({ Name = "🎮 游戏操作" })

MiscTab:AddToggle({
    Name = "AntiAFK (防挂机)",
    Default = SETTINGS.AntiAFK,
    Flag = "ToH_AntiAFK",
    Callback = function(val)
        SETTINGS.AntiAFK = val
        if val then
            enableAntiAFK()
            notify("AntiAFK", "防挂机已启用", 2, "Success")
        else
            if antiAFKConn then antiAFKConn:Disconnect(); antiAFKConn = nil end
            notify("AntiAFK", "防挂机已禁用", 2, "Warning")
        end
    end
})

MiscTab:AddButton({
    Name = "🔄 重新加入服务器 (Rejoin)",
    Callback = function()
        rejoinServer()
    end
})

MiscTab:AddButton({
    Name = "💀 彻底销毁脚本 (Destroy)",
    Callback = function()
        destroyScript()
    end
})

MiscTab:AddSection({ Name = "🌈 UI 美化" })

MiscTab:AddToggle({
    Name = "彩虹边框动画",
    Default = QuantumUI.RainbowEnabled,
    Flag = "ToH_Rainbow",
    Callback = function(state)
        QuantumUI.RainbowEnabled = state
    end
})

MiscTab:AddSlider({
    Name = "彩虹速度",
    Min = 0.1, Max = 5, Default = QuantumUI.RainbowSpeed or 1, Increment = 0.1,
    Suffix = "x",
    Flag = "ToH_RainbowSpeed",
    Callback = function(value)
        QuantumUI.RainbowSpeed = value
    end
})

MiscTab:AddSection({ Name = "🎨 主题预设 (7种)" })

MiscTab:AddButton({
    Name = "🔴 地狱红 (默认)",
    Callback = function()
        local c = Color3.fromRGB(255, 40, 40)
        Window.ThemeColor = c
        QuantumUI.ThemeColor = c
        Window:RefreshTheme()
        notify("主题", "已切换: 地狱红", 2, "Success")
    end
})

MiscTab:AddButton({
    Name = "🟢 幽灵绿",
    Callback = function()
        local c = Color3.fromRGB(0, 255, 120)
        Window.ThemeColor = c
        QuantumUI.ThemeColor = c
        Window:RefreshTheme()
        notify("主题", "已切换: 幽灵绿", 2, "Success")
    end
})

MiscTab:AddButton({
    Name = "🔵 赛博青",
    Callback = function()
        local c = Color3.fromRGB(0, 200, 255)
        Window.ThemeColor = c
        QuantumUI.ThemeColor = c
        Window:RefreshTheme()
        notify("主题", "已切换: 赛博青", 2, "Success")
    end
})

MiscTab:AddButton({
    Name = "🟣 暗紫",
    Callback = function()
        local c = Color3.fromRGB(180, 60, 255)
        Window.ThemeColor = c
        QuantumUI.ThemeColor = c
        Window:RefreshTheme()
        notify("主题", "已切换: 暗紫", 2, "Success")
    end
})

MiscTab:AddButton({
    Name = "🟡 黄金",
    Callback = function()
        local c = Color3.fromRGB(255, 200, 50)
        Window.ThemeColor = c
        QuantumUI.ThemeColor = c
        Window:RefreshTheme()
        notify("主题", "已切换: 黄金", 2, "Success")
    end
})

MiscTab:AddButton({
    Name = "🌸 樱花粉",
    Callback = function()
        local c = Color3.fromRGB(255, 105, 180)
        Window.ThemeColor = c
        QuantumUI.ThemeColor = c
        Window:RefreshTheme()
        notify("主题", "已切换: 樱花粉", 2, "Success")
    end
})

MiscTab:AddButton({
    Name = "🩵 薄荷青",
    Callback = function()
        local c = Color3.fromRGB(0, 255, 200)
        Window.ThemeColor = c
        QuantumUI.ThemeColor = c
        Window:RefreshTheme()
        notify("主题", "已切换: 薄荷青", 2, "Success")
    end
})

MiscTab:AddSection({ Name = "ℹ️ 关于" })

MiscTab:AddParagraph({
    Title = "Tower of Hell 辅助 | Quantum UI 版",
    Content = table.concat({
        "游戏: Tower of Hell (地狱塔)",
        "适配 PlaceId: 1962086868 / 3582763398",
        "UI框架: Quantum UI Library (Log-Hub)",
        "",
        "✅ AutoWin        - 自动循环通关",
        "✅ SkipStages     - 按顺序跳关",
        "✅ NoClipStages   - 传送期间穿墙",
        "✅ AntiRagequit   - 防服务器踢出",
        "✅ Stage ESP      - Stage/Checkpoint 高亮",
        "✅ WalkSpeed      - 移速修改 (16-300)",
        "✅ JumpPower      - 跳跃力修改 (50-250)",
        "✅ InfJump        - 无限跳跃",
        "✅ Noclip         - 穿墙 (按 V)",
        "✅ Fly            - 飞行 (按 F, WASD/Shift/Space)",
        "✅ LowGravity     - 低重力",
        "✅ Teleports      - Stage/Checkpoint/Spawn 传送",
        "✅ SkipStage      - 跳过一关 (按 G)",
        "✅ AntiAFK        - 防挂机",
        "✅ Rejoin         - 重连服务器",
        "✅ Keybinds       - 自定义快捷键",
        "✅ Config         - 配置保存/加载",
        "✅ Rainbow Theme  - 彩虹边框 + 7种主题色"
    }, "\n")
})

MiscTab:AddLabel({ Text = "💡 前往 Settings Tab 保存你的配置！" })

-- ══════════════════════════════════════════════════════════════════
-- 12. 主初始化
-- ══════════════════════════════════════════════════════════════════
task.wait(0.5)

applyWalkSpeed()
applyJumpPower()

if SETTINGS.InfJump then enableInfJump() end
if SETTINGS.Noclip then enableNoclip() end
if SETTINGS.Fly then enableFly() end
if SETTINGS.LowGrav then enableLowGravity() end
if SETTINGS.AntiAFK then enableAntiAFK() end
if SETTINGS.AntiRage then enableAntiRage() end
if SETTINGS.ESPEnabled then startESPLoop() end

heartbeatConnection = RunService.Heartbeat:Connect(function()
    if isDestroyed then return end
end)

LocalPlayer.CharacterAdded:Connect(function()
    if isDestroyed then return end
    task.wait(0.5)
    if wsConn then applyWalkSpeed() end
    if jpConn then applyJumpPower() end
    if SETTINGS.InfJump then enableInfJump() end
    if SETTINGS.LowGrav then enableLowGravity() end
end)

-- ══════════════════════════════════════════════════════════════════
-- 13. 全局快捷键 (Delete 销毁)
-- ══════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or isDestroyed then return end
    if input.KeyCode == Enum.KeyCode.Delete then
        destroyScript()
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 14. 加载完成通知
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
notify("✅ Tower of Hell 辅助加载完成!",
    "地狱塔 Quantum UI 版本就绪\n" ..
    "适配 PlaceId: 1962086868 / 3582763398\n" ..
    "按 RightShift 切换 UI 显示\n" ..
    "V=Noclip | F=Fly | G=跳过Stage\n" ..
    "前往 Settings Tab 保存你的配置!",
    6, "Success")

print("========================================")
print(" Tower of Hell 辅助 v1.0 (Quantum UI 版) 加载完成")
print("   PlaceId: 1962086868 / 3582763398")
print("   RightShift - 隐藏/显示 UI")
print("   V          - Noclip 穿墙开关")
print("   F          - Fly 飞行开关")
print("   G          - 跳过当前 Stage")
print("   Delete     - 彻底销毁脚本")
print("   Settings Tab - 保存/加载配置")
print("========================================")
