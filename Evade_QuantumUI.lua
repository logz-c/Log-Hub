--[[
    Evade 辅助脚本 v2.0 (Quantum UI 版)
    基于 VanillaSourceCode/evade + NoobHubV4/RobloxScripts 真实源码还原
    适配 PlaceId: 9872472334 (Evade)

    游戏内部结构 (来自源码分析):
      workspace.Game.Players        — 玩家+AI角色容器
      workspace.Game.Map.InvisParts — 隐形障碍
      workspace.Game.Map.Parts.KillBricks — 击杀砖块
      workspace.Game.Effects.Tickets — 票券拾取
      workspace.Game.Settings       — 复活时间等属性
      ReplicatedStorage.Events.Player.ChangePlayerMode — 重生事件
      ReplicatedStorage.Events.Character.Interact     — 交互(Revive/Carry)

    功能:
      角色: 自动重生 / 即时复活 / 即时搬运 / 自动复活 / 快速复活
      农场: Money Farm / AFK Farm / Ticket Farm
      移动: CFrame Speed Boost / Fly / NoClip
      视觉: Nextbot ESP / 玩家ESP / 倒地ESP / 票券ESP / 全亮 / 移除障碍 / 移除KillBricks
      服务器: 重join
      杂项: Anti-AFK / 坐标

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
local TeleportService = game:GetService("TeleportService")
local Workspace = workspace
local Lighting = game:GetService("Lighting")

-- ══════════════════════════════════════════════════════════════════
-- 3. 游戏路径 (来自源码分析)
-- ══════════════════════════════════════════════════════════════════
local GameRoot = Workspace:WaitForChild("Game", 10)
local WorkspacePlayers = GameRoot and GameRoot:WaitForChild("Players", 10) or nil
local GameMap = GameRoot and GameRoot:FindFirstChild("Map") or nil
local GameEffects = GameRoot and GameRoot:FindFirstChild("Effects") or nil
local GameSettings = GameRoot and GameRoot:FindFirstChild("Settings") or nil
local TicketsFolder = GameEffects and GameEffects:FindFirstChild("Tickets") or nil
local EventsFolder = ReplicatedStorage:FindFirstChild("Events") or nil

-- 事件引用
local ChangePlayerMode = EventsFolder and EventsFolder:FindFirstChild("Player")
    and EventsFolder.Player:FindFirstChild("ChangePlayerMode") or nil
local CharacterInteract = EventsFolder and EventsFolder:FindFirstChild("Character")
    and EventsFolder.Character:FindFirstChild("Interact") or nil

-- ══════════════════════════════════════════════════════════════════
-- 4. SETTINGS
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- Character
    EV_AutoRespawn = false,
    EV_InstantRevive = false,
    EV_InstantCarry = false,
    EV_AutoRevive = false,
    EV_FastRevive = false,
    EV_ReviveTime = 2.2,

    -- Farm
    EV_MoneyFarm = false,
    EV_AFKFarm = false,
    EV_TicketFarm = false,

    -- Movement
    EV_SpeedBoost = false,
    EV_Speed = 2,
    EV_Fly = false,
    EV_FlySpeed = 80,
    EV_NoClip = false,

    -- Visual
    ESP_Nextbot = false,
    ESP_NextbotColor = Color3.fromRGB(255, 50, 50),
    ESP_Player = false,
    ESP_PlayerColor = Color3.fromRGB(255, 170, 0),
    ESP_Downed = false,
    ESP_DownedColor = Color3.fromRGB(255, 0, 0),
    ESP_Ticket = false,
    ESP_TicketColor = Color3.fromRGB(41, 180, 255),
    ESP_Distance = true,
    ESP_Refresh = 0.1,
    EV_Fullbright = false,

    -- Misc
    EV_AntiAFK = false,
}

-- ══════════════════════════════════════════════════════════════════
-- 5. 全局变量
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false
local noclipConn = nil
local flyConn = nil
local flyBV = nil
local flyBG = nil
local speedConn = nil
local espConn = nil
local espFolder = nil
local farmConn = nil
local reviveConn = nil
local carryConn = nil
local autoReviveConn = nil
local autoRespawnConn = nil
local savedLighting = {}

-- ══════════════════════════════════════════════════════════════════
-- 6. 通知辅助函数
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
-- 7. 工具函数
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

-- 来自源码: 查找AI (Nextbot)
local function findAI()
    if not WorkspacePlayers then return nil end
    for _, v in pairs(WorkspacePlayers:GetChildren()) do
        if not Players:GetPlayerFromCharacter(v) then
            return v
        end
    end
    return nil
end

-- 来自源码: 查找所有AI
local function findAllAI()
    local result = {}
    if not WorkspacePlayers then return result end
    for _, v in pairs(WorkspacePlayers:GetChildren()) do
        if not Players:GetPlayerFromCharacter(v) and v:IsA("Model") then
            table.insert(result, v)
        end
    end
    return result
end

-- 来自源码: 查找倒地玩家
local function getDownedPlr()
    if not WorkspacePlayers then return nil end
    for _, v in pairs(WorkspacePlayers:GetChildren()) do
        if v:GetAttribute("Downed") then
            return v
        end
    end
    return nil
end

-- 来自源码: 查找所有倒地玩家
local function getAllDownedPlrs()
    local result = {}
    if not WorkspacePlayers then return result end
    for _, v in pairs(WorkspacePlayers:GetChildren()) do
        if v:GetAttribute("Downed") and Players:GetPlayerFromCharacter(v) then
            table.insert(result, v)
        end
    end
    return result
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 角色功能 (来自源码还原)
-- ══════════════════════════════════════════════════════════════════

-- 重生 (来自源码: ChangePlayerMode:FireServer(true))
local function respawn()
    if ChangePlayerMode then
        pcall(function() ChangePlayerMode:FireServer(true) end)
    else
        pcall(function() LocalPlayer:LoadCharacter() end)
    end
end

-- 自动重生 (来自源码: 检查 Downed 属性)
local function toggleAutoRespawn(enabled)
    if autoRespawnConn then
        autoRespawnConn:Disconnect()
        autoRespawnConn = nil
    end
    if enabled then
        autoRespawnConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local char = LocalPlayer.Character
            if char and char:GetAttribute("Downed") then
                respawn()
                task.wait(2)
            end
        end)
    end
