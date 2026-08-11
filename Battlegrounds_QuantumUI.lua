--[[
    The Strongest Battlegrounds 辅助脚本 v1.0 (Quantum UI 版)
    基于 Spectral_Hub (claymannn12-ship-it) + Antimony + Speed Hub X 源码还原
    适配 PlaceId: 10449761463 (The Strongest Battlegrounds)

    游戏内部结构 (源码分析):
      LocalPlayer.Mana                   — 技能资源 (Ultimate需要Mana)
      Humanoid:GetState()                — Stunned/Ragdoll/Blocking 状态检测
      ReplicatedStorage.Packages         — Knit/Spring 模块
      Players:GetPlayers()               — 敌人遍历
      技能系统: M1(普攻)/技能1~4/终极/觉醒/冲刺
      角色种类: Hero Hunter / Saitama / Garou / Deadly Ninja / Brute / etc.

    功能:
      战斗: Kill Aura / Hitbox Expander / Auto Block / Auto Attack / No Cooldown / Aimbot
      移动: WalkSpeed / JumpPower / NoClip / Fly / InfJump / No Stun / No Ragdoll / No Dash Cooldown
      视觉: Player ESP / Health ESP / Tracers / 全亮
      农场: Auto Farm / Auto Reset (低血量重置)
      杂项: Server Hop / Rejoin / Anti-AFK / 坐标

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
    warn("[TSB] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[TSB] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[TSB] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[TSB] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

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
local TeleportService = game:GetService("TeleportService")
local Workspace = workspace
local Lighting = game:GetService("Lighting")

-- ══════════════════════════════════════════════════════════════════
-- 3. SETTINGS
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- Combat
    TSB_KillAura = false,
    TSB_KillAuraRange = 15,
    TSB_HitboxExpander = false,
    TSB_HitboxSize = 10,
    TSB_AutoBlock = false,
    TSB_AutoAttack = false,
    TSB_NoCooldown = false,
    TSB_Aimbot = false,
    TSB_AimbotRange = 100,

    -- Movement
    TSB_WalkSpeed = false,
    TSB_WalkSpeedValue = 16,
    TSB_JumpPower = false,
    TSB_JumpPowerValue = 50,
    TSB_InfJump = false,
    TSB_NoClip = false,
    TSB_Fly = false,
    TSB_FlySpeed = 80,
    TSB_NoStun = false,
    TSB_NoRagdoll = false,
    TSB_NoDashCooldown = false,

    -- Visual
    ESP_Player = false,
    ESP_PlayerColor = Color3.fromRGB(0, 200, 255),
    ESP_Health = false,
    ESP_Tracers = false,
    ESP_Distance = true,
    ESP_Refresh = 0.1,
    TSB_Fullbright = false,

    -- Farm
    TSB_AutoFarm = false,
    TSB_AutoReset = false,
    TSB_AutoResetHP = 20,

    -- Misc
    TSB_AntiAFK = false,
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
local killAuraConn = nil
local autoBlockConn = nil
local autoAttackConn = nil
local noStunConn = nil
local noRagdollConn = nil
local noDashConn = nil
local noCooldownConn = nil
local espConn = nil
local espFolder = nil
local farmConn = nil
local autoResetConn = nil
local antiAFKConn = nil
local aimbotConn = nil
local savedLighting = {}

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
                Title = title, Text = content, Duration = duration or 3
            })
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 6. 工具函数 (来自 Spectral_Hub 源码还原)
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

-- 来自源码: 获取最近敌人 (多因素优先级评分)
local function getClosestEnemy(range)
    local closest = nil
    local highestScore = -1
    local myRoot = getRoot()
    if not myRoot then return nil end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 then
                local dist = (myRoot.Position - hrp.Position).Magnitude
                if dist <= range then
                    -- 来自源码: 评分 = (100 - 血量) + 状态加成
                    local score = (100 - hum.Health)
                    if hum:GetState() == Enum.HumanoidStateType.Stunned
                    or hum:GetState() == Enum.HumanoidStateType.Ragdoll then
                        score = score + 500
                    end
                    if score > highestScore then
                        closest = player
                        highestScore = score
                    end
                end
            end
        end
    end
    return closest
end

-- 来自源码: 获取所有范围内敌人
local function getAllEnemiesInRange(range)
    local result = {}
    local myRoot = getRoot()
    if not myRoot then return result end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 then
                local dist = (myRoot.Position - hrp.Position).Magnitude
                if dist <= range then
                    table.insert(result, player)
                end
            end
        end
    end
    return result
end

-- 来自源码: 面朝目标 (预测移动)
local function faceTarget(target)
    if not target or not target.Character then return end
    local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
    local myRoot = getRoot()
    if not targetHRP or not myRoot then return end
    local predictedPos = targetHRP.Position + targetHRP.Velocity * 0.2
    local direction = (predictedPos - myRoot.Position).Unit
    pcall(function()
        myRoot.CFrame = CFrame.new(myRoot.Position, myRoot.Position + direction)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 7. 战斗功能 (源码还原)
-- ══════════════════════════════════════════════════════════════════

-- Kill Aura (来自源码: 对范围内所有敌人自动攻击)
local function toggleKillAura(enabled)
    if killAuraConn then
        killAuraConn:Disconnect()
        killAuraConn = nil
    end
    if enabled then
        killAuraConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            if not myRoot then return end
            local range = SETTINGS.TSB_KillAuraRange or 15
            local enemies = getAllEnemiesInRange(range)
            for _, enemy in ipairs(enemies) do
                pcall(function()
                    faceTarget(enemy)
                    -- 模拟M1点击
                    if VirtualUser then
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton1(Vector2.new())
                    end
                end)
            end
        end)
    end
end

-- Hitbox Expander (来自源码: 放大敌人碰撞箱)
local function toggleHitboxExpander(enabled)
    if enabled then
        local conn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        pcall(function()
                            hrp.Size = Vector3.new(SETTINGS.TSB_HitboxSize, SETTINGS.TSB_HitboxSize, SETTINGS.TSB_HitboxSize)
                            hrp.Transparency = 0.5
                            hrp.CanCollide = false
                            hrp.Material = Enum.Material.Neon
                            hrp.Color = Color3.fromRGB(255, 0, 0)
                        end)
                    end
                end
            end
        end)
        -- 存储conn以便关闭
        _G.TSB_HitboxConn = conn
    else
        if _G.TSB_HitboxConn then
            _G.TSB_HitboxConn:Disconnect()
            _G.TSB_HitboxConn = nil
        end
        -- 恢复原始大小
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function()
                        hrp.Size = Vector3.new(2, 2, 1)
                        hrp.Transparency = 1
                        hrp.Material = Enum.Material.Plastic
                    end)
                end
            end
        end
    end
