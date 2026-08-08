--[[
    造船寻宝 (Build a Boat for Treasure) 辅助脚本 v1.0  ——  Quantum UI Library 版
    适配 PlaceId: 537413528
    功能: 移动类 (WalkSpeed / JumpPower / InfJump / NoClip / Fly / TP) + AutoFarm + Anti-AFK
    UI 框架: Quantum UI v3.x (SciFi-UI-Library)

    ⚠️  安全承诺: 本脚本:
      • 无任何 Discord Webhook / Google Forms / 统计上报
      • 不采集 IP / HWID / 账号信息
      • 不 loadstring 任何 pastebin / gitee / github 外部代码 (除加载 UI 库本身外)
      • 所有功能纯本地实现
--]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0.  SINGLETON GUARD — 防止重复注入
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
-- 1.  LOAD QUANTUM UI LIBRARY  (优先在线，回退本地)
-- ══════════════════════════════════════════════════════════════════
local success, QuantumUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"))()
end)

if not success then
    warn("[BABFT] 在线加载 Quantum UI 失败，尝试本地源码...")
    local localOk, localLib = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localOk or not localLib then
        error("[BABFT] 无法加载 Quantum UI Library，脚本终止")
        return
    end
    QuantumUI = localLib
end
print(("[BABFT] Quantum UI v%s 加载成功"):format(QuantumUI.Version))

-- ══════════════════════════════════════════════════════════════════
-- 2.  ROBLOX SERVICES & 常量
-- ══════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local Lighting          = game:GetService("Lighting")

-- ══════════════════════════════════════════════════════════════════
-- 3.  CREATE MAIN WINDOW
-- ══════════════════════════════════════════════════════════════════
local Window = QuantumUI.new({
    Title    = "造船寻宝助手",
    Subtitle = "BABFT v1.0  /  PlaceId 537413528",
    ThemeColor = Color3.fromRGB(0, 200, 255),
    Transparency = 0.3,
    Size     = UDim2.new(0, 580, 0, 460),
    Keybind  = Enum.KeyCode.RightControl,
})

task.wait(3.5)
_G.QuantumUI_Window = Window

-- ══════════════════════════════════════════════════════════════════
-- 4.  全局状态 & 辅助函数
-- ══════════════════════════════════════════════════════════════════
local state = {
    -- Movement
    WalkSpeed        = 16,
    JumpPower        = 50,
    SetWalkSpeed     = false,
    SetJumpPower     = false,
    InfJump          = false,
    NoClip           = false,
    FlyEnabled       = false,
    FlySpeed         = 50,
    -- AutoFarm (源自 Autofarm.lua)
    AutoFarm         = false,
    Teleport         = 2,    -- 段间隔 (秒)
    TimeBetweenRuns  = 5,   -- 下一轮间隔 (秒)
    AutoClaim        = true,
    -- Anti-AFK
    AntiAFK          = false,
}

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

-- BABFT AutoFarm 原理 (源自 Autofarm.lua):
--   Workspace.BoatStages.NormalStages["CaveStage1".."CaveStage10"].DarknessPart.CFrame
--   终点: Workspace.BoatStages.NormalStages.TheEnd.GoldenChest.Trigger.CFrame
--   完成判断: Lighting.ClockTime ~= 14
--   每段传送后, 在角色下方 6 单位创建 Anchored Part 防止下落

-- 传送点 (便捷)
local TP_LOCATIONS = {
    { Name = "起点",       Pos = CFrame.new(-25.1,  63.0, 1152.7) },
    { Name = "中段",       Pos = CFrame.new(-25.1,  81.0, 1777.4) },
    { Name = "终点附近",   Pos = CFrame.new(-25.1,  68.5, 2576.7) },
    { Name = "宝藏区",     Pos = CFrame.new(-25.1, 114.3, 3195.2) },
    { Name = "出生点",     Pos = CFrame.new(-55.7,  70.7,  125.0) },
    { Name = "地下宝藏",   Pos = CFrame.new(-55.7,-360.7, 9492.4) },
}

-- ══════════════════════════════════════════════════════════════════
-- 5.  MOVEMENT TAB  (移动类功能)
-- ══════════════════════════════════════════════════════════════════
local MovementTab = Window:AddTab({
    Name = "Movement",
    Icon = "rbxassetid://6034466796",
})

-- ═══ WalkSpeed ═══
MovementTab:AddSection({ Name = "WalkSpeed (移速)" })