end

-- 即时复活 (来自源码: Interact:FireServer("Revive", true, name))
local function toggleInstantRevive(enabled)
    if reviveConn then
        reviveConn:Disconnect()
        reviveConn = nil
    end
    if enabled then
        reviveConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            if not myRoot then return end
            for _, v in ipairs(Players:GetPlayers()) do
                if v ~= LocalPlayer and v.Character then
                    local hum = v.Character:FindFirstChildOfClass("Humanoid")
                    local vRoot = v.Character:FindFirstChild("HumanoidRootPart")
                    if hum and vRoot and hum.Health <= 0 then
                        local dist = (myRoot.Position - vRoot.Position).Magnitude
                        if dist <= 15 then
                            if CharacterInteract then
                                pcall(function()
                                    CharacterInteract:FireServer("Revive", true, v.Name)
                                end)
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- 即时搬运 (来自源码: Interact:FireServer("Carry", true, name))
local function toggleInstantCarry(enabled)
    if carryConn then
        carryConn:Disconnect()
        carryConn = nil
    end
    if enabled then
        carryConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            if not myRoot then return end
            for _, v in ipairs(Players:GetPlayers()) do
                if v ~= LocalPlayer and v.Character then
                    local hum = v.Character:FindFirstChildOfClass("Humanoid")
                    local vRoot = v.Character:FindFirstChild("HumanoidRootPart")
                    if hum and vRoot and hum.Health <= 0 then
                        local dist = (myRoot.Position - vRoot.Position).Magnitude
                        if dist <= 15 then
                            if CharacterInteract then
                                pcall(function()
                                    CharacterInteract:FireServer("Carry", true, v.Name)
                                end)
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- 自动复活 (来自源码: 传送到倒地玩家旁并复活)
local function toggleAutoRevive(enabled)
    if autoReviveConn then
        autoReviveConn:Disconnect()
        autoReviveConn = nil
    end
    if enabled then
        autoReviveConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local myRoot = getRoot()
            if not myRoot then return end
            for _, v in ipairs(Players:GetPlayers()) do
                if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                    local hum = v.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health <= 0 then
                        local vRoot = v.Character.HumanoidRootPart
                        -- 传送到倒地玩家上方
                        pcall(function()
                            myRoot.CFrame = CFrame.new(vRoot.Position + Vector3.new(0, 3, 0))
                        end)
                        -- 快速复活: 修改复活时间
                        if GameSettings and SETTINGS.EV_FastRevive then
                            pcall(function() GameSettings:SetAttribute("ReviveTime", SETTINGS.EV_ReviveTime) end)
                        end
                        -- 触发复活
                        if CharacterInteract then
                            pcall(function()
                                CharacterInteract:FireServer("Revive", true, v.Name)
                            end)
                        end
                    end
                end
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 农场功能 (来自源码还原)
-- ══════════════════════════════════════════════════════════════════
local function toggleFarm(enabled)
    if farmConn then
        farmConn:Disconnect()
        farmConn = nil
    end
    if not enabled then return end

    farmConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end

        -- Ticket Farm (来自源码: 传送到票券位置)
        if SETTINGS.EV_TicketFarm then
            if LocalPlayer:GetAttribute("InMenu") ~= true and LocalPlayer:GetAttribute("Dead") ~= true then
                if TicketsFolder then
                    for _, ticket in pairs(TicketsFolder:GetChildren()) do
                        local tRoot = ticket:FindFirstChild("HumanoidRootPart") or ticket:FindFirstChildOfClass("BasePart")
                        if tRoot and getRoot() then
                            pcall(function()
                                getRoot().CFrame = CFrame.new(tRoot.Position)
                            end)
                            task.wait(0.1)
                        end
                    end
                end
            else
                task.wait(2)
                respawn()
            end
            -- 倒地时自动重生
            local char = LocalPlayer.Character
            if char and char:GetAttribute("Downed") then
                respawn()
                task.wait(2)
            end
        end

        -- Money Farm (来自源码: 复活倒地玩家获取Token)
        if SETTINGS.EV_MoneyFarm then
            if LocalPlayer:GetAttribute("InMenu") and LocalPlayer:GetAttribute("Dead") ~= true then
                respawn()
            end
            local char = LocalPlayer.Character
            if char and char:GetAttribute("Downed") then
                respawn()
                task.wait(3)
            else
                -- 自动复活倒地玩家
                local downed = getDownedPlr()
                if downed and downed:FindFirstChild("HumanoidRootPart") and getRoot() then
                    pcall(function()
                        if GameSettings and SETTINGS.EV_FastRevive then
                            GameSettings:SetAttribute("ReviveTime", SETTINGS.EV_ReviveTime)
                        end
                        getRoot().CFrame = CFrame.new(downed.HumanoidRootPart.Position + Vector3.new(0, 3, 0))
                    end)
                    if CharacterInteract then
                        pcall(function()
                            CharacterInteract:FireServer("Revive", true, tostring(downed))
                        end)
                    end
                    task.wait(1)
                end
            end
        end

        -- AFK Farm (来自源码: 传送到地图外安全点)
        if SETTINGS.EV_AFKFarm then
            local root = getRoot()
            if root then
                pcall(function()
                    root.CFrame = CFrame.new(6007, 7005, 8005)
                end)
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 移动功能 (来自源码还原)
-- ══════════════════════════════════════════════════════════════════