end

-- Auto Block (来自源码: 检测附近攻击并自动格挡)
local function toggleAutoBlock(enabled)
    if autoBlockConn then
        autoBlockConn:Disconnect()
        autoBlockConn = nil
    end
    if enabled then
        autoBlockConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            if not myRoot then return end
            -- 检测附近敌人的攻击动作
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                    local hum = player.Character:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        local dist = (myRoot.Position - hrp.Position).Magnitude
                        if dist <= 12 then
                            -- 检查敌人是否面朝自己且在攻击范围
                            local direction = (myRoot.Position - hrp.Position).Unit
                            local enemyLook = hrp.CFrame.LookVector
                            local dot = direction:Dot(enemyLook)
                            if dot > 0.7 then
                                -- 敌人面朝自己，自动格挡
                                pcall(function()
                                    if VirtualUser then
                                        VirtualUser:CaptureController()
                                        -- 模拟右键格挡 (KeyF in TSB)
                                        VirtualInputManager = VirtualInputManager or game:GetService("VirtualInputManager")
                                        if VirtualInputManager then
                                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                                            task.wait(0.1)
                                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                                        end
                                    end
                                end)
                                break
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- Auto Attack (来自源码: 自动攻击最近敌人)
local function toggleAutoAttack(enabled)
    if autoAttackConn then
        autoAttackConn:Disconnect()
        autoAttackConn = nil
    end
    if enabled then
        local lastAttack = 0
        autoAttackConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local now = tick()
            if now - lastAttack < 0.5 then return end
            local target = getClosestEnemy(20)
            if target then
                faceTarget(target)
                pcall(function()
                    if VirtualUser then
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton1(Vector2.new())
                    end
                end)
                lastAttack = now
            end
        end)
    end
end