MovementTab:AddSlider({
    Name      = "WalkSpeed Value",
    Min       = 16, Max = 500, Default = 16, Increment = 1,
    Flag      = "BABFT_WalkSpeed",
    Callback  = function(value) state.WalkSpeed = value end,
})

MovementTab:AddToggle({
    Name      = "Enable WalkSpeed",
    Default   = false,
    Flag      = "BABFT_WalkSpeedEnabled",
    Callback  = function(s)
        state.SetWalkSpeed = s
        if s then
            task.spawn(function()
                while state.SetWalkSpeed do
                    local hum = getHum()
                    if hum and hum.Health > 0 and hum.WalkSpeed ~= state.WalkSpeed then
                        hum.WalkSpeed = state.WalkSpeed
                    end
                    task.wait(0.1)
                end
            end)
        else
            local hum = getHum()
            if hum then hum.WalkSpeed = 16 end
        end
    end,
})

-- ═══ JumpPower ═══
MovementTab:AddSection({ Name = "JumpPower (跳跃力)" })

MovementTab:AddSlider({
    Name      = "JumpPower Value",
    Min       = 50, Max = 500, Default = 50, Increment = 1,
    Flag      = "BABFT_JumpPower",
    Callback  = function(value) state.JumpPower = value end,
})

MovementTab:AddToggle({
    Name      = "Enable JumpPower",
    Default   = false,
    Flag      = "BABFT_JumpPowerEnabled",
    Callback  = function(s)
        state.SetJumpPower = s
        if s then
            task.spawn(function()
                while state.SetJumpPower do
                    local hum = getHum()
                    if hum and hum.Health > 0 and hum.JumpPower ~= state.JumpPower then
                        hum.JumpPower = state.JumpPower
                    end
                    task.wait(0.1)
                end
            end)
        else
            local hum = getHum()
            if hum then hum.JumpPower = 50 end
        end
    end,
})

-- ═══ Infinite Jump ═══
MovementTab:AddSection({ Name = "Infinite Jump (无限跳)" })