-- CFrame Speed Boost (来自源码: 使用 MoveDirection 移动)
local function toggleSpeedBoost(enabled)
    if speedConn then
        speedConn:Disconnect()
        speedConn = nil
    end
    if enabled then
        speedConn = RunService.Stepped:Connect(function()
            if isDestroyed then return end
            local char = LocalPlayer.Character
            if not char then return end
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local rootPart = char:FindFirstChild("HumanoidRootPart")
            if not humanoid or not rootPart then return end
            local moveDirection = humanoid.MoveDirection
            if moveDirection.Magnitude > 0 then
                local speed = SETTINGS.EV_Speed or 2
                local newPosition = rootPart.Position + moveDirection * speed
                rootPart.CFrame = CFrame.new(newPosition, newPosition + moveDirection)
            end
        end)
    end
end

-- NoClip
local function toggleNoclip(enabled)
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    if enabled then
        noclipConn = RunService.Stepped:Connect(function()
            if isDestroyed then return end
            local char = LocalPlayer.Character
            if not char then return end
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end)
    end
end

-- Fly
local function toggleFly(enabled, speed)
    if flyConn then
        flyConn:Disconnect()
        flyConn = nil
    end
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
            local spd = speed or SETTINGS.EV_FlySpeed or 80
            if move.Magnitude > 0 then move = move.Unit * spd end
            flyBV.Velocity = move
            if root then
                flyBG.CFrame = CFrame.new(root.Position) * cam.CFrame.Rotation
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 11. ESP 功能 (来自源码还原)
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end
end