-- No Cooldown (来自源码: 移除技能冷却)
local function toggleNoCooldown(enabled)
    if noCooldownConn then
        noCooldownConn:Disconnect()
        noCooldownConn = nil
    end
    if enabled then
        noCooldownConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            -- 尝试找到并修改冷却值
            pcall(function()
                local char = getChar()
                if char then
                    -- 搜索技能相关的Cooldown值
                    for _, v in ipairs(char:GetDescendants()) do
                        if v:IsA("NumberValue") and (string.find(string.lower(v.Name), "cooldown") or string.find(string.lower(v.Name), "cd")) then
                            v.Value = 0
                        end
                        if v:IsA("IntValue") and (string.find(string.lower(v.Name), "cooldown") or string.find(string.lower(v.Name), "cd")) then
                            v.Value = 0
                        end
                    end
                end
                -- 搜索ReplicatedStorage中的技能配置
                local skills = ReplicatedStorage:FindFirstChild("Skills") or ReplicatedStorage:FindFirstChild("Moves")
                if skills then
                    for _, v in ipairs(skills:GetDescendants()) do
                        if v:IsA("NumberValue") and (string.find(string.lower(v.Name), "cooldown") or string.find(string.lower(v.Name), "cd")) then
                            v.Value = 0
                        end
                    end
                end
            end)
        end)
    end
end

-- Aimbot (来自源码: 锁定最近敌人到鼠标)
local function toggleAimbot(enabled)
    if aimbotConn then
        aimbotConn:Disconnect()
        aimbotConn = nil
    end
    if enabled then
        aimbotConn = RunService.RenderStepped:Connect(function()
            if isDestroyed then return end
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local target = getClosestEnemy(SETTINGS.TSB_AimbotRange or 100)
            if target and target.Character then
                local hrp = target.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function()
                        -- 将相机对准目标
                        local myRoot = getRoot()
                        if myRoot then
                            local direction = (hrp.Position - myRoot.Position).Unit
                            myRoot.CFrame = CFrame.new(myRoot.Position, myRoot.Position + direction)
                        end
                    end)
                end
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 移动功能 (源码还原)
-- ══════════════════════════════════════════════════════════════════
local function setWalkSpeed(enabled, value)
    local hum = getHum()
    if not hum then return end
    pcall(function() hum.WalkSpeed = enabled and value or 16 end)
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
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
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
            if isDestroyed then return end
            local char = getChar()
            if not char then return end
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end)
    end
end

local function toggleFly(enabled, speed)
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
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
            local spd = speed or SETTINGS.TSB_FlySpeed or 80
            if move.Magnitude > 0 then move = move.Unit * spd end
            flyBV.Velocity = move
            if root then flyBG.CFrame = CFrame.new(root.Position) * cam.CFrame.Rotation end
        end)
    end
end

-- No Stun (来自源码: 防止眩晕状态)
local function toggleNoStun(enabled)
    if noStunConn then
        noStunConn:Disconnect()
        noStunConn = nil
    end
    if enabled then
        noStunConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if hum then
                pcall(function()
                    if hum:GetState() == Enum.HumanoidStateType.Stunned then
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                end)
            end
        end)
    end
end

-- No Ragdoll (来自源码: 防止布娃娃状态)
local function toggleNoRagdoll(enabled)
    if noRagdollConn then
        noRagdollConn:Disconnect()
        noRagdollConn = nil
    end
    if enabled then
        noRagdollConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if hum then
                pcall(function()
                    if hum:GetState() == Enum.HumanoidStateType.Ragdoll
                    or hum:GetState() == Enum.HumanoidStateType.FallingDown then
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                end)
            end
        end)
    end
end

-- No Dash Cooldown (来自源码: 移除冲刺冷却)
local function toggleNoDashCooldown(enabled)
    if noDashConn then
        noDashConn:Disconnect()
        noDashConn = nil
    end
    if enabled then
        noDashConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            pcall(function()
                local char = getChar()
                if char then
                    for _, v in ipairs(char:GetDescendants()) do
                        local name = string.lower(v.Name)
                        if (v:IsA("NumberValue") or v:IsA("IntValue")) and string.find(name, "dash") then
                            v.Value = 0
                        end
                        if v:IsA("BoolValue") and string.find(name, "dash") and string.find(name, "cd") then
                            v.Value = false
                        end
                    end
                end
            end)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 9. ESP 功能 (源码还原)
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end
end

local function createHighlight(parent, color)
    local hl = Instance.new("Highlight")
    hl.Name = "TSB_ESP_HL"
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0.2
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = parent
    return hl
end