MovementTab:AddToggle({
    Name      = "Infinite Jump",
    Default   = false,
    Flag      = "BABFT_InfJump",
    Callback  = function(s)
        state.InfJump = s
        if s then
            local conn
            conn = UserInputService.JumpRequest:Connect(function()
                if not state.InfJump then
                    conn:Disconnect()
                    return
                end
                local hum = getHum()
                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        end
    end,
})

-- ═══ NoClip ═══
MovementTab:AddSection({ Name = "NoClip (穿墙)" })

MovementTab:AddToggle({
    Name      = "NoClip (穿墙)",
    Default   = false,
    Flag      = "BABFT_NoClip",
    Callback  = function(s)
        state.NoClip = s
        if s then
            task.spawn(function()
                local conn
                conn = RunService.Stepped:Connect(function()
                    if not state.NoClip then
                        conn:Disconnect()
                        return
                    end
                    local char = getChar()
                    if char then
                        for _, part in ipairs(char:GetDescendants()) do
                            if part:IsA("BasePart") and part.CanCollide then
                                part.CanCollide = false
                            end
                        end
                    end
                end)
            end)
        else
            local char = getChar()
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = true
                    end
                end
            end
        end
    end,
})

-- ═══ Fly ═══
MovementTab:AddSection({ Name = "Fly (飞行)" })

MovementTab:AddSlider({
    Name      = "Fly Speed",
    Min       = 10, Max = 300, Default = 50, Increment = 5,
    Flag      = "BABFT_FlySpeed",
    Callback  = function(value) state.FlySpeed = value end,
})

MovementTab:AddKeybind({
    Name      = "Fly Toggle Key",
    Default   = Enum.KeyCode.F,
    Flag      = "BABFT_FlyKey",
    Callback  = function()
        state.FlyEnabled = not state.FlyEnabled
        if state.FlyEnabled then
            task.spawn(function()
                local flyConn
                local flyBV, flyBG
                local function startFly()
                    local root = getRoot()
                    local hum  = getHum()
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
                end
                local function stopFly()
                    local hum = getHum()
                    if hum then hum.PlatformStand = false end
                    if flyBV then flyBV:Destroy() end
                    if flyBG then flyBG:Destroy() end
                end
                startFly()
                flyConn = RunService.RenderStepped:Connect(function()
                    if not state.FlyEnabled then
                        flyConn:Disconnect()
                        stopFly()
                        return
                    end
                    local root = getRoot()
                    local cam  = workspace.CurrentCamera
                    if not root or not cam then return end
                    local dir = Vector3.zero
                    local cf  = cam.CFrame
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
                    if flyBV then flyBV.Velocity = dir * state.FlySpeed end
                    if flyBG then flyBG.CFrame = cam.CFrame end
                end)
            end)
            Window:Notify({
                Title = "Fly", Content = "飞行已开启 (WASD/Space/Shift)",
                Duration = 3, Type = "Info",
            })
        else
            local hum = getHum()
            if hum then hum.PlatformStand = false end
            Window:Notify({
                Title = "Fly", Content = "飞行已关闭",
                Duration = 2, Type = "Info",
            })
        end
    end,
})

-- ═══ Teleport ═══
MovementTab:AddSection({ Name = "Teleport (传送)" })

local selectedTP = TP_LOCATIONS[1]

MovementTab:AddDropdown({
    Name      = "Select Location",
    Items     = (function()
        local names = {}
        for _, loc in ipairs(TP_LOCATIONS) do table.insert(names, loc.Name) end
        return names
    end)(),
    Default   = "起点",
    Multi     = false,
    Flag      = "BABFT_TPLocation",
    Callback  = function(selected)
        for _, loc in ipairs(TP_LOCATIONS) do
            if loc.Name == selected then selectedTP = loc; break end
        end
    end,
})

MovementTab:AddButton({
    Name      = "Teleport!",
    Callback  = function()
        local char = getChar()
        if char and selectedTP then
            char:PivotTo(selectedTP.Pos)
            Window:Notify({
                Title = "传送", Content = "已传送到: " .. selectedTP.Name,
                Duration = 2, Type = "Success",
            })
        end
    end,
})

-- ══════════════════════════════════════════════════════════════════
-- 6.  AUTOFARM TAB  (源自 Autofarm.lua - CaveStage 分段传送 + GoldenChest 触发)
-- ══════════════════════════════════════════════════════════════════
local FarmTab = Window:AddTab({
    Name = "AutoFarm",
    Icon = "rbxassetid://6031094678",
})

FarmTab:AddSection({ Name = "BABFT AutoFarm (河道农场)" })

FarmTab:AddSlider({
    Name      = "Teleport Delay (段间隔)",
    Min       = 0.5, Max = 10, Default = 2, Increment = 0.5,
    Suffix    = "s",
    Flag      = "BABFT_Teleport",
    Callback  = function(value) state.Teleport = value end,
})

FarmTab:AddSlider({
    Name      = "Time Between Runs (轮间隔)",
    Min       = 1, Max = 30, Default = 5, Increment = 1,
    Suffix    = "s",
    Flag      = "BABFT_TimeBetweenRuns",
    Callback  = function(value) state.TimeBetweenRuns = value end,
})

-- 单轮农场流程 (基于 Autofarm.lua 真实逻辑)
local function runFarmOnce(currentRun)
    local Character = LocalPlayer.Character
    if not Character then return false end
    local HRP = Character:FindFirstChild("HumanoidRootPart")
    if not HRP then return false end

    local NormalStages = workspace:FindFirstChild("BoatStages")
        and workspace.BoatStages:FindFirstChild("NormalStages")
    if not NormalStages then
        warn("[BABFT] 未找到 BoatStages.NormalStages, 当前游戏可能未加载完毕")
        return false
    end

    -- 1) 依次传送到 CaveStage1 .. CaveStage10 的 DarknessPart
    for i = 1, 10 do
        if not state.AutoFarm then return false end
        local Stage = NormalStages:FindFirstChild("CaveStage" .. i)
        local DarknessPart = Stage and Stage:FindFirstChild("DarknessPart")
        if DarknessPart then
            print("[BABFT] 传送到 Stage " .. i)
            HRP.CFrame = DarknessPart.CFrame
            -- 在角色下方 6 单位创建临时 Anchored Part 防止下落
            local tempPart = Instance.new("Part")
            tempPart.Anchored = true
            tempPart.Size = Vector3.new(8, 1, 8)
            tempPart.Position = HRP.Position - Vector3.new(0, 6, 0)
            tempPart.Parent = Character
            task.wait(state.Teleport)
            tempPart:Destroy()
        end
    end

    -- 2) 传送到 TheEnd.GoldenChest.Trigger 触发宝藏奖励
    local TheEnd = NormalStages:FindFirstChild("TheEnd")
    local GoldenChest = TheEnd and TheEnd:FindFirstChild("GoldenChest")
    local Trigger = GoldenChest and GoldenChest:FindFirstChild("Trigger")
    if Trigger then
        print("[BABFT] 传送到终点 GoldenChest.Trigger")
        repeat
            if not state.AutoFarm then return false end
            HRP.CFrame = Trigger.CFrame
            task.wait(0.2)
        until Lighting.ClockTime ~= 14
    end

    -- 3) 等待角色重生
    local respawned = false
    local conn
    conn = LocalPlayer.CharacterAdded:Connect(function()
        respawned = true
        if conn then conn:Disconnect() end
    end)
    repeat
        task.wait(0.2)
        if not state.AutoFarm then return false end
    until respawned
    task.wait(state.TimeBetweenRuns)
    print("[BABFT] Run " .. currentRun .. " 完成")
    return true