local function createHighlight(parent, color)
    local hl = Instance.new("Highlight")
    hl.Name = "EvadeESP_HL"
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
    bb.Name = "EvadeESP_BB"
    bb.Size = UDim2.new(0, 200, 0, 30)
    bb.StudsOffset = Vector3.new(0, yOffset or 3, 0)
    bb.AlwaysOnTop = true

    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.BackgroundTransparency = 1
    tl.Text = text
    tl.TextColor3 = color
    tl.TextStrokeTransparency = 0.3
    tl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14
    tl.Parent = bb

    bb.Parent = parent
    return bb
end

local function runESPLoop()
    if not espFolder then
        espFolder = Instance.new("Folder")
        espFolder.Name = "EvadeESP_Folder"
        espFolder.Parent = CoreGui
    end

    local myRoot = getRoot()

    -- 清理旧标记
    local function cleanObj(obj)
        pcall(function()
            for _, c in ipairs(obj:GetChildren()) do
                if c.Name == "EvadeESP_HL" or c.Name == "EvadeESP_BB" then
                    c:Destroy()
                end
            end
        end)
    end

    -- Nextbot ESP (来自源码: WorkspacePlayers 中非玩家角色即为AI)
    if SETTINGS.ESP_Nextbot and WorkspacePlayers then
        for _, obj in pairs(WorkspacePlayers:GetChildren()) do
            if not Players:GetPlayerFromCharacter(obj) and obj:IsA("Model") then
                cleanObj(obj)
                local distText = ""
                local objRoot = obj:FindFirstChild("HumanoidRootPart")
                if myRoot and objRoot then
                    local dist = (myRoot.Position - objRoot.Position).Magnitude
                    distText = string.format(" [%dm]", math.floor(dist))
                end
                pcall(function() createHighlight(obj, SETTINGS.ESP_NextbotColor) end)
                if SETTINGS.ESP_Distance then
                    pcall(function() createBillboard(obj, "[AI] " .. obj.Name .. distText, SETTINGS.ESP_NextbotColor, 4) end)
                else
                    pcall(function() createBillboard(obj, "[AI] " .. obj.Name, SETTINGS.ESP_NextbotColor, 4) end)
                end
            end
        end
    end

    -- Player ESP + Downed ESP (来自源码: 玩家ESP + Downed属性检测)
    if SETTINGS.ESP_Player or SETTINGS.ESP_Downed then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local char = p.Character
                cleanObj(char)
                local isDowned = char:GetAttribute("Downed")
                local color = SETTINGS.ESP_PlayerColor
                local prefix = ""

                -- 来自源码: Downed玩家使用特殊颜色
                if isDowned and SETTINGS.ESP_Downed then
                    color = SETTINGS.ESP_DownedColor
                    prefix = "[DOWNED] "
                elseif not SETTINGS.ESP_Player then
                    continue  -- 不显示普通玩家
                end

                local distText = ""
                local pRoot = char:FindFirstChild("HumanoidRootPart")
                if myRoot and pRoot then
                    local dist = (myRoot.Position - pRoot.Position).Magnitude
                    distText = string.format(" [%dm]", math.floor(dist))
                end
                pcall(function() createHighlight(char, color) end)
                local name = prefix .. p.Name
                if SETTINGS.ESP_Distance then name = name .. distText end
                pcall(function() createBillboard(char, name, color, 4) end)
            end
        end
    end

    -- Ticket ESP (来自源码: workspace.Game.Effects.Tickets)
    if SETTINGS.ESP_Ticket and TicketsFolder then
        for _, ticket in pairs(TicketsFolder:GetChildren()) do
            cleanObj(ticket)
            local distText = ""
            local tRoot = ticket:FindFirstChild("HumanoidRootPart") or ticket:FindFirstChildOfClass("BasePart")
            if myRoot and tRoot then
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                distText = string.format(" [%dm]", math.floor(dist))
            end
            pcall(function() createHighlight(ticket, SETTINGS.ESP_TicketColor) end)
            local name = "Ticket"
            if SETTINGS.ESP_Distance then name = name .. distText end
            pcall(function() createBillboard(ticket, name, SETTINGS.ESP_TicketColor, 3) end)
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
-- 12. 视觉功能 (来自源码还原)
-- ══════════════════════════════════════════════════════════════════