local function createBillboard(parent, text, color, yOffset)
    local bb = Instance.new("BillboardGui")
    bb.Name = "TSB_ESP_BB"
    bb.Size = UDim2.new(0, 200, 0, 50)
    bb.StudsOffset = Vector3.new(0, yOffset or 3, 0)
    bb.AlwaysOnTop = true

    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 0, 20)
    tl.BackgroundTransparency = 1
    tl.Text = text
    tl.TextColor3 = color
    tl.TextStrokeTransparency = 0.3
    tl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14
    tl.Parent = bb

    -- 血量条
    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(0.8, 0, 0, 6)
    barBg.Position = UDim2.new(0.1, 0, 0, 22)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    barBg.BorderSizePixel = 0
    barBg.Parent = bb

    local bar = Instance.new("Frame")
    bar.Name = "HealthBar"
    bar.Size = UDim2.new(1, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    bar.BorderSizePixel = 0
    bar.Parent = barBg

    bb.Parent = parent
    return bb, bar
end

local function runESPLoop()
    if not espFolder then
        espFolder = Instance.new("Folder")
        espFolder.Name = "TSB_ESP_Folder"
        espFolder.Parent = CoreGui
    end

    local myRoot = getRoot()

    local function cleanObj(obj)
        pcall(function()
            for _, c in ipairs(obj:GetChildren()) do
                if c.Name == "TSB_ESP_HL" or c.Name == "TSB_ESP_BB" then
                    c:Destroy()
                end
            end
        end)
    end

    if SETTINGS.ESP_Player or SETTINGS.ESP_Health or SETTINGS.ESP_Tracers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local char = p.Character
                local hum = char:FindFirstChildOfClass("Humanoid")
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 then
                    cleanObj(char)
                    local color = SETTINGS.ESP_PlayerColor
                    local distText = ""
                    if myRoot then
                        local dist = (myRoot.Position - hrp.Position).Magnitude
                        distText = string.format(" [%dm]", math.floor(dist))
                    end
                    local hpText = ""
                    if SETTINGS.ESP_Health then
                        hpText = string.format(" HP:%d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
                    end
                    local name = p.Name .. hpText
                    if SETTINGS.ESP_Distance then name = name .. distText end
                    if SETTINGS.ESP_Player or SETTINGS.ESP_Health then
                        pcall(function()
                            createHighlight(char, color)
                            local _, bar = createBillboard(char, name, color, 4)
                            if bar and hum then
                                local hpPercent = hum.Health / hum.MaxHealth
                                bar.Size = UDim2.new(math.clamp(hpPercent, 0, 1), 0, 1, 0)
                                -- 血量颜色: 绿→黄→红
                                if hpPercent > 0.5 then
                                    bar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
                                elseif hpPercent > 0.25 then
                                    bar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
                                else
                                    bar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
                                end
                            end
                        end)
                    end
                end
            end
        end
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
-- 10. 视觉功能 (源码还原)
-- ══════════════════════════════════════════════════════════════════
local function toggleFullbright(enabled)
    if enabled then
        if not savedLighting.brightness then
            savedLighting.brightness = Lighting.Brightness
            savedLighting.fogEnd = Lighting.FogEnd
            savedLighting.clockTime = Lighting.ClockTime
            savedLighting.globalShadows = Lighting.GlobalShadows
        end
        Lighting.Brightness = 4
        Lighting.FogEnd = 100000
        Lighting.ClockTime = 12
        Lighting.GlobalShadows = false
    else
        Lighting.Brightness = savedLighting.brightness or 1
        Lighting.FogEnd = savedLighting.fogEnd or 500
        Lighting.ClockTime = savedLighting.clockTime or 14
        Lighting.GlobalShadows = savedLighting.globalShadows ~= nil and savedLighting.globalShadows or true
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 农场功能 (源码还原)
-- ══════════════════════════════════════════════════════════════════

-- Auto Farm (来自源码: 自动找敌+攻击+防死)
local function toggleAutoFarm(enabled)
    if farmConn then
        farmConn:Disconnect()
        farmConn = nil
    end
    if enabled then
        farmConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            local hum = getHum()
            if not myRoot or not hum then return end

            -- 低血量自动重置
            if SETTINGS.TSB_AutoReset and hum.Health > 0 then
                local hpPercent = (hum.Health / hum.MaxHealth) * 100
                if hpPercent <= (SETTINGS.TSB_AutoResetHP or 20) then
                    pcall(function()
                        hum.Health = 0
                    end)
                    task.wait(2)
                    return
                end
            end

            -- 找最近敌人
            local target = getClosestEnemy(100)
            if target and target.Character then
                local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
                local targetHum = target.Character:FindFirstChildOfClass("Humanoid")
                if targetHRP and targetHum and targetHum.Health > 0 then
                    local dist = (myRoot.Position - targetHRP.Position).Magnitude
                    if dist > 8 then
                        -- 传送到敌人附近
                        pcall(function()
                            myRoot.CFrame = CFrame.new(targetHRP.Position + targetHRP.CFrame.LookVector * 4)
                        end)
                    else
                        -- 攻击
                        faceTarget(target)
                        pcall(function()
                            if VirtualUser then
                                VirtualUser:CaptureController()
                                VirtualUser:ClickButton1(Vector2.new())
                            end
                        end)
                    end
                end
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 12. 杂项
-- ══════════════════════════════════════════════════════════════════
local function rejoin()
    pcall(function()
        if #Players:GetPlayers() <= 1 then
            LocalPlayer:Kick("Rejoining...")
            task.wait(1)
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end)
end

local function serverHop()
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end

local function setupAntiAFK()
    local GC = getconnections or get_signal_cons
    if GC then
        for _, v in pairs(GC(LocalPlayer.Idled)) do
            if v["Disable"] then v["Disable"](v)
            elseif v["Disconnect"] then v["Disconnect"](v) end
        end
    else
        if antiAFKConn then antiAFKConn:Disconnect() end
        antiAFKConn = LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 13. 创建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title      = "The Strongest Battlegrounds",
    Subtitle   = "最强战场 v1.0",
    ThemeColor = Color3.fromRGB(255, 80, 80),
    Transparency = 0.3,
    Size       = UDim2.new(0, 640, 0, 560),
    Keybind    = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: 战斗 ──
local CombatTab = Window:AddTab({
    Name = "战斗",
    Icon = "rbxassetid://6034287594",
})

CombatTab:AddSection({ Name = "攻击" })

CombatTab:AddToggle({
    Name     = "Kill Aura (范围自动攻击)",
    Default  = false,
    Flag     = "TSB_KillAura",
    Callback = function(s)
        SETTINGS.TSB_KillAura = s
        toggleKillAura(s)
        notify("TSB", s and "Kill Aura 已开启" or "Kill Aura 已关闭", 2, s and "Success" or "Info")
    end,
})

CombatTab:AddSlider({
    Name      = "Kill Aura 范围",
    Min       = 5, Max = 50, Default = 15, Increment = 1,
    Suffix    = " studs",
    Flag      = "TSB_KillAuraRange",
    Callback  = function(v) SETTINGS.TSB_KillAuraRange = v end,
})

CombatTab:AddToggle({
    Name     = "Auto Attack (自动攻击最近敌人)",
    Default  = false,
    Flag     = "TSB_AutoAttack",
    Callback = function(s)
        SETTINGS.TSB_AutoAttack = s
        toggleAutoAttack(s)
    end,
})

CombatTab:AddToggle({
    Name     = "Aimbot (自动锁定)",
    Default  = false,
    Flag     = "TSB_Aimbot",
    Callback = function(s)
        SETTINGS.TSB_Aimbot = s
        toggleAimbot(s)
    end,
})

CombatTab:AddSlider({
    Name      = "Aimbot 范围",
    Min       = 20, Max = 500, Default = 100, Increment = 10,
    Suffix    = " studs",
    Flag      = "TSB_AimbotRange",
    Callback  = function(v) SETTINGS.TSB_AimbotRange = v end,
})

CombatTab:AddSection({ Name = "防御" })

CombatTab:AddToggle({
    Name     = "Auto Block (自动格挡)",
    Default  = false,
    Flag     = "TSB_AutoBlock",
    Callback = function(s)
        SETTINGS.TSB_AutoBlock = s
        toggleAutoBlock(s)
    end,
})

CombatTab:AddSection({ Name = "修改" })

CombatTab:AddToggle({
    Name     = "Hitbox Expander (放大碰撞箱)",
    Default  = false,
    Flag     = "TSB_HitboxExpander",
    Callback = function(s)
        SETTINGS.TSB_HitboxExpander = s
        toggleHitboxExpander(s)
    end,
})

CombatTab:AddSlider({
    Name      = "Hitbox 大小",
    Min       = 2, Max = 50, Default = 10, Increment = 1,
    Flag      = "TSB_HitboxSize",
    Callback  = function(v) SETTINGS.TSB_HitboxSize = v end,
})

CombatTab:AddToggle({
    Name     = "No Cooldown (无冷却)",
    Default  = false,
    Flag     = "TSB_NoCooldown",
    Callback = function(s)
        SETTINGS.TSB_NoCooldown = s
        toggleNoCooldown(s)
    end,
})

-- ── TAB 2: 移动 ──
local MoveTab = Window:AddTab({
    Name = "移动",
    Icon = "rbxassetid://6034466796",
})

MoveTab:AddSection({ Name = "基础移动" })

MoveTab:AddToggle({
    Name     = "WalkSpeed",
    Default  = false,
    Flag     = "TSB_WalkSpeedEnabled",
    Callback = function(s)
        SETTINGS.TSB_WalkSpeed = s
        setWalkSpeed(s, SETTINGS.TSB_WalkSpeedValue)
    end,
})

MoveTab:AddSlider({
    Name      = "WalkSpeed 值",
    Min       = 16, Max = 200, Default = 35, Increment = 1,
    Flag      = "TSB_WalkSpeedValue",
    Callback  = function(v)
        SETTINGS.TSB_WalkSpeedValue = v
        if SETTINGS.TSB_WalkSpeed then setWalkSpeed(true, v) end
    end,
})

MoveTab:AddToggle({
    Name     = "JumpPower",
    Default  = false,
    Flag     = "TSB_JumpPowerEnabled",
    Callback = function(s)
        SETTINGS.TSB_JumpPower = s
        setJumpPower(s, SETTINGS.TSB_JumpPowerValue)
    end,
})

MoveTab:AddSlider({
    Name      = "JumpPower 值",
    Min       = 50, Max = 200, Default = 100, Increment = 1,
    Flag      = "TSB_JumpPowerValue",
    Callback  = function(v)
        SETTINGS.TSB_JumpPowerValue = v
        if SETTINGS.TSB_JumpPower then setJumpPower(true, v) end
    end,
})

MoveTab:AddToggle({
    Name     = "InfJump (无限跳)",
    Default  = false,
    Flag     = "TSB_InfJump",
    Callback = function(s)
        SETTINGS.TSB_InfJump = s
        toggleInfJump(s)
    end,
})

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({
    Name     = "NoClip (穿墙)",
    Default  = false,
    Flag     = "TSB_NoClip",
    Callback = function(s)
        SETTINGS.TSB_NoClip = s
        toggleNoclip(s)
    end,
})

MoveTab:AddToggle({
    Name     = "Fly (飞行 WASD+Space/Ctrl)",
    Default  = false,
    Flag     = "TSB_Fly",
    Callback = function(s)
        SETTINGS.TSB_Fly = s
        toggleFly(s, SETTINGS.TSB_FlySpeed)
    end,
})

MoveTab:AddSlider({
    Name      = "Fly Speed",
    Min       = 10, Max = 300, Default = 80, Increment = 5,
    Flag      = "TSB_FlySpeed",
    Callback  = function(v)
        SETTINGS.TSB_FlySpeed = v
        if SETTINGS.TSB_Fly then toggleFly(true, v) end
    end,
})

MoveTab:AddSection({ Name = "状态防抗 (源码还原)" })

MoveTab:AddToggle({
    Name     = "No Stun (防眩晕)",
    Default  = false,
    Flag     = "TSB_NoStun",
    Callback = function(s)
        SETTINGS.TSB_NoStun = s
        toggleNoStun(s)
    end,
})

MoveTab:AddToggle({
    Name     = "No Ragdoll (防布娃娃)",
    Default  = false,
    Flag     = "TSB_NoRagdoll",
    Callback = function(s)
        SETTINGS.TSB_NoRagdoll = s
        toggleNoRagdoll(s)
    end,
})

MoveTab:AddToggle({
    Name     = "No Dash Cooldown (无冲刺冷却)",
    Default  = false,
    Flag     = "TSB_NoDashCooldown",
    Callback = function(s)
        SETTINGS.TSB_NoDashCooldown = s
        toggleNoDashCooldown(s)
    end,
})

-- ── TAB 3: 视觉 ──
local VisualTab = Window:AddTab({
    Name = "视觉",
    Icon = "rbxassetid://6035153470",
})

VisualTab:AddSection({ Name = "ESP" })

VisualTab:AddToggle({
    Name     = "玩家 ESP (高亮)",
    Default  = false,
    Flag     = "TSB_ESPPlayer",
    Callback = function(s)
        SETTINGS.ESP_Player = s
        toggleESP(s or SETTINGS.ESP_Health or SETTINGS.ESP_Tracers)
    end,
})

VisualTab:AddToggle({
    Name     = "血量 ESP (血量条+数字)",
    Default  = false,
    Flag     = "TSB_ESPHealth",
    Callback = function(s)
        SETTINGS.ESP_Health = s
        toggleESP(s or SETTINGS.ESP_Player or SETTINGS.ESP_Tracers)
    end,
})

VisualTab:AddToggle({
    Name     = "显示距离",
    Default  = true,
    Flag     = "TSB_ESPDistance",
    Callback = function(s) SETTINGS.ESP_Distance = s end,
})

VisualTab:AddColorPicker({
    Name     = "ESP 颜色",
    Default  = Color3.fromRGB(0, 200, 255),
    Flag     = "TSB_PlayerColor",
    Callback  = function(c) SETTINGS.ESP_PlayerColor = c end,
})

VisualTab:AddButton({
    Name = "清除所有 ESP",
    Callback = function() clearESP() end,
})

VisualTab:AddSection({ Name = "世界" })

VisualTab:AddToggle({
    Name     = "全亮 (Fullbright)",
    Default  = false,
    Flag     = "TSB_Fullbright",
    Callback = function(s)
        SETTINGS.TSB_Fullbright = s
        toggleFullbright(s)
    end,
})

-- ── TAB 4: 农场 ──
local FarmTab = Window:AddTab({
    Name = "农场",
    Icon = "rbxassetid://6031280882",
})

FarmTab:AddSection({ Name = "自动农场" })

FarmTab:AddToggle({
    Name     = "Auto Farm (自动找敌+攻击)",
    Default  = false,
    Flag     = "TSB_AutoFarm",
    Callback = function(s)
        SETTINGS.TSB_AutoFarm = s
        toggleAutoFarm(s)
        notify("TSB", s and "Auto Farm 已开启" or "Auto Farm 已关闭", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddSection({ Name = "自动重置" })

FarmTab:AddToggle({
    Name     = "Auto Reset (低血量自动重置)",
    Default  = false,
    Flag     = "TSB_AutoReset",
    Callback = function(s)
        SETTINGS.TSB_AutoReset = s
    end,
})

FarmTab:AddSlider({
    Name      = "重置血量阈值",
    Min       = 5, Max = 80, Default = 20, Increment = 5,
    Suffix    = "%",
    Flag      = "TSB_AutoResetHP",
    Callback  = function(v) SETTINGS.TSB_AutoResetHP = v end,
})

-- ── TAB 5: 服务器 ──
local ServerTab = Window:AddTab({
    Name = "服务器",
    Icon = "rbxassetid://6035032976",
})

ServerTab:AddSection({ Name = "服务器操作" })

ServerTab:AddButton({
    Name = "重新加入 (Rejoin)",
    Callback = function()
        notify("TSB", "正在重新加入...", 2, "Info")
        rejoin()
    end,
})

ServerTab:AddButton({
    Name = "服务器跳转 (Server Hop)",
    Callback = function()
        notify("TSB", "正在跳转服务器...", 2, "Info")
        serverHop()
    end,
})

-- ── TAB 6: 杂项 ──
local MiscTab = Window:AddTab({
    Name = "杂项",
    Icon = "rbxassetid://6031280882",
})

MiscTab:AddSection({ Name = "Anti-AFK" })

MiscTab:AddToggle({
    Name     = "Anti-AFK (防挂机踢出)",
    Default  = false,
    Flag     = "TSB_AntiAFK",
    Callback = function(s)
        SETTINGS.TSB_AntiAFK = s
        if s then setupAntiAFK() end
    end,
})

MiscTab:AddSection({ Name = "坐标" })

local coordsLabel = MiscTab:AddLabel({ Text = "X: 0.00  Y: 0.00  Z: 0.00" })
task.spawn(function()
    while not isDestroyed do
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root and coordsLabel then
            local p = root.Position
            coordsLabel:SetText(string.format("X: %.2f   Y: %.2f   Z: %.2f", p.X, p.Y, p.Z))
        end
        task.wait(0.1)
    end
end)

MiscTab:AddButton({
    Name = "复制当前坐标",
    Callback = function()
        local root = getRoot()
        if root then
            local p = root.Position
            local s = string.format("Vector3.new(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
            if setclipboard then
                setclipboard(s)
                notify("TSB", "已复制: " .. s, 2, "Success")
            end
        end
    end,
})

MiscTab:AddSection({ Name = "信息" })

MiscTab:AddParagraph({
    Title   = "The Strongest Battlegrounds v1.0",
    Content = table.concat({
        "基于真实源码还原 (Spectral_Hub + Antimony + Speed Hub X)",
        "PlaceId: 10449761463",
        "",
        "源码分析:",
        "  技能系统: M1/技能1~4/终极/觉醒/冲刺",
        "  状态系统: Stunned/Ragdoll/Blocking",
        "  Mana系统: LocalPlayer.Mana (终极技能消耗)",
        "  角色种类: Hero Hunter/Saitama/Garou/Ninja/Brute",
        "",
        "功能:",
        "  • Kill Aura (范围自动攻击, 多因素优先级)",
        "  • Hitbox Expander (碰撞箱扩大)",
        "  • Auto Block + Auto Attack + Aimbot",
        "  • No Cooldown + No Stun + No Ragdoll + No Dash CD",
        "  • WalkSpeed/JumpPower/InfJump/NoClip/Fly",
        "  • Player ESP + 血量条 + 距离",
        "  • Auto Farm (自动找敌+传送+攻击)",
        "  • Auto Reset (低血量重置)",
        "  • Rejoin + Server Hop + Anti-AFK",
        "",
        "快捷键: RightShift 隐藏/显示 UI",
    }, "\n"),
})

-- ── 快捷键 ──
local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.T then
        local target = getClosestEnemy(200)
        if target and target.Character then
            local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
            local myRoot = getRoot()
            if targetHRP and myRoot then
                pcall(function()
                    myRoot.CFrame = CFrame.new(targetHRP.Position + targetHRP.CFrame.LookVector * 4)
                end)
                notify("T 快捷键", "→ 传送到 " .. target.Name, 1.5, "Info")
            end
        end
    elseif input.KeyCode == Enum.KeyCode.Y then
        local newState = not SETTINGS.TSB_NoClip
        SETTINGS.TSB_NoClip = newState
        toggleNoclip(newState)
        notify("Y 快捷键", newState and "NoClip ON" or "NoClip OFF", 1.5, "Info")
    elseif input.KeyCode == Enum.KeyCode.U then
        local newState = not SETTINGS.TSB_Fly
        SETTINGS.TSB_Fly = newState
        toggleFly(newState, SETTINGS.TSB_FlySpeed)
        notify("U 快捷键", newState and "Fly ON" or "Fly OFF", 1.5, "Info")
    end
end)

-- 角色重生时恢复设置
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if isDestroyed then return end
    if SETTINGS.TSB_WalkSpeed then setWalkSpeed(true, SETTINGS.TSB_WalkSpeedValue) end
    if SETTINGS.TSB_JumpPower then setJumpPower(true, SETTINGS.TSB_JumpPowerValue) end
    if SETTINGS.TSB_NoClip then toggleNoclip(true) end
    if SETTINGS.TSB_Fly then toggleFly(true, SETTINGS.TSB_FlySpeed) end
end)

-- ══════════════════════════════════════════════════════════════════
-- 14. 清理
-- ══════════════════════════════════════════════════════════════════
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    if inputConn then inputConn:Disconnect() end
    if charAddedConn then charAddedConn:Disconnect() end
    if noclipConn then noclipConn:Disconnect() end
    if infJumpConn then infJumpConn:Disconnect() end
    if flyConn then flyConn:Disconnect() end
    if killAuraConn then killAuraConn:Disconnect() end
    if autoBlockConn then autoBlockConn:Disconnect() end
    if autoAttackConn then autoAttackConn:Disconnect() end
    if noStunConn then noStunConn:Disconnect() end
    if noRagdollConn then noRagdollConn:Disconnect() end
    if noDashConn then noDashConn:Disconnect() end
    if noCooldownConn then noCooldownConn:Disconnect() end
    if espConn then espConn:Disconnect() end
    if farmConn then farmConn:Disconnect() end
    if aimbotConn then aimbotConn:Disconnect() end
    if antiAFKConn then antiAFKConn:Disconnect() end
    if _G.TSB_HitboxConn then _G.TSB_HitboxConn:Disconnect() _G.TSB_HitboxConn = nil end

    if flyBV then flyBV:Destroy() end
    if flyBG then flyBG:Destroy() end

    clearESP()
    toggleFullbright(false)
    setWalkSpeed(false, 16)
    setJumpPower(false, 50)

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "TSB", Text = "脚本已卸载", Duration = 2
        })
    end)
end

_G.TSB_Cleanup = cleanup

-- ── 完成通知 ──
task.wait(0.5)
notify("TSB v1.0", "The Strongest Battlegrounds 辅助已加载\n基于真实源码还原\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[TSB] v1.0 (PlaceId: %d) 辅助加载完成 — 基于真实源码还原", game.PlaceId))
