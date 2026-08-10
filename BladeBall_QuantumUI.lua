--[[
    Blade Ball 辅助脚本 v1.0 (Quantum UI 版)
    功能：AutoParry / AutoDash / AbilitySpam / KillAura / Reach / ESP / 移动修改 / AntiAFK
    快捷键：
        RightShift - 隐藏/显示 UI
        P          - AutoParry 开关
        V          - Noclip 开关
    所有功能均通过 UI 面板操作。
    安全承诺：不采集任何信息，不 loadstring 外部功能代码，所有逻辑本地实现。
--]]

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
    warn("[Blade Ball] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[Blade Ball] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[Blade Ball] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[Blade Ball] Quantum UI v" .. QuantumUI.Version .. " 加载成功")

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
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")

-- ══════════════════════════════════════════════════════════════════
-- 3. 预设颜色 & SETTINGS
-- ══════════════════════════════════════════════════════════════════
local PRESET_COLORS = {
    Color3.fromRGB(255, 80, 160),
    Color3.fromRGB(0, 200, 255),
    Color3.fromRGB(180, 60, 255),
    Color3.fromRGB(0, 255, 120),
    Color3.fromRGB(255, 70, 90),
    Color3.fromRGB(255, 200, 50),
    Color3.fromRGB(255, 105, 180),
    Color3.fromRGB(255, 255, 255),
}

local THEME_PRESETS = {
    ["Pink"]     = Color3.fromRGB(255, 80, 160),
    ["Cyan"]     = Color3.fromRGB(0, 200, 255),
    ["Purple"]   = Color3.fromRGB(180, 60, 255),
    ["Green"]    = Color3.fromRGB(0, 255, 120),
    ["Red"]      = Color3.fromRGB(255, 70, 90),
    ["Gold"]     = Color3.fromRGB(255, 200, 50),
    ["HotPink"]  = Color3.fromRGB(255, 105, 180),
}