end

FarmTab:AddToggle({
    Name      = "Start AutoFarm",
    Default   = false,
    Flag      = "BABFT_AutoFarm",
    Callback  = function(s)
        state.AutoFarm = s
        if s then
            task.spawn(function()
                local run = 1
                while state.AutoFarm do
                    print("[BABFT] 初始化 AutoFarm: Run " .. run)
                    local ok = pcall(runFarmOnce, run)
                    if not ok then
                        warn("[BABFT] Run " .. run .. " 异常, 等待重试")
                        task.wait(1)
                    end
                    run = run + 1
                end
            end)
            Window:Notify({
                Title = "AutoFarm", Content = "自动农场已启动\n基于 Autofarm.lua 真实逻辑",
                Duration = 3, Type = "Success",
            })
        else
            Window:Notify({
                Title = "AutoFarm", Content = "自动农场已停止",
                Duration = 2, Type = "Warning",
            })
        end
    end,
})

FarmTab:AddSection({ Name = "手动操作" })

FarmTab:AddButton({
    Name      = "传送到起点",
    Callback  = function()
        local char = getChar()
        if char then char:PivotTo(TP_LOCATIONS[1].Pos) end
    end,
})

FarmTab:AddButton({
    Name      = "传送到宝藏区",
    Callback  = function()
        local char = getChar()
        if char then char:PivotTo(TP_LOCATIONS[4].Pos) end
    end,
})

FarmTab:AddButton({
    Name      = "传送到 TheEnd (终点)",
    Callback  = function()
        local char = getChar()
        local HRP = char and char:FindFirstChild("HumanoidRootPart")
        if not HRP then return end
        local ok = pcall(function()
            local Trigger = workspace.BoatStages.NormalStages.TheEnd.GoldenChest.Trigger
            HRP.CFrame = Trigger.CFrame
        end)
        Window:Notify({
            Title = "传送", Content = ok and "已传送到 TheEnd" or "未找到 TheEnd",
            Duration = 2, Type = ok and "Success" or "Error",
        })
    end,
})

FarmTab:AddButton({
    Name      = "打印 CaveStage 坐标",
    Callback  = function()
        print("[BABFT] —— CaveStage DarknessPart 坐标 ——")
        for i = 1, 10 do
            local Stage = workspace.BoatStages.NormalStages:FindFirstChild("CaveStage" .. i)
            local dp = Stage and Stage:FindFirstChild("DarknessPart")
            if dp then
                local p = dp.Position
                print(string.format("  CaveStage%d: (%.1f, %.1f, %.1f)", i, p.X, p.Y, p.Z))
            end
        end
        local trigger = workspace.BoatStages.NormalStages.TheEnd.GoldenChest.Trigger
        local tp = trigger.Position
        print(string.format("  TheEnd.Trigger: (%.1f, %.1f, %.1f)", tp.X, tp.Y, tp.Z))
        Window:Notify({
            Title = "调试", Content = "坐标已打印到控制台",
            Duration = 2, Type = "Info",
        })
    end,
})

-- ══════════════════════════════════════════════════════════════════
-- 7.  ANTI-AFK
-- ══════════════════════════════════════════════════════════════════
MovementTab:AddSection({ Name = "Anti-AFK (防挂机)" })

MovementTab:AddToggle({
    Name      = "Anti-AFK",
    Default   = false,
    Flag      = "BABFT_AntiAFK",
    Callback  = function(s) state.AntiAFK = s end,
})

LocalPlayer.Idled:Connect(function()
    if state.AntiAFK then
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 8.  完成
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
Window:Notify({
    Title   = "造船寻宝助手",
    Content = "已加载\n按 RightControl 切换 UI\n\n功能: 移动 / AutoFarm / Anti-AFK",
    Duration = 6,
    Type    = "Success",
})

print("[BABFT] 造船寻宝助手 v1.0 加载完毕")