-- Full Bright (来自源码: Lighting 修改)
local function toggleFullbright(enabled)
    if enabled then
        if not savedLighting.brightness then
            savedLighting.brightness = Lighting.Brightness
            savedLighting.fogEnd = Lighting.FogEnd
            savedLighting.globalShadows = Lighting.GlobalShadows
            savedLighting.clockTime = Lighting.ClockTime
        end
        Lighting.Brightness = 4
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.ClockTime = 12
    else
        Lighting.Brightness = savedLighting.brightness or 1
        Lighting.FogEnd = savedLighting.fogEnd or 500
        Lighting.GlobalShadows = savedLighting.globalShadows ~= nil and savedLighting.globalShadows or true
        Lighting.ClockTime = savedLighting.clockTime or 14
    end
end

-- Remove Barriers (来自源码: workspace.Game.Map.InvisParts:ClearAllChildren())
local function removeBarriers()
    if GameMap then
        local invisParts = GameMap:FindFirstChild("InvisParts")
        if invisParts then
            pcall(function() invisParts:ClearAllChildren() end)
            notify("Evade", "已移除隐形障碍", 2, "Success")
        else
            notify("Evade", "未找到 InvisParts", 2, "Warning")
        end
    end
end

-- Remove KillBricks (来自源码: workspace.Game.Map.Parts.KillBricks:Destroy())
local function removeKillBricks()
    if GameMap then
        local parts = GameMap:FindFirstChild("Parts") or GameMap:FindFirstChild("KillBricks")
        local killBricks = parts and parts:FindFirstChild("KillBricks") or GameMap:FindFirstChild("KillBricks")
        if killBricks then
            pcall(function() killBricks:Destroy() end)
            notify("Evade", "已移除 KillBricks", 2, "Success")
        else
            notify("Evade", "未找到 KillBricks", 2, "Warning")
        end
    end
end

-- Rejoin (来自源码: TeleportService)
local function rejoin()
    local placeId = game.PlaceId
    local jobId = game.JobId
    if #Players:GetPlayers() <= 1 then
        pcall(function() LocalPlayer:Kick("\nRejoining...") end)
        task.wait(1)
        TeleportService:Teleport(placeId, LocalPlayer)
    else
        TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
    end
end

-- Anti-AFK (来自源码: getconnections 方法)
local function setupAntiAFK()
    local GC = getconnections or get_signal_cons
    if GC then
        for _, v in pairs(GC(LocalPlayer.Idled)) do
            if v["Disable"] then
                v["Disable"](v)
            elseif v["Disconnect"] then
                v["Disconnect"](v)
            end
        end
    else
        LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 13. 创建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title      = "Evade",
    Subtitle   = "Nextbot 逃生 v2.0",
    ThemeColor = Color3.fromRGB(180, 60, 255),
    Transparency = 0.3,
    Size       = UDim2.new(0, 640, 0, 560),
    Keybind    = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: 角色 ──
local CharTab = Window:AddTab({
    Name = "角色",
    Icon = "rbxassetid://6034287594",
})

CharTab:AddSection({ Name = "重生" })