local SETTINGS = {
    -- Combat
    BB_AutoParry = false,
    BB_AutoParryPrediction = 60,
    BB_AutoDash = false,
    BB_DashCooldownReduction = 0.5,
    BB_AbilitySpam = false,
    BB_KillAura = false,
    BB_Reach = false,
    BB_ReachStuds = 8,

    -- Visuals
    BB_BallESP = false,
    BB_BallESPColor = Color3.fromRGB(255, 80, 160),
    BB_PlayerESP = false,
    BB_PlayerESPColor = Color3.fromRGB(0, 200, 255),
    BB_Tracer = false,
    BB_NightMode = false,
    BB_FullBright = false,
    BB_HitboxVis = false,

    -- Movement
    BB_WalkSpeed = 50,
    BB_WalkSpeedEnabled = false,
    BB_JumpPower = 100,
    BB_JumpPowerEnabled = false,
    BB_InfJump = false,
    BB_Noclip = false,
    BB_Fly = false,
    BB_FlySpeed = 80,

    -- Player
    BB_AntiAFK = false,

    -- Keybinds
    BB_UIKey = Enum.KeyCode.RightShift,
    BB_AutoParryKey = Enum.KeyCode.P,
    BB_NoclipKey = Enum.KeyCode.V,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 全局变量
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false

local espObjects = {}
local ballEspObjects = {}
local tracerLines = {}
local hitboxParts = {}

local mainLoopConn = nil
local noclipConn = nil
local infJumpConn = nil
local flyConn = nil
local flyBV = nil
local flyBG = nil
local antiAFKConn = nil
local nightModeCache = {}

local lastParryTime = 0
local lastAbilityTime = 0
local lastDashTime = 0
local lastKillAuraTime = 0

local selectedPlayer = nil
local playerDropdownItems = {}

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

local function findParryRemotes()
    local remotes = {}
    pcall(function()
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v:IsA("RemoteEvent") then
                local nameLower = v.Name:lower()
                if nameLower:find("parry") or nameLower:find("swing") or nameLower:find("sword") or nameLower:find("ball") or nameLower:find("hit") or nameLower:find("attack") then
                    table.insert(remotes, v)
                end
            end
        end
    end)
    return remotes
end

local function findAttackRemotes()
    local remotes = {}
    pcall(function()
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v:IsA("RemoteEvent") then
                local nameLower = v.Name:lower()
                if nameLower:find("hit") or nameLower:find("attack") or nameLower:find("sword") or nameLower:find("swing") or nameLower:find("damage") then
                    table.insert(remotes, v)
                end
            end
        end
    end)
    return remotes
end

local function findAbilityRemotes()
    local remotes = {}
    pcall(function()
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v:IsA("RemoteEvent") then
                local nameLower = v.Name:lower()
                if nameLower:find("ability") or nameLower:find("skill") or nameLower:find("dash") or nameLower:find("action") or nameLower:find("use") then
                    table.insert(remotes, v)
                end
            end
        end
    end)
    return remotes
end

local function getBalls()
    local balls = {}
    pcall(function()
        for _, v in pairs(Workspace:GetDescendants()) do
            if v:IsA("BasePart") then
                local nameLower = v.Name:lower()
                if nameLower == "ball" then
                    table.insert(balls, v)
                elseif v:FindFirstChild("Forces") or v:FindFirstChild("Velocity") or v:FindFirstChildOfClass("BodyVelocity") or v:FindFirstChildOfClass("LinearVelocity") then
                    if v:IsA("BasePart") and v.Shape ~= Enum.PartType.Block then
                        table.insert(balls, v)
                    end
                end
            elseif v:IsA("Model") and v.Name:lower():find("ball") then
                local primary = v.PrimaryPart or v:FindFirstChildWhichIsA("BasePart")
                if primary then table.insert(balls, primary) end
            end
        end
    end)
    return balls
end

local function getClosestBall()
    local localRoot = getRoot()
    if not localRoot then return nil, math.huge end
    local closestBall = nil
    local closestDist = math.huge
    local localPos = localRoot.Position
    for _, ball in ipairs(getBalls()) do
        local dist = (ball.Position - localPos).Magnitude
        if dist < closestDist then
            closestDist = dist
            closestBall = ball
        end
    end
    return closestBall, closestDist
end

-- ══════════════════════════════════════════════════════════════════
-- 7. Combat: AutoParry / AutoDash / AbilitySpam / KillAura / Reach
-- ══════════════════════════════════════════════════════════════════
local parryRemotes = nil
local attackRemotes = nil
local abilityRemotes = nil

local function ensureRemotes()
    if not parryRemotes then parryRemotes = findParryRemotes() end
    if not attackRemotes then attackRemotes = findAttackRemotes() end
    if not abilityRemotes then abilityRemotes = findAbilityRemotes() end
end

local function fireParry()
    ensureRemotes()
    local now = tick()
    local predictionSec = SETTINGS.BB_AutoParryPrediction / 1000
    if now - lastParryTime < 0.1 then return end
    lastParryTime = now
    pcall(function()
        for _, remote in ipairs(parryRemotes) do
            pcall(function()
                remote:FireServer()
            end)
        end
    end)
end

local function fireAbility()
    ensureRemotes()
    local now = tick()
    if now - lastAbilityTime < 0.3 then return end
    lastAbilityTime = now
    pcall(function()
        for _, remote in ipairs(abilityRemotes) do
            pcall(function()
                remote:FireServer()
            end)
        end
    end)
end

local function fireDash()
    ensureRemotes()
    local now = tick()
    local cooldown = 1 - SETTINGS.BB_DashCooldownReduction
    cooldown = math.max(0.1, cooldown)
    if now - lastDashTime < cooldown then return end
    lastDashTime = now
    pcall(function()
        for _, remote in ipairs(abilityRemotes) do
            local nameLower = remote.Name:lower()
            if nameLower:find("dash") then
                pcall(function() remote:FireServer() end)
            end
        end
    end)
end

local function fireAttack(targetPlayer)
    ensureRemotes()
    pcall(function()
        for _, remote in ipairs(attackRemotes) do
            pcall(function()
                if targetPlayer then
                    remote:FireServer(targetPlayer)
                else
                    remote:FireServer()
                end
            end)
        end
    end)
end

local function updateCombat()
    if isDestroyed then return end
    local localRoot = getRoot()
    if not localRoot then return end

    if SETTINGS.BB_AutoParry then
        local ball, dist = getClosestBall()
        if ball then
            local threshold = 12
            local velocity = ball.Velocity or Vector3.zero
            local speed = velocity.Magnitude
            local predictionSec = SETTINGS.BB_AutoParryPrediction / 1000
            local predictedDist = dist - speed * predictionSec
            if predictedDist < threshold or dist < threshold then
                fireParry()
            end
        end
    end

    if SETTINGS.BB_AutoDash then
        local ball, dist = getClosestBall()
        if ball and dist < 15 then
            fireDash()
        end
    end

    if SETTINGS.BB_AbilitySpam then
        fireAbility()
    end

    if SETTINGS.BB_KillAura then
        local now = tick()
        if now - lastKillAuraTime < 0.15 then return end
        lastKillAuraTime = now
        local localPos = localRoot.Position
        local reachDist = SETTINGS.BB_Reach and SETTINGS.BB_ReachStuds or 6
        for _, player in pairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local char = player.Character
            if not char then continue end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then continue end
            local dist = (root.Position - localPos).Magnitude
            if dist <= reachDist then
                fireAttack(player)
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 8. Movement: WalkSpeed / JumpPower / InfJump / Noclip / Fly
-- ══════════════════════════════════════════════════════════════════
local function updateMovement()
    if isDestroyed then return end
    local hum = getHum()
    if not hum then return end

    if SETTINGS.BB_WalkSpeedEnabled then
        if hum.WalkSpeed ~= SETTINGS.BB_WalkSpeed then
            hum.WalkSpeed = SETTINGS.BB_WalkSpeed
        end
    end

    if SETTINGS.BB_JumpPowerEnabled then
        if hum.JumpPower ~= SETTINGS.BB_JumpPower then
            hum.JumpPower = SETTINGS.BB_JumpPower
        end
    end
end

local function enableInfJump()
    if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
    infJumpConn = UserInputService.JumpRequest:Connect(function()
        if not SETTINGS.BB_InfJump then
            infJumpConn:Disconnect()
            infJumpConn = nil
            return
        end
        local hum = getHum()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

local function enableNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    noclipConn = RunService.Stepped:Connect(function()
        if not SETTINGS.BB_Noclip then
            noclipConn:Disconnect()
            noclipConn = nil
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = true
                    end
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
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end

    task.spawn(function()
        local root = getRoot()
        local hum = getHum()
        if not root or not hum then return end
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
            if not SETTINGS.BB_Fly then
                flyConn:Disconnect()
                flyConn = nil
                local h = getHum()
                if h then h.PlatformStand = false end
                if flyBV then flyBV:Destroy(); flyBV = nil end
                if flyBG then flyBG:Destroy(); flyBG = nil end
                return
            end
            local r = getRoot()
            local cam = workspace.CurrentCamera
            if not r or not cam then return end
            local dir = Vector3.zero
            local cf = cam.CFrame
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
            if flyBV then flyBV.Velocity = dir * SETTINGS.BB_FlySpeed end
            if flyBG then flyBG.CFrame = cam.CFrame end
        end)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 9. Visuals: ESP / Tracer / NightMode / FullBright / Hitbox
-- ══════════════════════════════════════════════════════════════════
local function createPlayerESP(player)
    if espObjects[player] then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "BB_PlayerHighlight"
    highlight.FillColor = SETTINGS.BB_PlayerESPColor
    highlight.OutlineColor = SETTINGS.BB_PlayerESPColor
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0.3
    highlight.Enabled = false
    highlight.Parent = player.Character or player

    local nameText = Drawing.new("Text")
    nameText.Visible = false
    nameText.Color = Color3.new(1,1,1)
    nameText.Size = 14
    nameText.Center = true
    nameText.Outline = true
    nameText.OutlineColor = Color3.new(0,0,0)

    local tracer = Drawing.new("Line")
    tracer.Visible = false
    tracer.Thickness = 1
    tracer.Transparency = 0.7
    tracer.Color = SETTINGS.BB_PlayerESPColor

    espObjects[player] = {
        Highlight = highlight,
        NameText = nameText,
        Tracer = tracer,
        Player = player,
    }

    player.CharacterAdded:Connect(function(newChar)
        task.wait(0.1)
        local obj = espObjects[player]
        if obj and obj.Highlight then
            obj.Highlight.Adornee = newChar
            obj.Highlight.Parent = newChar
        end
    end)
end

local function createBallESP(ball)
    if ballEspObjects[ball] then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "BB_BallHighlight"
    highlight.FillColor = SETTINGS.BB_BallESPColor
    highlight.OutlineColor = SETTINGS.BB_BallESPColor
    highlight.FillTransparency = 0.3
    highlight.OutlineTransparency = 0.1
    highlight.Enabled = false
    highlight.Adornee = ball
    highlight.Parent = ball

    local tracer = Drawing.new("Line")
    tracer.Visible = false
    tracer.Thickness = 1
    tracer.Transparency = 0.8
    tracer.Color = SETTINGS.BB_BallESPColor

    ballEspObjects[ball] = {
        Highlight = highlight,
        Tracer = tracer,
        Ball = ball,
    }
end

local function clearHitboxes()
    for _, part in pairs(hitboxParts) do
        pcall(function() part:Destroy() end)
    end
    hitboxParts = {}
end

local function updateHitboxes()
    if not SETTINGS.BB_HitboxVis then
        clearHitboxes()
        return
    end
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and not hitboxParts[part] then
                local box = Instance.new("SelectionBox")
                box.Name = "BB_HitboxVis"
                box.Adornee = part
                box.LineThickness = 0.05
                box.Color3 = SETTINGS.BB_PlayerESPColor
                box.Transparency = 0.5
                box.Parent = CoreGui
                hitboxParts[part] = box
            end
        end
    end
    for part, box in pairs(hitboxParts) do
        if not part or not part.Parent then
            pcall(function() box:Destroy() end)
            hitboxParts[part] = nil
        end
    end
end

local function enableNightMode()
    for _, v in pairs(Lighting:GetChildren()) do
        if v:IsA("Atmosphere") or v:IsA("Sky") or v:IsA("Clouds") then
            nightModeCache[v] = true
        end
    end
    Lighting.ClockTime = 0
    Lighting.FogEnd = 1000
    Lighting.Ambient = Color3.fromRGB(20, 20, 40)
    Lighting.OutdoorAmbient = Color3.fromRGB(10, 10, 25)
    for v in pairs(nightModeCache) do
        pcall(function() v.Enabled = false end)
    end
end

local function disableNightMode()
    Lighting.ClockTime = 14
    Lighting.FogEnd = 100000
    Lighting.Ambient = Color3.fromRGB(128, 128, 128)
    Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    for v in pairs(nightModeCache) do
        pcall(function() v.Enabled = true end)
    end
    nightModeCache = {}
end

local origBrightness = nil
local origAmbient = nil
local origOutdoorAmbient = nil

local function enableFullBright()
    if not origBrightness then
        origBrightness = Lighting.Brightness
        origAmbient = Lighting.Ambient
        origOutdoorAmbient = Lighting.OutdoorAmbient
    end
    Lighting.Brightness = 3
    Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
end

local function disableFullBright()
    if origBrightness then
        Lighting.Brightness = origBrightness
        Lighting.Ambient = origAmbient
        Lighting.OutdoorAmbient = origOutdoorAmbient
    end
end

local function updateVisuals()
    if isDestroyed then return end
    local localRoot = getRoot()
    local viewportSize = Camera.ViewportSize
    local screenBottom = Vector2.new(viewportSize.X / 2, viewportSize.Y)

    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local obj = espObjects[player]
        if not obj then
            createPlayerESP(player)
            obj = espObjects[player]
        end
        local char = player.Character
        if not char then
            if obj.Highlight then obj.Highlight.Enabled = false end
            obj.NameText.Visible = false
            obj.Tracer.Visible = false
            continue
        end
        local root = char:FindFirstChild("HumanoidRootPart")
        local head = char:FindFirstChild("Head")
        if not root or not head then
            if obj.Highlight then obj.Highlight.Enabled = false end
            obj.NameText.Visible = false
            obj.Tracer.Visible = false
            continue
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local isDead = hum and hum.Health <= 0

        if obj.Highlight then
            obj.Highlight.Enabled = (SETTINGS.BB_PlayerESP and not isDead)
            obj.Highlight.FillColor = SETTINGS.BB_PlayerESPColor
            obj.Highlight.OutlineColor = SETTINGS.BB_PlayerESPColor
        end

        local headPos, headVis = Camera:WorldToViewportPoint(head.Position)
        if SETTINGS.BB_PlayerESP and not isDead and headVis then
            obj.NameText.Position = Vector2.new(headPos.X, headPos.Y - 25)
            obj.NameText.Text = player.Name
            obj.NameText.Color = Color3.new(1,1,1)
            obj.NameText.Visible = true
        else
            obj.NameText.Visible = false
        end

        if SETTINGS.BB_Tracer and SETTINGS.BB_PlayerESP and not isDead and headVis then
            local rootPos, rootVis = Camera:WorldToViewportPoint(root.Position)
            if rootVis then
                obj.Tracer.From = screenBottom
                obj.Tracer.To = Vector2.new(rootPos.X, rootPos.Y)
                obj.Tracer.Color = SETTINGS.BB_PlayerESPColor
                obj.Tracer.Visible = true
            else
                obj.Tracer.Visible = false
            end
        else
            obj.Tracer.Visible = false
        end
    end

    for player, obj in pairs(espObjects) do
        if not Players:FindFirstChild(player.Name) then
            if obj.Highlight then obj.Highlight:Destroy() end
            obj.NameText:Remove()
            obj.Tracer:Remove()
            espObjects[player] = nil
        end
    end

    local balls = getBalls()
    local seenBalls = {}
    for _, ball in ipairs(balls) do
        seenBalls[ball] = true
        local obj = ballEspObjects[ball]
        if not obj then
            createBallESP(ball)
            obj = ballEspObjects[ball]
        end
        if obj.Highlight then
            obj.Highlight.Enabled = SETTINGS.BB_BallESP
            obj.Highlight.FillColor = SETTINGS.BB_BallESPColor
            obj.Highlight.OutlineColor = SETTINGS.BB_BallESPColor
        end
        local ballPos, ballVis = Camera:WorldToViewportPoint(ball.Position)
        if SETTINGS.BB_Tracer and SETTINGS.BB_BallESP and ballVis then
            obj.Tracer.From = screenBottom
            obj.Tracer.To = Vector2.new(ballPos.X, ballPos.Y)
            obj.Tracer.Color = SETTINGS.BB_BallESPColor
            obj.Tracer.Visible = true
        else
            obj.Tracer.Visible = false
        end
    end
    for ball, obj in pairs(ballEspObjects) do
        if not seenBalls[ball] then
            if obj.Highlight then obj.Highlight:Destroy() end
            obj.Tracer:Remove()
            ballEspObjects[ball] = nil
        end
    end

    updateHitboxes()
end

-- ══════════════════════════════════════════════════════════════════
-- 10. Player Tab: 玩家列表 / 传送 / AntiAFK / Rejoin / ServerHop
-- ══════════════════════════════════════════════════════════════════
local function refreshPlayerList()
    playerDropdownItems = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(playerDropdownItems, player.Name)
        end
    end
    table.sort(playerDropdownItems)
    return playerDropdownItems
end

local function teleportToPlayer(targetName)
    local targetPlayer = nil
    for _, player in pairs(Players:GetPlayers()) do
        if player.Name == targetName then
            targetPlayer = player
            break
        end
    end
    if not targetPlayer then
        notify("传送", "未找到玩家: " .. tostring(targetName), 3, "Warning")
        return
    end
    local targetChar = targetPlayer.Character
    if not targetChar then
        notify("传送", "目标玩家尚未生成", 3, "Warning")
        return
    end
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local localChar = getChar()
    if not targetRoot or not localChar then
        notify("传送", "无法获取位置信息", 3, "Warning")
        return
    end
    local offset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
    localChar:PivotTo(CFrame.new(targetRoot.Position + offset))
    notify("传送", "已传送到: " .. targetPlayer.Name, 2, "Success")
end

local function rejoin()
    local placeId = game.PlaceId
    local jobId = game.JobId
    pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
    end)
    notify("Rejoin", "正在重新加入...", 3, "Info")
end

local function serverHop()
    local placeId = game.PlaceId
    pcall(function()
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
    notify("ServerHop", "正在跳转到其他服务器...", 3, "Info")
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 销毁脚本
-- ══════════════════════════════════════════════════════════════════
local function destroyScript()
    if isDestroyed then return end
    isDestroyed = true

    if mainLoopConn then mainLoopConn:Disconnect(); mainLoopConn = nil end
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end

    SETTINGS.BB_Noclip = false
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
    local hum = getHum()
    if hum then
        hum.PlatformStand = false
        hum.WalkSpeed = 16
        hum.JumpPower = 50
    end

    disableNightMode()
    disableFullBright()
    clearHitboxes()

    for player, obj in pairs(espObjects) do
        if obj.Highlight then obj.Highlight:Destroy() end
        pcall(function() obj.NameText:Remove() end)
        pcall(function() obj.Tracer:Remove() end)
    end
    espObjects = {}
    for ball, obj in pairs(ballEspObjects) do
        if obj.Highlight then obj.Highlight:Destroy() end
        pcall(function() obj.Tracer:Remove() end)
    end
    ballEspObjects = {}

    if Window then pcall(function() Window:Destroy() end) end
    if _G.QuantumUI_Window then _G.QuantumUI_Window = nil end

    notify("销毁", "脚本已彻底销毁", 2, "Warning")
    print("[Blade Ball] 脚本已彻底销毁")
end

-- ══════════════════════════════════════════════════════════════════
-- 12. 构建 Quantum UI 界面
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title = "Blade Ball 辅助",
    Subtitle = "利刃球",
    ThemeColor = Color3.fromRGB(255, 80, 160),
    Transparency = 0.3,
    Size = UDim2.new(0, 620, 0, 520),
    Keybind = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ========== TAB 1: Combat ==========
local CombatTab = Window:AddTab({
    Name = "Combat",
    Icon = "rbxassetid://6034287594"
})

CombatTab:AddSection({ Name = "⚔️ 战斗功能" })

CombatTab:AddToggle({
    Name = "Auto Parry (自动格挡)",
    Default = SETTINGS.BB_AutoParry,
    Flag = "BB_AutoParry",
    Callback = function(val)
        SETTINGS.BB_AutoParry = val
        notify("Auto Parry", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

CombatTab:AddSlider({
    Name = "Auto Parry Prediction (预测时间)",
    Min = 0, Max = 200, Default = SETTINGS.BB_AutoParryPrediction, Increment = 5,
    Suffix = " ms",
    Flag = "BB_AutoParryPrediction",
    Callback = function(val) SETTINGS.BB_AutoParryPrediction = val end
})

CombatTab:AddToggle({
    Name = "Auto Dash (自动冲刺)",
    Default = SETTINGS.BB_AutoDash,
    Flag = "BB_AutoDash",
    Callback = function(val)
        SETTINGS.BB_AutoDash = val
        notify("Auto Dash", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

CombatTab:AddSlider({
    Name = "Dash Cooldown Reduction (冷却减少)",
    Min = 0, Max = 1, Default = SETTINGS.BB_DashCooldownReduction, Increment = 0.05,
    Flag = "BB_DashCooldownReduction",
    Callback = function(val) SETTINGS.BB_DashCooldownReduction = val end
})

CombatTab:AddToggle({
    Name = "Ability Spam (技能连发)",
    Default = SETTINGS.BB_AbilitySpam,
    Flag = "BB_AbilitySpam",
    Callback = function(val)
        SETTINGS.BB_AbilitySpam = val
        notify("Ability Spam", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

CombatTab:AddToggle({
    Name = "Kill Aura (击杀光环)",
    Default = SETTINGS.BB_KillAura,
    Flag = "BB_KillAura",
    Callback = function(val)
        SETTINGS.BB_KillAura = val
        notify("Kill Aura", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

CombatTab:AddToggle({
    Name = "Reach (增加攻击距离)",
    Default = SETTINGS.BB_Reach,
    Flag = "BB_Reach",
    Callback = function(val)
        SETTINGS.BB_Reach = val
        notify("Reach", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

CombatTab:AddSlider({
    Name = "Reach Studs (攻击距离)",
    Min = 2, Max = 20, Default = SETTINGS.BB_ReachStuds, Increment = 1,
    Suffix = " studs",
    Flag = "BB_ReachStuds",
    Callback = function(val) SETTINGS.BB_ReachStuds = val end
})

-- ========== TAB 2: Visuals ==========
local VisualsTab = Window:AddTab({
    Name = "Visuals",
    Icon = "rbxassetid://6034509993"
})

VisualsTab:AddSection({ Name = "👁️ 视觉功能" })

VisualsTab:AddToggle({
    Name = "Ball ESP (球体透视)",
    Default = SETTINGS.BB_BallESP,
    Flag = "BB_BallESP",
    Callback = function(val)
        SETTINGS.BB_BallESP = val
        notify("Ball ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

VisualsTab:AddColorPicker({
    Name = "Ball ESP Color",
    Default = SETTINGS.BB_BallESPColor,
    Presets = PRESET_COLORS,
    Flag = "BB_BallESPColor",
    Callback = function(c) SETTINGS.BB_BallESPColor = c end
})

VisualsTab:AddToggle({
    Name = "Player ESP (玩家透视)",
    Default = SETTINGS.BB_PlayerESP,
    Flag = "BB_PlayerESP",
    Callback = function(val)
        SETTINGS.BB_PlayerESP = val
        notify("Player ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

VisualsTab:AddColorPicker({
    Name = "Player ESP Color",
    Default = SETTINGS.BB_PlayerESPColor,
    Presets = PRESET_COLORS,
    Flag = "BB_PlayerESPColor",
    Callback = function(c) SETTINGS.BB_PlayerESPColor = c end
})

VisualsTab:AddToggle({
    Name = "Tracer (追踪线)",
    Default = SETTINGS.BB_Tracer,
    Flag = "BB_Tracer",
    Callback = function(val)
        SETTINGS.BB_Tracer = val
        notify("Tracer", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

VisualsTab:AddToggle({
    Name = "Night Mode (夜间模式)",
    Default = SETTINGS.BB_NightMode,
    Flag = "BB_NightMode",
    Callback = function(val)
        SETTINGS.BB_NightMode = val
        if val then enableNightMode() else disableNightMode() end
        notify("Night Mode", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

VisualsTab:AddToggle({
    Name = "Full Bright (全屏亮度)",
    Default = SETTINGS.BB_FullBright,
    Flag = "BB_FullBright",
    Callback = function(val)
        SETTINGS.BB_FullBright = val
        if val then enableFullBright() else disableFullBright() end
        notify("Full Bright", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

VisualsTab:AddToggle({
    Name = "Hitbox Visualizer (碰撞箱显示)",
    Default = SETTINGS.BB_HitboxVis,
    Flag = "BB_HitboxVis",
    Callback = function(val)
        SETTINGS.BB_HitboxVis = val
        if not val then clearHitboxes() end
        notify("Hitbox Visualizer", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

-- ========== TAB 3: Movement ==========
local MovementTab = Window:AddTab({
    Name = "Movement",
    Icon = "rbxassetid://6034466796"
})

MovementTab:AddSection({ Name = "🏃 移动功能" })

MovementTab:AddSlider({
    Name = "Walk Speed (行走速度)",
    Min = 16, Max = 200, Default = SETTINGS.BB_WalkSpeed, Increment = 1,
    Suffix = " studs/s",
    Flag = "BB_WalkSpeed",
    Callback = function(val) SETTINGS.BB_WalkSpeed = val end
})

MovementTab:AddToggle({
    Name = "Enable Walk Speed",
    Default = SETTINGS.BB_WalkSpeedEnabled,
    Flag = "BB_WalkSpeedEnabled",
    Callback = function(val)
        SETTINGS.BB_WalkSpeedEnabled = val
        notify("Walk Speed", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if not val then
            local hum = getHum()
            if hum then hum.WalkSpeed = 16 end
        end
    end
})

MovementTab:AddSlider({
    Name = "Jump Power (跳跃力)",
    Min = 50, Max = 200, Default = SETTINGS.BB_JumpPower, Increment = 1,
    Flag = "BB_JumpPower",
    Callback = function(val) SETTINGS.BB_JumpPower = val end
})

MovementTab:AddToggle({
    Name = "Enable Jump Power",
    Default = SETTINGS.BB_JumpPowerEnabled,
    Flag = "BB_JumpPowerEnabled",
    Callback = function(val)
        SETTINGS.BB_JumpPowerEnabled = val
        notify("Jump Power", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if not val then
            local hum = getHum()
            if hum then hum.JumpPower = 50 end
        end
    end
})

MovementTab:AddToggle({
    Name = "Infinite Jump (无限跳)",
    Default = SETTINGS.BB_InfJump,
    Flag = "BB_InfJump",
    Callback = function(val)
        SETTINGS.BB_InfJump = val
        if val then enableInfJump() end
        notify("Infinite Jump", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

MovementTab:AddToggle({
    Name = "Noclip (穿墙)",
    Default = SETTINGS.BB_Noclip,
    Flag = "BB_Noclip",
    Callback = function(val)
        SETTINGS.BB_Noclip = val
        if val then enableNoclip() end
        notify("Noclip", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

MovementTab:AddToggle({
    Name = "Fly (飞行)",
    Default = SETTINGS.BB_Fly,
    Flag = "BB_Fly",
    Callback = function(val)
        SETTINGS.BB_Fly = val
        if val then
            enableFly()
            notify("Fly", "已启用 (WASD/Space/Shift 控制)", 3, "Success")
        else
            local hum = getHum()
            if hum then hum.PlatformStand = false end
            notify("Fly", "已禁用", 2, "Warning")
        end
    end
})

MovementTab:AddSlider({
    Name = "Fly Speed (飞行速度)",
    Min = 10, Max = 200, Default = SETTINGS.BB_FlySpeed, Increment = 5,
    Flag = "BB_FlySpeed",
    Callback = function(val) SETTINGS.BB_FlySpeed = val end
})

-- ========== TAB 4: Player ==========
local PlayerTab = Window:AddTab({
    Name = "Player",
    Icon = "rbxassetid://6031280882"
})

PlayerTab:AddSection({ Name = "👥 玩家操作" })

local playerDropdown = PlayerTab:AddDropdown({
    Name = "玩家列表",
    Items = refreshPlayerList(),
    Default = "请选择玩家",
    Multi = false,
    Flag = "BB_SelectedPlayer",
    Callback = function(selected)
        selectedPlayer = selected
    end
})

PlayerTab:AddButton({
    Name = "🔄 刷新玩家列表",
    Callback = function()
        local items = refreshPlayerList()
        if playerDropdown and playerDropdown.Refresh then
            playerDropdown:Refresh(items)
        end
        notify("玩家列表", "已刷新，共 " .. #items .. " 名玩家", 2, "Info")
    end
})

PlayerTab:AddButton({
    Name = "🚀 传送到选中玩家",
    Callback = function()
        if not selectedPlayer then
            notify("传送", "请先在下拉列表选择玩家", 3, "Warning")
            return
        end
        teleportToPlayer(selectedPlayer)
    end
})

PlayerTab:AddSection({ Name = "🛡️ 防挂机 & 服务器" })

PlayerTab:AddToggle({
    Name = "Anti AFK (防挂机)",
    Default = SETTINGS.BB_AntiAFK,
    Flag = "BB_AntiAFK",
    Callback = function(val)
        SETTINGS.BB_AntiAFK = val
        notify("Anti AFK", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

PlayerTab:AddButton({
    Name = "🔀 Server Hop (换服)",
    Callback = function()
        serverHop()
    end
})

PlayerTab:AddButton({
    Name = "🔁 Rejoin (重连)",
    Callback = function()
        rejoin()
    end
})

-- ========== TAB 5: Keybinds ==========
local KeybindsTab = Window:AddTab({
    Name = "Keybinds",
    Icon = "rbxassetid://6034281467"
})

KeybindsTab:AddSection({ Name = "⌨️ 快捷键绑定" })

KeybindsTab:AddKeybind({
    Name = "UI 切换 (默认 RightShift)",
    Default = Enum.KeyCode.RightShift,
    Flag = "BB_UIKey",
    Callback = function()
        notify("快捷键", "UI 切换键已设置", 2, "Info")
    end
})

KeybindsTab:AddKeybind({
    Name = "AutoParry 切换 (默认 P)",
    Default = Enum.KeyCode.P,
    Flag = "BB_AutoParryKey",
    Callback = function()
        SETTINGS.BB_AutoParry = not SETTINGS.BB_AutoParry
        if Window and Window.Flags and Window.Flags["BB_AutoParry"] then
            pcall(function() Window.Flags["BB_AutoParry"]:Set(SETTINGS.BB_AutoParry) end)
        end
        notify("Auto Parry", SETTINGS.BB_AutoParry and "已启用" or "已禁用", 2, SETTINGS.BB_AutoParry and "Success" or "Warning")
    end
})

KeybindsTab:AddKeybind({
    Name = "Noclip 切换 (默认 V)",
    Default = Enum.KeyCode.V,
    Flag = "BB_NoclipKey",
    Callback = function()
        SETTINGS.BB_Noclip = not SETTINGS.BB_Noclip
        if SETTINGS.BB_Noclip then enableNoclip() end
        if Window and Window.Flags and Window.Flags["BB_Noclip"] then
            pcall(function() Window.Flags["BB_Noclip"]:Set(SETTINGS.BB_Noclip) end)
        end
        notify("Noclip", SETTINGS.BB_Noclip and "已启用" or "已禁用", 2, SETTINGS.BB_Noclip and "Success" or "Warning")
    end
})

-- ========== TAB 6: Misc ==========
local MiscTab = Window:AddTab({
    Name = "Misc",
    Icon = "rbxassetid://6031094678"
})

MiscTab:AddSection({ Name = "💀 脚本控制" })

MiscTab:AddButton({
    Name = "🔁 Rejoin (重新加入)",
    Callback = function()
        rejoin()
    end
})

MiscTab:AddButton({
    Name = "💀 Destroy (销毁脚本)",
    Callback = function()
        destroyScript()
    end
})

MiscTab:AddSection({ Name = "🌈 UI 外观" })

MiscTab:AddToggle({
    Name = "彩虹边框动画",
    Default = QuantumUI.RainbowEnabled,
    Flag = "BB_RainbowBorder",
    Callback = function(state)
        QuantumUI.RainbowEnabled = state
        notify("彩虹边框", state and "已启用" or "已禁用", 2, state and "Success" or "Warning")
    end
})

MiscTab:AddSlider({
    Name = "彩虹速度",
    Min = 0.1, Max = 5, Default = QuantumUI.RainbowSpeed, Increment = 0.1,
    Suffix = "x",
    Flag = "BB_RainbowSpeed",
    Callback = function(value) QuantumUI.RainbowSpeed = value end
})

MiscTab:AddDropdown({
    Name = "预设主题色 (7种)",
    Items = {"Pink", "Cyan", "Purple", "Green", "Red", "Gold", "HotPink"},
    Default = "Pink",
    Flag = "BB_ThemePreset",
    Callback = function(selected)
        local color = THEME_PRESETS[selected]
        if color then
            Window.ThemeColor = color
            QuantumUI.ThemeColor = color
            Window:RefreshTheme()
            notify("主题", "已切换: " .. selected, 2, "Success")
        end
    end
})

MiscTab:AddSection({ Name = "📖 About (关于)" })

MiscTab:AddParagraph({
    Title = "Blade Ball 辅助 v1.0",
    Content = table.concat({
        "游戏: Blade Ball / 利刃球",
        "UI 框架: Quantum UI (SciFi-UI-Library)",
        "",
        "功能列表:",
        "  Combat: AutoParry / AutoDash / AbilitySpam",
        "          KillAura / Reach",
        "  Visuals: BallESP / PlayerESP / Tracer",
        "           NightMode / FullBright / HitboxVis",
        "  Movement: WalkSpeed / JumpPower / InfJump",
        "            Noclip / Fly",
        "  Player: TP玩家 / AntiAFK / ServerHop / Rejoin",
        "",
        "快捷键:",
        "  RightShift - 隐藏/显示 UI",
        "  P          - AutoParry 开关",
        "  V          - Noclip 开关",
        "",
        "安全说明: 本脚本不采集任何信息，",
        "不 loadstring 外部功能代码，",
        "所有逻辑均为本地实现。",
    }, "\n")
})

-- ══════════════════════════════════════════════════════════════════
-- 13. 主初始化 & 主循环
-- ══════════════════════════════════════════════════════════════════
task.wait(0.5)

ensureRemotes()

mainLoopConn = RunService.RenderStepped:Connect(function()
    updateCombat()
    updateMovement()
    updateVisuals()
end)

-- Anti AFK 绑定
LocalPlayer.Idled:Connect(function()
    if SETTINGS.BB_AntiAFK and not isDestroyed then
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end
end)

-- 角色重生处理
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if isDestroyed then return end
    if SETTINGS.BB_Noclip then enableNoclip() end
    if SETTINGS.BB_InfJump then enableInfJump() end
    if SETTINGS.BB_Fly then enableFly() end
    if SETTINGS.BB_NightMode then enableNightMode() end
    if SETTINGS.BB_FullBright then enableFullBright() end
end)

-- ══════════════════════════════════════════════════════════════════
-- 14. 加载完成通知
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
notify("✅ Blade Ball 辅助加载完成!",
    "Quantum UI 版本\n" ..
    "按 RightShift 切换 UI 显示\n" ..
    "按 P 切换 AutoParry\n" ..
    "按 V 切换 Noclip",
    6, "Success")

print("========================================")
print(" Blade Ball 辅助 v1.0 (Quantum UI 版) 加载完成")
print("   RightShift - 隐藏/显示 UI")
print("   P          - AutoParry 开关")
print("   V          - Noclip 开关")
print("========================================")
