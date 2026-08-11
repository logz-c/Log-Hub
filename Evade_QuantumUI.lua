--[[
    Evade 辅助脚本 v2.0 (Quantum UI 版)  ——  基于真实 Evade 源码重写
    ============================================================
    适配 PlaceId:  9872472334
    GameId (Universe): 11818772280
    参考源码:
        • VanillaSourceCode/evade  main.lua   (Nextbot位置/Ticket路径/复活Remote/Speed逻辑/MoneyFarm逻辑)
        • NoobHubV4/RobloxScripts/Evade      (HUD死亡监听/原地复活/Instant Revive+Carry)

    Evade 真实游戏结构 (从上述源码提取):
        Nextbots / AI 存放:   workspace.Game.Players   (不是 workspace.Nextbots !)
        玩家倒下属性:         Character:GetAttribute("Downed")
        InMenu属性:           LocalPlayer:GetAttribute("InMenu")
        Dead属性:             LocalPlayer:GetAttribute("Dead")
        Tickets 位置:         workspace.Game.Effects.Tickets
        隐形障碍物:           workspace.Game.Map.InvisParts
        复活设置:             workspace.Game.Settings:SetAttribute("ReviveTime", 2.2)

        复活 Remote:          ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true)
        复活队友 Remote:      ReplicatedStorage.Events.Character.Interact:FireServer("Revive",  true, PlayerName)
        扛起队友 Remote:      ReplicatedStorage.Events.Character.Interact:FireServer("Carry",   true, PlayerName)
        HUD 死亡监听:         PlayerGui.Shared.HUD.Visible == false

    快捷键:
        RightShift  - 隐藏/显示 UI
        T           - Rejoin (重进当前服务器)
        Y           - 切换 NoClip
        U           - 切换 Fly
        R           - 一键复活 (ChangePlayerMode)

    安全承诺:  不采集任何信息，不 loadstring 外部功能代码，所有逻辑本地实现。
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
    warn("[Evade v2] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[Evade v2] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[Evade v2] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[Evade v2] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

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
local TeleportService = game:GetService("TeleportService")

-- ══════════════════════════════════════════════════════════════════
-- 3. Evade 专用路径 & SETTINGS (真实游戏结构)
-- ══════════════════════════════════════════════════════════════════
-- 来自真实源码:
--   Nextbots / AI 位于    Workspace.Game.Players
--   Tickets 位于          Workspace.Game.Effects.Tickets
--   InvisParts 位于       Workspace.Game.Map.InvisParts
--   Revive 设置位于       Workspace.Game.Settings
local function getWorkspaceGame()
    return Workspace:FindFirstChild("Game")
end

local SETTINGS = {
    -- Character / 复活相关
    EV_AutoRespawn = false,         -- 自己倒下立即复活 (ChangePlayerMode)
    EV_SavePosOnRespawn = true,     -- 复活时保留原位置/相机 (源码方法)
    EV_InstantRevive = false,       -- 范围内立即复活队友
    EV_InstantCarry = false,        -- 范围内立即扛起队友
    EV_AutoRevive = false,          -- 自动瞬移到倒下队友+复活 (MoneyFarm核心)
    EV_InstantRange = 15,           -- InstantRevive/Carry 距离 (源码默认15)

    -- Farm
    EV_MoneyFarm = false,           -- 自动复活附近倒下玩家 → 赚Tokens (源码moneyfarm)
    EV_TicketFarm = false,          -- 自动收集Tickets (源码TicketFarm)
    EV_AFKFarm = false,             -- 传送到地图外安全坐标 (源码afkfarm: 6007,7005,8005)
    EV_ReviveTimeBoost = false,     -- 改 ReviveTime=2.2 加速复活
    EV_MoneyFarmDelay = 1,          -- Money Farm 间隔 (源码1秒)

    -- ESP
    ESPEnabled = false,
    ESP_Bot = false,                -- Nextbot/AI (红色)  Workspace.Game.Players 中不是玩家的
    ESP_BotColor = Color3.fromRGB(255, 50, 50),
    ESP_Player = false,             -- 普通玩家 (橙色)
    ESP_PlayerColor = Color3.fromRGB(255, 170, 0),
    ESP_Downed = false,             -- 倒下的玩家 (白色高亮区分)
    ESP_DownedColor = Color3.fromRGB(255, 255, 255),
    ESP_Ticket = false,             -- Tickets (蓝色)  workspace.Game.Effects.Tickets
    ESP_TicketColor = Color3.fromRGB(41, 180, 255),
    ESP_Name = true,
    ESP_Distance = true,
    ESP_Box = false,
    ESP_Refresh = 0.1,

    -- Movement
    EV_SpeedBoost = false,          -- 源码方式: moveDirection*Speed 直接改CFrame (不会被游戏重置WalkSpeed)
    EV_SpeedValue = 2,              -- 源码默认 2, 范围 2~500
    EV_WalkSpeed = false,           -- 备用 (传统改Humanoid.WalkSpeed)
    EV_WalkSpeedValue = 16,
    EV_JumpPower = false,
    EV_JumpPowerValue = 50,
    EV_InfJump = false,
    EV_NoClip = false,
    EV_Fly = false,
    EV_FlySpeed = 80,
    EV_LowGravity = false,
    EV_GravityValue = 50,

    -- Visual / World
    EV_Fullbright = false,
    EV_FOV = false,
    EV_FOVValue = 90,
    EV_RemoveBarriers = false,      -- 清除 InvisParts
    EV_NoCameraShake = false,

    -- Misc
    EV_AntiAFK = true,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 全局变量 / 复活位置保存 (来自NoobHubV4源码)
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
local speedConn = nil
local farmConn = nil
local ticketConn = nil
local autoRespawnConn = nil
local downedAttrConn = nil

local SavedPositions = {
    AutoRe = nil,       -- 倒下前角色CFrame (原地复活)
    OldCameraPos = nil, -- 倒下前相机CFrame
}
local autoRespawnSent = false  -- 防止重复触发

-- 统计
local FarmStats = {
    TicketFarm = { earned = nil, duration = 0 },
    TokenFarm  = { earned = nil, duration = 0 },
}
local baseTokens = nil  -- Tokens基准，用于赚差值

-- 保存Fullbright前的Lighting
local savedLighting = { Brightness=nil, FogEnd=nil, ClockTime=nil, GlobalShadows=nil }

-- ══════════════════════════════════════════════════════════════════
-- 5. 通知辅助函数
-- ══════════════════════════════════════════════════════════════════
local function notify(title, content, duration, ntype)
    if Window then
        Window:Notify({ Title = title, Content = content, Duration = duration or 3, Type = ntype or "Info" })
    else
        pcall(function()
            StarterGui:SetCore("SendNotification", { Title = title, Text = content, Duration = duration or 3 })
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 6. Evade 专用 Remote 包装 (来自真实源码)
-- ══════════════════════════════════════════════════════════════════
local Events = ReplicatedStorage:FindFirstChild("Events")
local PlayerEvents = Events and Events:FindFirstChild("Player")
local CharacterEvents = Events and Events:FindFirstChild("Character")
local ChangePlayerMode = PlayerEvents and PlayerEvents:FindFirstChild("ChangePlayerMode")
local InteractEvent = CharacterEvents and CharacterEvents:FindFirstChild("Interact")

local function ev_RespawnSelf()
    -- 真实源码: ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true)
    if ChangePlayerMode then
        pcall(function() ChangePlayerMode:FireServer(true) end)
        return true
    else
        warn("[Evade v2] 找不到 ChangePlayerMode Remote")
        return false
    end
end

local function ev_Interact(action, flag, targetName)
    -- 真实源码:
    --   Events.Character.Interact:FireServer("Revive", true, PlayerName)
    --   Events.Character.Interact:FireServer("Carry",  true, PlayerName)
    if InteractEvent then
        pcall(function() InteractEvent:FireServer(action, flag, targetName) end)
        return true
    else
        warn("[Evade v2] 找不到 Character.Interact Remote")
        return false
    end
end

-- 兼容 VanillaSourceCode 里的第二种调用
local function ev_RevivePlayerCompat(targetName)
    pcall(function()
        local ReviveFolder = Events and Events:FindFirstChild("Revive")
        local RevivePlayer = ReviveFolder and ReviveFolder:FindFirstChild("RevivePlayer")
        if RevivePlayer then
            RevivePlayer:FireServer(tostring(targetName), false)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 7. 通用工具函数
-- ══════════════════════════════════════════════════════════════════
local function getChar() return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() end
local function getHum()  local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot() local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end

local function TP(v3)
    local root = getRoot()
    if not root then return false end
    pcall(function() root.CFrame = (typeof(v3) == "CFrame" and v3) or CFrame.new(v3) end)
    return true
end

local function getDistBetween(a, b)
    if a and b then return (a.Position - b.Position).Magnitude end
    return math.huge
end

-- 获取 Workspace.Game.Players 下的所有对象 (AI + 玩家角色模型实际都在这里)
local function getWSP()
    local g = getWorkspaceGame()
    return g and g:FindFirstChild("Players")
end

-- 判断 obj 是否是 Nextbot/AI (在 WSP 里但不是真实玩家的 character)
local function isAI(obj)
    if not obj or not obj:IsA("Model") then return false end
    -- 真实源码: not game.Players:FindFirstChild(v.Name)  => AI
    if Players:FindFirstChild(obj.Name) then return false end
    -- 双重保险: GetPlayerFromCharacter
    if Players:GetPlayerFromCharacter(obj) then return false end
    return true
end

-- 找出第一个倒下的玩家 (用于 MoneyFarm)
local function GetDownedPlayer()
    local wsp = getWSP()
    if not wsp then return nil end
    for _, v in ipairs(wsp:GetChildren()) do
        if v:IsA("Model") and v:GetAttribute("Downed") then
            return v
        end
    end
    return nil
end

-- 时间格式化 h/m/s (真实源码)
local function fmtInt(n) return string.format("%02i", n) end
local function secsToHMS(s)
    local m = (s - s % 60) / 60
    s = s - m * 60
    local h = (m - m % 60) / 60
    m = m - h * 60
    return fmtInt(h) .. "H " .. fmtInt(m) .. "M " .. fmtInt(s) .. "S"
end

-- 数字千分位 (真实源码 Credits: DevForum)
local function fmtNumber(v)
    v = tostring(v)
    return v:reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
end

-- ══════════════════════════════════════════════════════════════════
-- 8. ESP 实现 (基于真实游戏路径)
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end
end

local function createHighlight(parent, color, fillT, outlineT)
    local hl = Instance.new("Highlight")
    hl.Name = "Evade2_ESP_HL"
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = fillT or 0.6
    hl.OutlineTransparency = outlineT or 0.2
    hl.Enabled = true
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = parent
    return hl
end

local function createBillboard(parent, text, color, yOffset)
    local bb = Instance.new("BillboardGui")
    bb.Name = "Evade2_ESP_BB"
    bb.Size = UDim2.new(0, 200, 0, 40)
    bb.StudsOffset = Vector3.new(0, yOffset or 3, 0)
    bb.AlwaysOnTop = true
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.BackgroundTransparency = 1
    tl.Text = text
    tl.TextColor3 = color
    tl.TextStrokeTransparency = 0.5
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14
    tl.Parent = bb
    bb.Parent = parent
    return bb
end

local function clearObjESP(obj)
    pcall(function()
        for _, c in ipairs(obj:GetChildren()) do
            if c.Name == "Evade2_ESP_HL" or c.Name == "Evade2_ESP_BB" then
                c:Destroy()
            end
        end
    end)
end

local function processModel(obj, espColor, prefix)
    if not obj or not obj.Parent then return end
    local target = obj
    if not obj:IsA("Model") and obj.Parent and obj.Parent:IsA("Model") then
        target = obj.Parent
    end
    clearObjESP(target)

    -- 倒下的玩家 → 用 ESP_DownedColor 覆盖
    local color = espColor
    local prefixStr = prefix or ""
    local plrFromChar = Players:GetPlayerFromCharacter(target)
    if SETTINGS.ESP_Downed and plrFromChar and target:GetAttribute("Downed") then
        color = SETTINGS.ESP_DownedColor
        prefixStr = "💀DOWN "
    end

    -- 距离
    local myRoot = getRoot()
    local tgtRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildOfClass("BasePart")
    local distText = ""
    if myRoot and tgtRoot and tgtRoot:IsA("BasePart") then
        distText = string.format(" [%dm]", math.floor((myRoot.Position - tgtRoot.Position).Magnitude))
    end

    if SETTINGS.ESP_Box then
        pcall(function() createHighlight(target, color, 0.6, 0.2) end)
    end

    if SETTINGS.ESP_Name or SETTINGS.ESP_Distance then
        local text = ""
        if SETTINGS.ESP_Name then text = text .. prefixStr .. target.Name end
        if SETTINGS.ESP_Distance then text = text .. distText end
        if text ~= "" then
            pcall(function() createBillboard(target, text, color, plrFromChar and 4 or 2.5) end)
        end
    end
end

local function runESPLoop()
    if not espFolder then
        espFolder = Instance.new("Folder")
        espFolder.Name = "Evade2_ESP_Folder"
        espFolder.Parent = CoreGui
    end

    -- Bot ESP (真实源码: workspace.Game.Players)
    if SETTINGS.ESP_Bot then
        local wsp = getWSP()
        if wsp then
            for _, obj in ipairs(wsp:GetChildren()) do
                if isAI(obj) then
                    processModel(obj, SETTINGS.ESP_BotColor, "[AI] ")
                end
            end
        end
    end

    -- Player ESP + Downed (遍历 WSP + GetPlayers 双保险)
    if SETTINGS.ESP_Player or SETTINGS.ESP_Downed then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                processModel(p.Character, SETTINGS.ESP_PlayerColor, "")
            end
        end
    end

    -- Ticket ESP (真实源码: workspace.Game.Effects.Tickets)
    if SETTINGS.ESP_Ticket then
        local game = getWorkspaceGame()
        local effects = game and game:FindFirstChild("Effects")
        local tickets = effects and effects:FindFirstChild("Tickets")
        if tickets then
            for _, tk in ipairs(tickets:GetChildren()) do
                -- 真实源码里 Tickets 子项有 HumanoidRootPart
                local tgt = tk:FindFirstChild("HumanoidRootPart") or tk
                processModel(tgt, SETTINGS.ESP_TicketColor, "🎫 Ticket: ")
            end
        end
    end
end

local function toggleESP(enabled)
    if espConn then espConn:Disconnect(); espConn = nil end
    if enabled then
        local last = 0
        espConn = RunService.RenderStepped:Connect(function()
            if isDestroyed then return end
            local now = tick()
            if now - last >= (SETTINGS.ESP_Refresh or 0.1) then
                last = now
                pcall(runESPLoop)
            end
        end)
    else
        clearESP()
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 移动功能
-- ══════════════════════════════════════════════════════════════════
local function toggleSpeedBoost(enabled, value)
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    if enabled then
        -- 真实源码: 用 moveDirection * Speed 直接改 CFrame
        speedConn = RunService.Stepped:Connect(function()
            if isDestroyed then return end
            local p = LocalPlayer
            if not p or not p.character then return end
            local hum = p.character:FindFirstChildOfClass("Humanoid")
            local rp  = p.character:FindFirstChild("HumanoidRootPart")
            if hum and rp then
                local md = hum.MoveDirection
                if md.Magnitude > 0 then
                    local np = rp.Position + md * (value or SETTINGS.EV_SpeedValue or 2)
                    pcall(function()
                        rp.CFrame = CFrame.new(np, np + md)
                    end)
                end
            end
        end)
    end
end

local function setWalkSpeed(enabled, v)
    local hum = getHum()
    if hum then pcall(function() hum.WalkSpeed = enabled and v or 16 end) end
end

local function setJumpPower(enabled, v)
    local hum = getHum()
    if hum then pcall(function() hum.JumpPower = enabled and v or 50; hum.UseJumpPower = true end) end
end

local function toggleInfJump(enabled)
    if infJumpConn then infJumpConn:Disconnect(); infJumpConn = nil end
    if enabled then
        infJumpConn = UserInputService.UserJumpRequest:Connect(function()
            local hum = getHum()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

local function toggleNoclip(enabled)
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if enabled then
        noclipConn = RunService.Stepped:Connect(function()
            local root = getRoot()
            if root then
                pcall(function() root.CanCollide = false end)
                for _, p in ipairs(root.Parent:GetChildren()) do
                    if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
                end
            end
        end)
    end
end

local function toggleFly(enabled, speed)
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
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
            local v = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then v = v + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then v = v - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then v = v - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then v = v + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then v = v + Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then v = v - Vector3.new(0,1,0) end
            if v.Magnitude > 0 then v = v.Unit * (speed or 80) end
            flyBV.Velocity = v
            if flyBG and root then flyBG.CFrame = CFrame.new(root.Position) * cam.CFrame.Rotation end
        end)
    end
end

local function toggleGravity(enabled, v)
    if gravityConn then gravityConn:Disconnect(); gravityConn = nil end
    Workspace.Gravity = enabled and v or 196.2
end

local function toggleFOV(enabled, v)
    if fovConn then fovConn:Disconnect(); fovConn = nil end
    if enabled then
        fovConn = RunService.RenderStepped:Connect(function()
            local c = Workspace.CurrentCamera
            if c then c.FieldOfView = v or 90 end
        end)
    else
        local c = Workspace.CurrentCamera
        if c then c.FieldOfView = 70 end
    end
end

local function toggleAntiAFK(enabled)
    if antiAFKConn then antiAFKConn:Disconnect(); antiAFKConn = nil end
    if enabled then
        antiAFKConn = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 视觉 / 世界功能 (基于真实源码)
-- ══════════════════════════════════════════════════════════════════
local function toggleFullbright(enabled)
    -- 真实源码风格: Brightness=4, FogEnd=100000, GlobalShadows=false, ClockTime=12
    if enabled then
        if savedLighting.Brightness == nil then
            savedLighting.Brightness = Lighting.Brightness
            savedLighting.FogEnd = Lighting.FogEnd
            savedLighting.ClockTime = Lighting.ClockTime
            savedLighting.GlobalShadows = Lighting.GlobalShadows
        end
        Lighting.Brightness = 4
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.ClockTime = 12
    else
        Lighting.Brightness = savedLighting.Brightness or 1
        Lighting.FogEnd = savedLighting.FogEnd or 500
        Lighting.ClockTime = savedLighting.ClockTime or 14
        Lighting.GlobalShadows = savedLighting.GlobalShadows or true
    end
end

local function doRemoveBarriers()
    -- 真实源码: workspace.Game.Map.InvisParts:ClearAllChildren()
    local g = getWorkspaceGame()
    local map = g and g:FindFirstChild("Map")
    local invis = map and map:FindFirstChild("InvisParts")
    if invis then
        local n = #invis:GetChildren()
        invis:ClearAllChildren()
        notify("世界", "已清除 " .. n .. " 个隐形障碍物", 2, "Success")
        return true
    else
        notify("世界", "找不到 InvisParts (可能未开局)", 2, "Warning")
        return false
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 原地复活 / 相机还原 (来自NoobHubV4源码)
-- ══════════════════════════════════════════════════════════════════
local function SaveCamPos() SavedPositions.OldCameraPos = Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame end
local function LoadCamPos()
    if SavedPositions.OldCameraPos and Workspace.CurrentCamera then
        Workspace.CurrentCamera.CFrame = SavedPositions.OldCameraPos
    end
end

local function setupHUDListener(hud)
    if not hud then return end
    hud:GetPropertyChangedSignal("Visible"):Connect(function()
        -- 真实源码: 当 HUD.Visible == false + autoRespawn 开启时 → 保存位置/相机 + 触发复活
        if not hud.Visible and SETTINGS.EV_AutoRespawn then
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if SETTINGS.EV_SavePosOnRespawn then
                SavedPositions.AutoRe = root and root.CFrame
                SaveCamPos()
            end
            autoRespawnSent = true
            ev_RespawnSelf()
        end
    end)
end

local function listenToShared(shared)
    if not shared then return end
    local hud = shared:FindFirstChild("HUD")
    if hud then setupHUDListener(hud) end
    shared.ChildAdded:Connect(function(child)
        if child.Name == "HUD" then setupHUDListener(child) end
    end)
end

local function listenToPlayerGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end
    local shared = pg:FindFirstChild("Shared")
    if shared then listenToShared(shared) end
    pg.ChildAdded:Connect(function(child)
        if child.Name == "Shared" then listenToShared(child) end
    end)
end

-- 角色复活后 → 还原位置/相机 (真实源码: 循环5次 TP 校正位置)
local function onCharAdded()
    local lochar = getChar()
    if SETTINGS.EV_SavePosOnRespawn and SETTINGS.EV_AutoRespawn and autoRespawnSent and SavedPositions.AutoRe then
        local LRoot = lochar:WaitForChild("HumanoidRootPart", 2)
        if LRoot then
            pcall(function()
                LRoot.CFrame = SavedPositions.AutoRe
                LoadCamPos()
                LRoot.CFrame = SavedPositions.AutoRe
            end)
            autoRespawnSent = false
            task.spawn(function()
                for i = 1, 5 do
                    task.wait()
                    if LRoot and LRoot.Parent then
                        pcall(function() LRoot.CFrame = SavedPositions.AutoRe end)
                    end
                end
            end)
        end
    end
    -- 同步移动设置
    setWalkSpeed(SETTINGS.EV_WalkSpeed, SETTINGS.EV_WalkSpeedValue)
    setJumpPower(SETTINGS.EV_JumpPower, SETTINGS.EV_JumpPowerValue)
    if SETTINGS.EV_InfJump then toggleInfJump(true) end
    if SETTINGS.EV_NoClip then toggleNoclip(true) end
end

-- ══════════════════════════════════════════════════════════════════
-- 12. Farm 功能 (MoneyFarm / TicketFarm / AFKFarm)
-- ══════════════════════════════════════════════════════════════════
local SAFE_AFK_POS = Vector3.new(6007, 7005, 8005)  -- 真实源码的天空盒外安全坐标

local function reviveDownedPlayer(downedplr)
    if not downedplr or not downedplr:FindFirstChild("HumanoidRootPart") then return end
    task.spawn(function()
        if SETTINGS.EV_ReviveTimeBoost then
            local g = getWorkspaceGame()
            local settings = g and g:FindFirstChild("Settings")
            if settings then
                pcall(function() settings:SetAttribute("ReviveTime", 2.2) end)
            end
        end
        local dhrp = downedplr.HumanoidRootPart
        -- 真实源码: TP 到目标上方 +3 位置
        TP(Vector3.new(dhrp.Position.X, dhrp.Position.Y + 3, dhrp.Position.Z))
        task.wait()
        -- 两种 Interact 调用 (兼容)
        ev_Interact("Revive", nil, tostring(downedplr))
        ev_Interact("Revive", true, tostring(downedplr))
        ev_RevivePlayerCompat(tostring(downedplr))
    end)
end

local function toggleMoneyFarm(enabled)
    if farmConn then farmConn:Disconnect(); farmConn = nil end
    if enabled then
        farmConn = RunService.Heartbeat:Connect(function() end)  -- 占位
        task.spawn(function()
            while SETTINGS.EV_MoneyFarm and not isDestroyed do
                local delay = SETTINGS.EV_MoneyFarmDelay or 1
                -- 主循环
                if LocalPlayer:GetAttribute("InMenu") and LocalPlayer:GetAttribute("Dead") ~= true then
                    ev_RespawnSelf()
                end
                local ch = LocalPlayer.Character
                if ch and ch:GetAttribute("Downed") then
                    ev_RespawnSelf()
                    task.wait(3)
                else
                    reviveDownedPlayer(GetDownedPlayer())
                end
                task.wait(delay)
            end
        end)
    end
end

local function toggleTicketFarm(enabled)
    if ticketConn then ticketConn:Disconnect(); ticketConn = nil end
    if enabled then
        task.spawn(function()
            while SETTINGS.EV_TicketFarm and not isDestroyed do
                if LocalPlayer:GetAttribute("InMenu") ~= true and LocalPlayer:GetAttribute("Dead") ~= true then
                    local g = getWorkspaceGame()
                    local effects = g and g:FindFirstChild("Effects")
                    local tickets = effects and effects:FindFirstChild("Tickets")
                    if tickets then
                        for _, tk in ipairs(tickets:GetChildren()) do
                            local hrp = tk:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                TP(hrp.Position)
                            end
                        end
                    end
                else
                    task.wait(2)
                    ev_RespawnSelf()
                end
                if LocalPlayer.Character and LocalPlayer.Character:GetAttribute("Downed") then
                    ev_RespawnSelf()
                    task.wait(2)
                end
                task.wait()
            end
        end)
    end
end

-- Tokens 变化监听 (真实源码: 记录差值)
local function setupTokensTracking()
    if baseTokens == nil then
        baseTokens = LocalPlayer:GetAttribute("Tokens") or 0
    end
    LocalPlayer:GetAttributeChangedSignal("Tokens"):Connect(function()
        local cur = LocalPlayer:GetAttribute("Tokens") or 0
        local diff = cur - baseTokens
        if diff > 0 then
            FarmStats.TokenFarm.earned = diff
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 13. Rejoin 当前服务器 (真实源码)
-- ══════════════════════════════════════════════════════════════════
local function doRejoin()
    local PlaceId = game.PlaceId
    local JobId = game.JobId
    if #Players:GetPlayers() <= 1 then
        LocalPlayer:Kick("\nRejoining...")
        task.wait()
        TeleportService:Teleport(PlaceId, LocalPlayer)
    else
        TeleportService:TeleportToPlaceInstance(PlaceId, JobId, LocalPlayer)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 14. 构建 Quantum UI
-- ══════════════════════════════════════════════════════════════════
local GameName = "Evade"
local PlaceId  = game.PlaceId

Window = QuantumUI.new({
    Title    = "Evade",
    Subtitle = "Nextbot 逃生辅助 v2.0 (真实源码版)",
    ThemeColor = Color3.fromRGB(170, 85, 255),
    Transparency = 0.3,
    Size     = UDim2.new(0, 640, 0, 580),
    Keybind  = Enum.KeyCode.RightShift,
})
_G.QuantumUI_Window = Window

task.wait(3.5)

listenToPlayerGui()
LocalPlayer.CharacterAdded:Connect(onCharAdded)
setupTokensTracking()

-- ─────────────── TAB 1: 角色 / 复活 ───────────────
local CharTab = Window:AddTab({ Name = "角色", Icon = "rbxassetid://6034287594" })

CharTab:AddSection({ Name = "自身复活 (Real Remote)" })

CharTab:AddToggle({
    Name     = "Auto Respawn (自动复活)",
    Default  = false,
    Flag     = "EV_AutoRespawn",
    Callback = function(s)
        SETTINGS.EV_AutoRespawn = s
        notify("Auto Respawn", s and "已开启 (HUD监听)" or "已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddToggle({
    Name     = "原地复活 (保存位置/相机)",
    Default  = true,
    Flag     = "EV_SavePosOnRespawn",
    Callback = function(s)
        SETTINGS.EV_SavePosOnRespawn = s
    end,
})

CharTab:AddToggle({
    Name     = "加速复活 (ReviveTime=2.2s)",
    Default  = false,
    Flag     = "EV_ReviveTimeBoost",
    Callback = function(s) SETTINGS.EV_ReviveTimeBoost = s end,
})

CharTab:AddButton({
    Name = "🔄 立即复活 (ChangePlayerMode)",
    Callback = function()
        local root = getRoot()
        if root and SETTINGS.EV_SavePosOnRespawn then
            SavedPositions.AutoRe = root.CFrame
            SaveCamPos()
            autoRespawnSent = true
        end
        if ev_RespawnSelf() then
            notify("复活", "已调用 ChangePlayerMode(true)", 2, "Success")
        end
    end,
})

CharTab:AddSection({ Name = "队友复活/扛起 (Interact Remote)" })

CharTab:AddToggle({
    Name     = "Instant Revive (范围立即复活队友)",
    Default  = false,
    Flag     = "EV_InstantRevive",
    Callback = function(s) SETTINGS.EV_InstantRevive = s end,
})

CharTab:AddToggle({
    Name     = "Instant Carry (范围立即扛起队友)",
    Default  = false,
    Flag     = "EV_InstantCarry",
    Callback = function(s) SETTINGS.EV_InstantCarry = s end,
})

CharTab:AddToggle({
    Name     = "Auto Revive (瞬移+复活队友 Money核心)",
    Default  = false,
    Flag     = "EV_AutoRevive",
    Callback = function(s) SETTINGS.EV_AutoRevive = s end,
})

CharTab:AddSlider({
    Name      = "Instant 范围",
    Min       = 5, Max = 50, Default = 15, Increment = 1,
    Suffix    = "studs",
    Flag      = "EV_InstantRange",
    Callback  = function(v) SETTINGS.EV_InstantRange = v end,
})

-- Instant 循环 + AutoRevive 循环 + Attribute 自动复活检测 (统一放到一个Heartbeat里)
task.spawn(function()
    while task.wait() and not isDestroyed do
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            local r = SETTINGS.EV_InstantRange or 15
            for _, v in ipairs(Players:GetPlayers()) do
                if v == LocalPlayer then continue end
                if v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                    local hum = v.Character:FindFirstChildOfClass("Humanoid")
                    local vrp = v.Character.HumanoidRootPart
                    local dist = (myRoot.Position - vrp.Position).Magnitude
                    if hum and hum.Health <= 0 and dist <= r then
                        if SETTINGS.EV_InstantRevive then
                            ev_Interact("Revive", true, v.Name)
                        end
                        if SETTINGS.EV_InstantCarry then
                            ev_Interact("Carry", true, v.Name)
                        end
                    end
                    -- AutoRevive (MoneyFarm风格: 无视距离直接传)
                    if SETTINGS.EV_AutoRevive and v.Character and v.Character:GetAttribute("Downed") then
                        TP(Vector3.new(vrp.Position.X, vrp.Position.Y + 8, vrp.Position.Z))
                        ev_Interact("Revive", true, v.Name)
                    end
                end
            end
        end
        -- Downed属性自动复活
        if SETTINGS.EV_AutoRespawn and LocalPlayer.Character and LocalPlayer.Character:GetAttribute("Downed") then
            if not autoRespawnSent then
                if SETTINGS.EV_SavePosOnRespawn then
                    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    SavedPositions.AutoRe = root and root.CFrame
                    SaveCamPos()
                end
                autoRespawnSent = true
            end
            ev_RespawnSelf()
        end
        -- AFK Farm
        if SETTINGS.EV_AFKFarm and not SETTINGS.EV_MoneyFarm then
            local rp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if rp then
                pcall(function() rp.CFrame = CFrame.new(SAFE_AFK_POS) end)
            end
        end
    end
end)

-- Farm duration 累加
task.spawn(function()
    while task.wait(1) and not isDestroyed do
        if SETTINGS.EV_TicketFarm then FarmStats.TicketFarm.duration += 1 end
        if SETTINGS.EV_MoneyFarm then FarmStats.TokenFarm.duration += 1 end
    end
end)

-- ─────────────── TAB 2: Farm ───────────────
local FarmTab = Window:AddTab({ Name = "Farm", Icon = "rbxassetid://6035153470" })

FarmTab:AddSection({ Name = "自动农场 (真实源码逻辑)" })

FarmTab:AddToggle({
    Name     = "Money Farm (复活赚Tokens)",
    Default  = false,
    Flag     = "EV_MoneyFarm",
    Callback = function(s)
        SETTINGS.EV_MoneyFarm = s
        toggleMoneyFarm(s)
        notify("Money Farm", s and "已启动" or "已停止", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddToggle({
    Name     = "Ticket Farm (活动票收集)",
    Default  = false,
    Flag     = "EV_TicketFarm",
    Callback = function(s)
        SETTINGS.EV_TicketFarm = s
        toggleTicketFarm(s)
        notify("Ticket Farm", s and "已启动" or "已停止", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddToggle({
    Name     = "AFK Farm (天空盒安全坐标)",
    Default  = false,
    Flag     = "EV_AFKFarm",
    Callback = function(s)
        SETTINGS.EV_AFKFarm = s
        if s then
            notify("AFK Farm", "→ 传送到 ("..tostring(SAFE_AFK_POS.X)..","..tostring(SAFE_AFK_POS.Y)..","..tostring(SAFE_AFK_POS.Z)..")", 3, "Success")
        end
    end,
})

FarmTab:AddSlider({
    Name      = "Money Farm 间隔",
    Min       = 0.3, Max = 5, Default = 1, Increment = 0.1,
    Suffix    = "s",
    Flag      = "EV_MoneyFarmDelay",
    Callback  = function(v) SETTINGS.EV_MoneyFarmDelay = v end,
})

FarmTab:AddSection({ Name = "Farm 统计" })

local farmTypeLabel = FarmTab:AddLabel({ Text = "当前模式: 未启动" })
local farmDurLabel  = FarmTab:AddLabel({ Text = "运行时长: 0H 00M 00S" })
local farmEarnLabel = FarmTab:AddLabel({ Text = "已赚取: 0 Tokens" })

task.spawn(function()
    while task.wait(0.5) and not isDestroyed do
        if SETTINGS.EV_MoneyFarm then
            farmTypeLabel:SetText("当前模式: 💰 Money Farm")
            farmDurLabel:SetText("运行时长: " .. secsToHMS(FarmStats.TokenFarm.duration))
            local earned = FarmStats.TokenFarm.earned
            farmEarnLabel:SetText("已赚取: " .. (earned and (fmtNumber(earned) .. " Tokens") or (fmtNumber((LocalPlayer:GetAttribute("Tokens") or 0) - (baseTokens or 0)) .. " Tokens")))
        elseif SETTINGS.EV_TicketFarm then
            farmTypeLabel:SetText("当前模式: 🎫 Ticket Farm")
            farmDurLabel:SetText("运行时长: " .. secsToHMS(FarmStats.TicketFarm.duration))
            farmEarnLabel:SetText("当前Tickets: " .. tostring(LocalPlayer:GetAttribute("Tickets") or "N/A"))
        elseif SETTINGS.EV_AFKFarm then
            farmTypeLabel:SetText("当前模式: ☁️ AFK Farm (天空盒外)")
            farmDurLabel:SetText("坐标: " .. tostring(SAFE_AFK_POS.X) .. "," .. tostring(SAFE_AFK_POS.Y) .. "," .. tostring(SAFE_AFK_POS.Z))
            farmEarnLabel:SetText("Tokens: " .. fmtNumber(LocalPlayer:GetAttribute("Tokens") or 0))
        else
            farmTypeLabel:SetText("当前模式: 未启动")
            farmDurLabel:SetText("Money: " .. secsToHMS(FarmStats.TokenFarm.duration) .. "   Ticket: " .. secsToHMS(FarmStats.TicketFarm.duration))
            farmEarnLabel:SetText("Tokens: " .. fmtNumber(LocalPlayer:GetAttribute("Tokens") or 0))
        end
    end
end)

-- ─────────────── TAB 3: ESP ───────────────
local ESP_Tab = Window:AddTab({ Name = "ESP", Icon = "rbxassetid://6034509993" })

ESP_Tab:AddSection({ Name = "总开关" })

ESP_Tab:AddToggle({
    Name     = "启用 ESP",
    Default  = false,
    Flag     = "EV_ESPEnabled",
    Callback = function(s)
        SETTINGS.ESPEnabled = s
        toggleESP(s)
        notify("ESP", s and "已启动 (真实游戏路径)" or "已关闭", 2, s and "Success" or "Info")
    end,
})

ESP_Tab:AddSlider({
    Name      = "刷新间隔",
    Min       = 0.03, Max = 0.5, Default = 0.1, Increment = 0.01,
    Suffix    = "s",
    Flag      = "EV_ESPRefresh",
    Callback  = function(v) SETTINGS.ESP_Refresh = v end,
})

ESP_Tab:AddSection({ Name = "显示选项" })

ESP_Tab:AddToggle({ Name = "显示名称", Default = true, Flag = "EV_ESPName",
    Callback = function(s) SETTINGS.ESP_Name = s end })

ESP_Tab:AddToggle({ Name = "显示距离", Default = true, Flag = "EV_ESPDistance",
    Callback = function(s) SETTINGS.ESP_Distance = s end })

ESP_Tab:AddToggle({ Name = "高亮框 (Box)", Default = false, Flag = "EV_ESPBox",
    Callback = function(s) SETTINGS.ESP_Box = s end })

ESP_Tab:AddSection({ Name = "Nextbot / AI (workspace.Game.Players)" })

ESP_Tab:AddToggle({
    Name     = "Nextbot ESP (红色警告)",
    Default  = false,
    Flag     = "EV_ESPBot",
    Callback = function(s)
        SETTINGS.ESP_Bot = s
        if s and not SETTINGS.ESPEnabled then SETTINGS.ESPEnabled = true; toggleESP(true) end
    end,
})

ESP_Tab:AddColorPicker({
    Name = "Nextbot 颜色", Default = Color3.fromRGB(255, 50, 50), Flag = "EV_BotColor",
    Callback = function(c) SETTINGS.ESP_BotColor = c end
})

ESP_Tab:AddSection({ Name = "玩家" })

ESP_Tab:AddToggle({
    Name     = "玩家 ESP (橙色)",
    Default  = false,
    Flag     = "EV_ESPPlayer",
    Callback = function(s)
        SETTINGS.ESP_Player = s
        if s and not SETTINGS.ESPEnabled then SETTINGS.ESPEnabled = true; toggleESP(true) end
    end,
})

ESP_Tab:AddColorPicker({
    Name = "玩家 颜色", Default = Color3.fromRGB(255, 170, 0), Flag = "EV_PlayerColor",
    Callback = function(c) SETTINGS.ESP_PlayerColor = c end
})

ESP_Tab:AddToggle({
    Name     = "倒下玩家颜色区分 (白)",
    Default  = true,
    Flag     = "EV_ESPDowned",
    Callback = function(s)
        SETTINGS.ESP_Downed = s
        if s and not SETTINGS.ESPEnabled then SETTINGS.ESPEnabled = true; toggleESP(true) end
    end,
})

ESP_Tab:AddColorPicker({
    Name = "倒下玩家 颜色", Default = Color3.fromRGB(255, 255, 255), Flag = "EV_DownedColor",
    Callback = function(c) SETTINGS.ESP_DownedColor = c end
})

ESP_Tab:AddSection({ Name = "Tickets (workspace.Game.Effects.Tickets)" })

ESP_Tab:AddToggle({
    Name     = "Ticket ESP (蓝色)",
    Default  = false,
    Flag     = "EV_ESPTicket",
    Callback = function(s)
        SETTINGS.ESP_Ticket = s
        if s and not SETTINGS.ESPEnabled then SETTINGS.ESPEnabled = true; toggleESP(true) end
    end,
})

ESP_Tab:AddColorPicker({
    Name = "Ticket 颜色", Default = Color3.fromRGB(41, 180, 255), Flag = "EV_TicketColor",
    Callback = function(c) SETTINGS.ESP_TicketColor = c end
})

ESP_Tab:AddButton({
    Name = "🧹 清除所有 ESP 对象",
    Callback = function() clearESP(); notify("ESP", "已清除所有 ESP 标记", 2, "Info") end
})

-- ─────────────── TAB 4: 移动 ───────────────
local MoveTab = Window:AddTab({ Name = "移动", Icon = "rbxassetid://6034466796" })

MoveTab:AddSection({ Name = "Speed Boost (源码 CFrame 方式, 不被重置)" })

MoveTab:AddToggle({
    Name     = "Speed Boost (推荐)",
    Default  = false,
    Flag     = "EV_SpeedBoost",
    Callback = function(s)
        SETTINGS.EV_SpeedBoost = s
        toggleSpeedBoost(s, SETTINGS.EV_SpeedValue)
    end,
})

MoveTab:AddSlider({
    Name      = "Speed 值",
    Min       = 2, Max = 500, Default = 8, Increment = 1,
    Flag      = "EV_SpeedValue",
    Callback  = function(v) SETTINGS.EV_SpeedValue = v; if SETTINGS.EV_SpeedBoost then toggleSpeedBoost(true, v) end end,
})

MoveTab:AddSection({ Name = "传统移动修改" })

MoveTab:AddToggle({ Name = "WalkSpeed", Default = false, Flag = "EV_WalkSpeed",
    Callback = function(s) SETTINGS.EV_WalkSpeed = s; setWalkSpeed(s, SETTINGS.EV_WalkSpeedValue) end })

MoveTab:AddSlider({ Name = "WalkSpeed 值", Min = 16, Max = 300, Default = 35, Increment = 1,
    Flag = "EV_WalkSpeedValue",
    Callback = function(v) SETTINGS.EV_WalkSpeedValue = v; if SETTINGS.EV_WalkSpeed then setWalkSpeed(true, v) end end })

MoveTab:AddToggle({ Name = "JumpPower", Default = false, Flag = "EV_JumpPower",
    Callback = function(s) SETTINGS.EV_JumpPower = s; setJumpPower(s, SETTINGS.EV_JumpPowerValue) end })

MoveTab:AddSlider({ Name = "JumpPower 值", Min = 50, Max = 200, Default = 100, Increment = 1,
    Flag = "EV_JumpPowerValue",
    Callback = function(v) SETTINGS.EV_JumpPowerValue = v; if SETTINGS.EV_JumpPower then setJumpPower(true, v) end end })

MoveTab:AddToggle({ Name = "InfJump (无限跳)", Default = false, Flag = "EV_InfJump",
    Callback = function(s) SETTINGS.EV_InfJump = s; toggleInfJump(s) end })

MoveTab:AddSection({ Name = "重力 / FOV" })

MoveTab:AddToggle({ Name = "低重力", Default = false, Flag = "EV_LowGravity",
    Callback = function(s) SETTINGS.EV_LowGravity = s; toggleGravity(s, SETTINGS.EV_GravityValue) end })

MoveTab:AddSlider({ Name = "重力值", Min = 10, Max = 196, Default = 50, Increment = 1,
    Flag = "EV_GravityValue",
    Callback = function(v) SETTINGS.EV_GravityValue = v; if SETTINGS.EV_LowGravity then toggleGravity(true, v) end end })

MoveTab:AddToggle({ Name = "自定义 FOV", Default = false, Flag = "EV_FOV",
    Callback = function(s) SETTINGS.EV_FOV = s; toggleFOV(s, SETTINGS.EV_FOVValue) end })

MoveTab:AddSlider({ Name = "FOV 值", Min = 60, Max = 120, Default = 90, Increment = 1, Suffix = "°",
    Flag = "EV_FOVValue",
    Callback = function(v) SETTINGS.EV_FOVValue = v; if SETTINGS.EV_FOV then toggleFOV(true, v) end end })

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({ Name = "NoClip (穿墙)", Default = false, Flag = "EV_NoClip",
    Callback = function(s) SETTINGS.EV_NoClip = s; toggleNoclip(s) end })

MoveTab:AddToggle({ Name = "Fly (飞行)", Default = false, Flag = "EV_Fly",
    Callback = function(s) SETTINGS.EV_Fly = s; toggleFly(s, SETTINGS.EV_FlySpeed) end })

MoveTab:AddSlider({ Name = "Fly Speed", Min = 10, Max = 300, Default = 80, Increment = 5,
    Flag = "EV_FlySpeed",
    Callback = function(v) SETTINGS.EV_FlySpeed = v; if SETTINGS.EV_Fly then toggleFly(true, v) end end })

-- ─────────────── TAB 5: 视觉 / 世界 ───────────────
local WorldTab = Window:AddTab({ Name = "世界", Icon = "rbxassetid://6031280882" })

WorldTab:AddSection({ Name = "视觉" })

WorldTab:AddToggle({ Name = "全亮 Fullbright (源码方式)", Default = false, Flag = "EV_Fullbright",
    Callback = function(s) SETTINGS.EV_Fullbright = s; toggleFullbright(s) end })

WorldTab:AddSection({ Name = "世界操作" })

WorldTab:AddButton({
    Name = "🧱 清除隐形障碍物 (InvisParts)",
    Callback = function() doRemoveBarriers() end,
})

WorldTab:AddToggle({ Name = "Disable Camera Shake", Default = false, Flag = "EV_NoCameraShake",
    Callback = function(s)
        SETTINGS.EV_NoCameraShake = s
        notify("相机", s and "已启用 (需要游戏支持)" or "已关闭", 2, "Info")
    end
})

WorldTab:AddSection({ Name = "服务器" })

WorldTab:AddButton({
    Name = "🔄 Rejoin (重进当前服务器)",
    Callback = function() doRejoin() end,
})

-- ─────────────── TAB 6: 杂项 ───────────────
local MiscTab = Window:AddTab({ Name = "杂项", Icon = "rbxassetid://6034287594" })

MiscTab:AddSection({ Name = "功能" })

MiscTab:AddToggle({ Name = "Anti-AFK (默认开启)", Default = true, Flag = "EV_AntiAFK",
    Callback = function(s) SETTINGS.EV_AntiAFK = s; toggleAntiAFK(s) end })
toggleAntiAFK(true)

MiscTab:AddSection({ Name = "坐标" })

MiscTab:AddButton({
    Name = "☁️ 传送到 AFK 安全坐标",
    Callback = function()
        if TP(SAFE_AFK_POS) then
            notify("传送", "→ 天空盒外 ("..tostring(SAFE_AFK_POS.X)..","..tostring(SAFE_AFK_POS.Y)..","..tostring(SAFE_AFK_POS.Z)..")", 3, "Success")
        end
    end,
})

local coordsLabel = MiscTab:AddLabel({ Text = "X: 0.00  Y: 0.00  Z: 0.00" })
RunService.Heartbeat:Connect(function()
    if isDestroyed then return end
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root and coordsLabel then
        local p = root.Position
        coordsLabel:SetText(string.format("X: %.2f   Y: %.2f   Z: %.2f", p.X, p.Y, p.Z))
    end
end)

MiscTab:AddButton({
    Name = "打印当前坐标 (控制台)",
    Callback = function()
        local root = getRoot()
        if root then
            local p = root.Position
            print(("[Evade v2] 当前坐标: Vector3.new(%.3f, %.3f, %.3f)"):format(p.X, p.Y, p.Z))
        end
    end,
})

MiscTab:AddButton({
    Name = "复制 Vector3 坐标",
    Callback = function()
        local root = getRoot()
        if root and setclipboard then
            local p = root.Position
            local s = string.format("Vector3.new(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
            setclipboard(s)
            notify("已复制", s, 2, "Success")
        end
    end,
})

MiscTab:AddButton({
    Name = "💀 自杀 / 重置角色",
    Callback = function()
        local h = getHum()
        if h then pcall(function() h.Health = 0 end) end
    end,
})

MiscTab:AddSection({ Name = "信息" })

MiscTab:AddParagraph({
    Title   = "Evade 辅助 v2.0 (真实源码版)",
    Content = table.concat({
        "PlaceId: " .. tostring(PlaceId),
        "GameId:  11818772280",
        "",
        "✓ 基于真实Evade源码 (VanillaSourceCode + NoobHubV4)",
        "",
        "真实 Remote:",
        "  Events.Player.ChangePlayerMode → 复活",
        "  Events.Character.Interact(Revive/Carry) → 队友操作",
        "",
        "真实路径:",
        "  Nextbots → workspace.Game.Players",
        "  Tickets  → workspace.Game.Effects.Tickets",
        "  Invis    → workspace.Game.Map.InvisParts",
        "  ReviveTime → workspace.Game.Settings",
        "  死亡检测 → PlayerGui.Shared.HUD.Visible",
        "  倒下属性 → Character:GetAttribute('Downed')",
        "",
        "Farm系统:",
        "  Money Farm  → 自动复活倒下队友赚Tokens",
        "  Ticket Farm → 收集活动Tickets",
        "  AFK Farm    → " .. tostring(SAFE_AFK_POS.X) .. "," .. tostring(SAFE_AFK_POS.Y) .. "," .. tostring(SAFE_AFK_POS.Z),
        "",
        "快捷键:",
        "  RightShift - 隐藏/显示 UI",
        "  T  - Rejoin 当前服务器",
        "  Y  - 切换 NoClip",
        "  U  - 切换 Fly",
        "  R  - 立即复活 (ChangePlayerMode)",
    }, "\n"),
})

-- ─────────────── 快捷键绑定 ───────────────
local keybinds = {
    [Enum.KeyCode.T] = function()
        notify("T 快捷键", "→ Rejoin 服务器", 1.5, "Info")
        doRejoin()
    end,
    [Enum.KeyCode.Y] = function()
        local ns = not SETTINGS.EV_NoClip
        SETTINGS.EV_NoClip = ns
        toggleNoclip(ns)
        notify("Y 快捷键", ns and "NoClip 已开启" or "NoClip 已关闭", 1.5, ns and "Success" or "Info")
    end,
    [Enum.KeyCode.U] = function()
        local ns = not SETTINGS.EV_Fly
        SETTINGS.EV_Fly = ns
        toggleFly(ns, SETTINGS.EV_FlySpeed)
        notify("U 快捷键", ns and "Fly 已开启" or "Fly 已关闭", 1.5, ns and "Success" or "Info")
    end,
    [Enum.KeyCode.R] = function()
        local root = getRoot()
        if root and SETTINGS.EV_SavePosOnRespawn then
            SavedPositions.AutoRe = root.CFrame
            SaveCamPos()
            autoRespawnSent = true
        end
        ev_RespawnSelf()
        notify("R 快捷键", "→ 立即复活", 1.5, "Success")
    end,
}

local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local cb = keybinds[input.KeyCode]
    if cb then task.spawn(cb) end
end)

-- ─────────────── 清理函数 ───────────────
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    for _, c in ipairs{inputConn,noclipConn,infJumpConn,flyConn,antiAFKConn,espConn,gravityConn,fovConn,speedConn,farmConn,ticketConn} do
        pcall(function() if c then c:Disconnect() end end)
    end
    if flyBV then flyBV:Destroy() end
    if flyBG then flyBG:Destroy() end
    clearESP()

    SETTINGS.EV_WalkSpeed = false
    SETTINGS.EV_JumpPower = false
    SETTINGS.EV_InfJump = false
    SETTINGS.EV_NoClip = false
    SETTINGS.EV_Fly = false
    SETTINGS.EV_LowGravity = false
    SETTINGS.EV_FOV = false
    SETTINGS.EV_Fullbright = false
    SETTINGS.EV_SpeedBoost = false
    SETTINGS.ESPEnabled = false
    SETTINGS.EV_MoneyFarm = false
    SETTINGS.EV_TicketFarm = false
    SETTINGS.EV_AFKFarm = false
    SETTINGS.EV_AntiAFK = false

    setWalkSpeed(false, 16)
    setJumpPower(false, 50)
    toggleGravity(false)
    toggleFOV(false)
    toggleFullbright(false)

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "Evade", Text = "脚本已卸载", Duration = 2 })
    end)
end

_G.Evade2_Cleanup = cleanup

task.wait(0.5)
notify("Evade v2.0", table.concat({
    "基于真实源码重写版已加载",
    "PlaceId " .. tostring(PlaceId),
    "按 RightShift 打开 UI"
}, "\n"), 5, "Success")

print(string.format("[Evade v2] %s (PlaceId: %d) 加载完成 | 真实Remote + 真实路径", GameName, PlaceId))