CharTab:AddToggle({
    Name     = "自动重生 (倒地立即重生)",
    Default  = false,
    Flag     = "EV_AutoRespawn",
    Callback = function(s)
        SETTINGS.EV_AutoRespawn = s
        toggleAutoRespawn(s)
        notify("Evade", s and "自动重生 已开启" or "自动重生 已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddButton({
    Name = "立即重生",
    Callback = function()
        respawn()
        notify("Evade", "已触发重生", 2, "Info")
    end,
})

CharTab:AddSection({ Name = "复活 / 搬运" })

CharTab:AddToggle({
    Name     = "即时复活 (靠近倒地玩家自动复活)",
    Default  = false,
    Flag     = "EV_InstantRevive",
    Callback = function(s)
        SETTINGS.EV_InstantRevive = s
        toggleInstantRevive(s)
        notify("Evade", s and "即时复活 已开启" or "即时复活 已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddToggle({
    Name     = "即时搬运 (靠近倒地玩家自动搬运)",
    Default  = false,
    Flag     = "EV_InstantCarry",
    Callback = function(s)
        SETTINGS.EV_InstantCarry = s
        toggleInstantCarry(s)
        notify("Evade", s and "即时搬运 已开启" or "即时搬运 已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddToggle({
    Name     = "自动复活 (传送+复活所有倒地玩家)",
    Default  = false,
    Flag     = "EV_AutoRevive",
    Callback = function(s)
        SETTINGS.EV_AutoRevive = s
        toggleAutoRevive(s)
        notify("Evade", s and "自动复活 已开启" or "自动复活 已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddSection({ Name = "快速复活" })

CharTab:AddToggle({
    Name     = "快速复活 (修改复活时间)",
    Default  = false,
    Flag     = "EV_FastRevive",
    Callback = function(s)
        SETTINGS.EV_FastRevive = s
        if s and GameSettings then
            pcall(function() GameSettings:SetAttribute("ReviveTime", SETTINGS.EV_ReviveTime) end)
            notify("Evade", "复活时间已设为 " .. tostring(SETTINGS.EV_ReviveTime) .. "s", 2, "Success")
        end
    end,
})

CharTab:AddSlider({
    Name      = "复活时间",
    Min       = 0.1, Max = 10, Default = 2.2, Increment = 0.1,
    Suffix    = "s",
    Flag      = "EV_ReviveTime",
    Callback  = function(v)
        SETTINGS.EV_ReviveTime = v
        if SETTINGS.EV_FastRevive and GameSettings then
            pcall(function() GameSettings:SetAttribute("ReviveTime", v) end)
        end
    end,
})

-- ── TAB 2: 农场 ──
local FarmTab = Window:AddTab({
    Name = "农场",
    Icon = "rbxassetid://6031280882",
})

FarmTab:AddSection({ Name = "自动农场" })

FarmTab:AddToggle({
    Name     = "Money Farm (刷钱: 复活玩家获取Token)",
    Default  = false,
    Flag     = "EV_MoneyFarm",
    Callback = function(s)
        SETTINGS.EV_MoneyFarm = s
        toggleFarm(s or SETTINGS.EV_AFKFarm or SETTINGS.EV_TicketFarm)
        notify("Evade", s and "Money Farm 已开启" or "Money Farm 已关闭", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddToggle({
    Name     = "AFK Farm (挂机: 传送到安全点)",
    Default  = false,
    Flag     = "EV_AFKFarm",
    Callback = function(s)
        SETTINGS.EV_AFKFarm = s
        toggleFarm(s or SETTINGS.EV_MoneyFarm or SETTINGS.EV_TicketFarm)
        notify("Evade", s and "AFK Farm 已开启" or "AFK Farm 已关闭", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddToggle({
    Name     = "Ticket Farm (刷票券: 自动拾取)",
    Default  = false,
    Flag     = "EV_TicketFarm",
    Callback = function(s)
        SETTINGS.EV_TicketFarm = s
        toggleFarm(s or SETTINGS.EV_MoneyFarm or SETTINGS.EV_AFKFarm)
        notify("Evade", s and "Ticket Farm 已开启" or "Ticket Farm 已关闭", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddSection({ Name = "统计" })

local tokenLabel = FarmTab:AddLabel({ Text = "Tokens: 0" })
local ticketLabel = FarmTab:AddLabel({ Text = "Tickets: 0" })

task.spawn(function()
    while not isDestroyed do
        pcall(function()
            local tokens = LocalPlayer:GetAttribute("Tokens") or 0
            local tickets = LocalPlayer:GetAttribute("Tickets") or 0
            if tokenLabel then tokenLabel:SetText("Tokens: " .. tostring(tokens)) end
            if ticketLabel then ticketLabel:SetText("Tickets: " .. tostring(tickets)) end
        end)
        task.wait(1)
    end
end)

-- ── TAB 3: 移动 ──
local MoveTab = Window:AddTab({
    Name = "移动",
    Icon = "rbxassetid://6034466796",
})

MoveTab:AddSection({ Name = "CFrame Speed Boost (源码还原)" })

MoveTab:AddToggle({
    Name     = "Speed Boost (CFrame 加速)",
    Default  = false,
    Flag     = "EV_SpeedBoost",
    Callback = function(s)
        SETTINGS.EV_SpeedBoost = s
        toggleSpeedBoost(s)
        notify("Evade", s and "Speed Boost 已开启" or "Speed Boost 已关闭", 2, s and "Success" or "Info")
    end,
})

MoveTab:AddSlider({
    Name      = "Speed 值",
    Min       = 1, Max = 100, Default = 2, Increment = 1,
    Flag      = "EV_Speed",
    Callback  = function(v) SETTINGS.EV_Speed = v end,
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
    Name     = "Fly (飞行 WASD+Space/Ctrl)",
    Default  = false,
    Flag     = "EV_Fly",
    Callback = function(s)
        SETTINGS.EV_Fly = s
        toggleFly(s, SETTINGS.EV_FlySpeed)
    end,
})

MoveTab:AddSlider({
    Name      = "Fly Speed",
    Min       = 10, Max = 300, Default = 80, Increment = 5,
    Flag      = "EV_FlySpeed",
    Callback  = function(v)
        SETTINGS.EV_FlySpeed = v
        if SETTINGS.EV_Fly then toggleFly(true, v) end
    end,
})

-- ── TAB 4: 视觉 ──
local VisualTab = Window:AddTab({
    Name = "视觉",
    Icon = "rbxassetid://6035153470",
})

VisualTab:AddSection({ Name = "ESP (源码还原)" })

VisualTab:AddToggle({
    Name     = "Nextbot ESP (AI 红色高亮)",
    Default  = false,
    Flag     = "EV_ESPNextbot",
    Callback = function(s)
        SETTINGS.ESP_Nextbot = s
        if s then toggleESP(true) else
            if not (SETTINGS.ESP_Player or SETTINGS.ESP_Downed or SETTINGS.ESP_Ticket) then
                toggleESP(false)
            end
        end
    end,
})

VisualTab:AddColorPicker({
    Name     = "Nextbot 颜色",
    Default  = Color3.fromRGB(255, 50, 50),
    Flag     = "EV_NextbotColor",
    Callback  = function(c) SETTINGS.ESP_NextbotColor = c end,
})

VisualTab:AddToggle({
    Name     = "玩家 ESP (橙色高亮)",
    Default  = false,
    Flag     = "EV_ESPPlayer",
    Callback = function(s)
        SETTINGS.ESP_Player = s
        if s then toggleESP(true) else
            if not (SETTINGS.ESP_Nextbot or SETTINGS.ESP_Downed or SETTINGS.ESP_Ticket) then
                toggleESP(false)
            end
        end
    end,
})

VisualTab:AddColorPicker({
    Name     = "玩家 颜色",
    Default  = Color3.fromRGB(255, 170, 0),
    Flag     = "EV_PlayerColor",
    Callback  = function(c) SETTINGS.ESP_PlayerColor = c end,
})

VisualTab:AddToggle({
    Name     = "倒地玩家 ESP (红色高亮)",
    Default  = false,
    Flag     = "EV_ESPDowned",
    Callback = function(s)
        SETTINGS.ESP_Downed = s
        if s then toggleESP(true) else
            if not (SETTINGS.ESP_Nextbot or SETTINGS.ESP_Player or SETTINGS.ESP_Ticket) then
                toggleESP(false)
            end
        end
    end,
})

VisualTab:AddColorPicker({
    Name     = "倒地玩家 颜色",
    Default  = Color3.fromRGB(255, 0, 0),
    Flag     = "EV_DownedColor",
    Callback  = function(c) SETTINGS.ESP_DownedColor = c end,
})

VisualTab:AddToggle({
    Name     = "票券 ESP (蓝色高亮)",
    Default  = false,
    Flag     = "EV_ESPTicket",
    Callback = function(s)
        SETTINGS.ESP_Ticket = s
        if s then toggleESP(true) else
            if not (SETTINGS.ESP_Nextbot or SETTINGS.ESP_Player or SETTINGS.ESP_Downed) then
                toggleESP(false)
            end
        end
    end,
})

VisualTab:AddColorPicker({
    Name     = "票券 颜色",
    Default  = Color3.fromRGB(41, 180, 255),
    Flag     = "EV_TicketColor",
    Callback  = function(c) SETTINGS.ESP_TicketColor = c end,
})

VisualTab:AddToggle({
    Name     = "显示距离",
    Default  = true,
    Flag     = "EV_ESPDistance",
    Callback = function(s) SETTINGS.ESP_Distance = s end,
})

VisualTab:AddButton({
    Name = "清除所有 ESP",
    Callback = function()
        clearESP()
        notify("Evade", "已清除 ESP", 2, "Info")
    end,
})

VisualTab:AddSection({ Name = "世界" })

VisualTab:AddToggle({
    Name     = "全亮 (Fullbright)",
    Default  = false,
    Flag     = "EV_Fullbright",
    Callback = function(s)
        SETTINGS.EV_Fullbright = s
        toggleFullbright(s)
    end,
})

VisualTab:AddButton({
    Name = "移除隐形障碍 (Remove Barriers)",
    Callback = function() removeBarriers() end,
})

VisualTab:AddButton({
    Name = "移除击杀砖块 (Remove KillBricks)",
    Callback = function() removeKillBricks() end,
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
        notify("Evade", "正在重新加入...", 2, "Info")
        rejoin()
    end,
})

ServerTab:AddButton({
    Name = "服务器跳转 (Server Hop)",
    Callback = function()
        notify("Evade", "正在跳转服务器...", 2, "Info")
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
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
    Flag     = "EV_AntiAFK",
    Callback = function(s)
        SETTINGS.EV_AntiAFK = s
        if s then setupAntiAFK() end
        notify("Evade", s and "Anti-AFK 已开启" or "Anti-AFK 已关闭", 2, s and "Success" or "Info")
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
                notify("Evade", "已复制: " .. s, 2, "Success")
            else
                notify("Evade", "执行器不支持剪贴板", 2, "Error")
            end
        end
    end,
})

MiscTab:AddSection({ Name = "信息" })

MiscTab:AddParagraph({
    Title   = "Evade 辅助 v2.0",
    Content = table.concat({
        "基于真实源码还原 (VanillaSourceCode + NoobHubV4)",
        "",
        "游戏路径:",
        "  workspace.Game.Players — 玩家+AI",
        "  workspace.Game.Map.InvisParts — 障碍",
        "  workspace.Game.Map.Parts.KillBricks — 击杀砖",
        "  workspace.Game.Effects.Tickets — 票券",
        "  ReplicatedStorage.Events.Player.ChangePlayerMode — 重生",
        "  ReplicatedStorage.Events.Character.Interact — 复活/搬运",
        "",
        "功能:",
        "  • 自动重生 (Downed属性检测 + ChangePlayerMode)",
        "  • 即时复活/搬运 (Interact Revive/Carry)",
        "  • 自动复活 (传送+复活倒地玩家)",
        "  • 快速复活 (修改 ReviveTime 属性)",
        "  • Money/AFK/Ticket Farm (源码逻辑)",
        "  • CFrame Speed Boost (MoveDirection加速)",
        "  • NoClip + Fly",
        "  • Nextbot/玩家/倒地/票券 ESP",
        "  • 全亮 + 移除障碍 + 移除KillBricks",
        "  • Rejoin + Anti-AFK",
        "",
        "快捷键: RightShift 隐藏/显示 UI",
    }, "\n"),
})

-- ── 快捷键 ──
local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.T then
        -- T: 重生
        respawn()
        notify("T 快捷键", "→ 重生", 1.5, "Info")
    elseif input.KeyCode == Enum.KeyCode.Y then
        -- Y: 切换 NoClip
        local newState = not SETTINGS.EV_NoClip
        SETTINGS.EV_NoClip = newState
        toggleNoclip(newState)
        notify("Y 快捷键", newState and "NoClip ON" or "NoClip OFF", 1.5, "Info")
    elseif input.KeyCode == Enum.KeyCode.U then
        -- U: 切换 Fly
        local newState = not SETTINGS.EV_Fly
        SETTINGS.EV_Fly = newState
        toggleFly(newState, SETTINGS.EV_FlySpeed)
        notify("U 快捷键", newState and "Fly ON" or "Fly OFF", 1.5, "Info")
    end
end)

-- 角色重生时恢复设置
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if isDestroyed then return end
    if SETTINGS.EV_NoClip then toggleNoclip(true) end
    if SETTINGS.EV_Fly then toggleFly(true, SETTINGS.EV_FlySpeed) end
    if SETTINGS.EV_SpeedBoost then toggleSpeedBoost(true) end
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
    if flyConn then flyConn:Disconnect() end
    if speedConn then speedConn:Disconnect() end
    if espConn then espConn:Disconnect() end
    if farmConn then farmConn:Disconnect() end
    if reviveConn then reviveConn:Disconnect() end
    if carryConn then carryConn:Disconnect() end
    if autoReviveConn then autoReviveConn:Disconnect() end
    if autoRespawnConn then autoRespawnConn:Disconnect() end

    if flyBV then flyBV:Destroy() end
    if flyBG then flyBG:Destroy() end

    clearESP()
    toggleFullbright(false)

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Evade", Text = "脚本已卸载", Duration = 2
        })
    end)
end

_G.Evade_Cleanup = cleanup

-- ── 完成通知 ──
task.wait(0.5)
notify("Evade v2.0", "Evade 辅助已加载\n基于真实源码还原\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[Evade] v2.0 (PlaceId: %d) 辅助加载完成 — 基于真实源码还原", game.PlaceId))
