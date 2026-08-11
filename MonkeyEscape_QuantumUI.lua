--[[
    Active +1 Speed Monkey Escape 辅助脚本 v1.0 (Quantum UI 版)
    适配 PlaceId: 1169737442 (Main) / 10144280947 (Universe)
    功能: 奖励点位传送 (世界一 1win~200Kwins / 世界二 1Mwins~1Twins) / 世界切换 / 移动修改 / AntiAFK
    快捷键:
        RightShift - 隐藏/显示 UI
        T          - 传送到下一奖励点 (循环)
        Y          - 传送到世界二
        U          - 传送到世界一
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
    warn("[MonkeyEscape] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[MonkeyEscape] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[MonkeyEscape] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[MonkeyEscape] Quantum UI v" .. QuantumUI.Version .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. ROBLOX SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = workspace

-- ══════════════════════════════════════════════════════════════════
-- 3. 奖励点位数据
-- ══════════════════════════════════════════════════════════════════
local WORLD1_POINTS = {
    { Name = "1 Wins",     Pos = Vector3.new(-683.203, 29.447, -255.702) },
    { Name = "5 Wins",     Pos = Vector3.new(-933.316, 30.015, -254.878) },
    { Name = "20 Wins",    Pos = Vector3.new(-1215.430, 29.197, -255.541) },
    { Name = "100 Wins",  Pos = Vector3.new(-1567.980, 28.396, -254.732) },
    { Name = "500 Wins",  Pos = Vector3.new(-2181.777, 124.546, -256.163) },
    { Name = "3K Wins",   Pos = Vector3.new(-3045.701, 124.567, -255.268) },
    { Name = "15K Wins",  Pos = Vector3.new(-4317.159, 284.349, -255.824) },
    { Name = "50K Wins",  Pos = Vector3.new(-6158.939, 286.682, -254.242) },
    { Name = "200K Wins", Pos = Vector3.new(-9460.182, 392.969, -254.013) },
}

local WORLD2_POINTS = {
    { Name = "1M Wins",   Pos = Vector3.new(-737.095, 30.030, -2565.421) },
    { Name = "5M Wins",   Pos = Vector3.new(-1095.563, 45.457, -2564.472) },
    { Name = "25M Wins",  Pos = Vector3.new(-1879.019, -44.341, -2565.318) },
    { Name = "100M Wins", Pos = Vector3.new(-2399.544, 61.899, -2564.929) },
    { Name = "600M Wins", Pos = Vector3.new(-3249.115, 60.309, -2565.262) },
    { Name = "3B Wins",   Pos = Vector3.new(-3606.015, 60.515, -3697.472) },
    { Name = "25B Wins",  Pos = Vector3.new(-3604.688, 62.925, -4605.948) },
    { Name = "150B Wins", Pos = Vector3.new(-3606.032, 62.709, -5827.293) },
    { Name = "1T Wins",   Pos = Vector3.new(-3606.089, 156.607, -9379.602) },
}

-- ══════════════════════════════════════════════════════════════════
-- 4. SETTINGS
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- Movement
    ME_WalkSpeed = false,
    ME_WalkSpeedValue = 16,
    ME_JumpPower = false,
    ME_JumpPowerValue = 50,
    ME_InfJump = false,
    ME_NoClip = false,
    ME_Fly = false,
    ME_FlySpeed = 80,

    -- Misc
    ME_AntiAFK = false,
}

-- ══════════════════════════════════════════════════════════════════
-- 5. 全局变量
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false
local noclipConn = nil
local infJumpConn = nil
local flyConn = nil
local flyBV = nil
local flyBG = nil
local antiAFKConn = nil

local currentWorld = 1
local currentPointIndex = 1

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
                Title = title,
                Text = content,
                Duration = duration or 3
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

local function getPoints(world)
    if world == 2 then return WORLD2_POINTS end
    return WORLD1_POINTS
end

local function fireTeleportWorld(worldId)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        notify("错误", "找不到 Remotes 文件夹", 3, "Error")
        return false
    end
    local teleportEvent = remotes:FindFirstChild("TeleportWorld")
    if not teleportEvent then
        notify("错误", "找不到 TeleportWorld 事件", 3, "Error")
        return false
    end
    local ok, err = pcall(function()
        teleportEvent:FireServer(worldId)
    end)
    if not ok then
        notify("传送失败", tostring(err), 4, "Error")
        return false
    end
    currentWorld = worldId
    local points = getPoints(worldId)
    currentPointIndex = 1
    notify("世界切换", "已请求传送到世界 " .. worldId, 3, "Success")
    return true
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
-- 9. 创建 UI
-- ══════════════════════════════════════════════════════════════════
local GameName = "Active +1 Speed Monkey Escape"
local PlaceId   = game.PlaceId

Window = QuantumUI.new({
    Title    = "Monkey Escape",
    Subtitle = "Active +1 Speed Monkey Escape",
    ThemeColor = Color3.fromRGB(255, 140, 40),
    Transparency = 0.3,
    Size     = UDim2.new(0, 580, 0, 460),
    Keybind  = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: 奖励传送 ──
local TP_Tab = Window:AddTab({
    Name = "奖励传送",
    Icon = "rbxassetid://6035153470",
})

TP_Tab:AddSection({ Name = "世界切换" })

TP_Tab:AddButton({
    Name = "🌍 传送到世界一",
    Callback = function()
        fireTeleportWorld(1)
    end,
})

TP_Tab:AddButton({
    Name = "🌍 传送到世界二",
    Callback = function()
        fireTeleportWorld(2)
    end,
})

TP_Tab:AddParagraph({
    Title   = "说明",
    Content = "世界切换通过 TeleportWorld RemoteEvent 实现。\n切换后请稍等片刻，奖励点位会自动更新。",
})

-- 世界一奖励点
TP_Tab:AddSection({ Name = "世界一奖励点" })

local w1DropdownItems = {}
for i, p in ipairs(WORLD1_POINTS) do
    table.insert(w1DropdownItems, p.Name)
end

local w1Dropdown = TP_Tab:AddDropdown({
    Name    = "选择奖励点 (世界一)",
    Items   = w1DropdownItems,
    Default = w1DropdownItems[1],
    Multi   = false,
    Flag    = "ME_W1Point",
})

TP_Tab:AddButton({
    Name = "🚀 传送到选中点位",
    Callback = function()
        local sel = w1Dropdown:Get()
        if not sel then
            notify("失败", "请选择一个奖励点", 2, "Error")
            return
        end
        for i, p in ipairs(WORLD1_POINTS) do
            if p.Name == sel then
                if teleportTo(p.Pos) then
                    notify("传送成功", "已传送到 " .. p.Name, 2, "Success")
                end
                return
            end
        end
    end,
})

TP_Tab:AddButton({
    Name = "⏭️ 传送到下一奖励点 (循环)",
    Callback = function()
        currentPointIndex = currentPointIndex + 1
        if currentPointIndex > #WORLD1_POINTS then
            currentPointIndex = 1
        end
        local p = WORLD1_POINTS[currentPointIndex]
        w1Dropdown:Set(p.Name)
        if teleportTo(p.Pos) then
            notify("传送", "世界一 → " .. p.Name, 2, "Info")
        end
    end,
})

-- 世界二奖励点
TP_Tab:AddSection({ Name = "世界二奖励点" })

local w2DropdownItems = {}
for i, p in ipairs(WORLD2_POINTS) do
    table.insert(w2DropdownItems, p.Name)
end

local w2Dropdown = TP_Tab:AddDropdown({
    Name    = "选择奖励点 (世界二)",
    Items   = w2DropdownItems,
    Default = w2DropdownItems[1],
    Multi   = false,
    Flag    = "ME_W2Point",
})

TP_Tab:AddButton({
    Name = "🚀 传送到选中点位",
    Callback = function()
        local sel = w2Dropdown:Get()
        if not sel then
            notify("失败", "请选择一个奖励点", 2, "Error")
            return
        end
        for i, p in ipairs(WORLD2_POINTS) do
            if p.Name == sel then
                if teleportTo(p.Pos) then
                    notify("传送成功", "已传送到 " .. p.Name, 2, "Success")
                end
                return
            end
        end
    end,
})

TP_Tab:AddButton({
    Name = "⏭️ 传送到下一奖励点 (循环)",
    Callback = function()
        currentPointIndex = currentPointIndex + 1
        if currentPointIndex > #WORLD2_POINTS then
            currentPointIndex = 1
        end
        local p = WORLD2_POINTS[currentPointIndex]
        w2Dropdown:Set(p.Name)
        if teleportTo(p.Pos) then
            notify("传送", "世界二 → " .. p.Name, 2, "Info")
        end
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
    Flag     = "ME_WalkSpeedEnabled",
    Callback = function(s)
        SETTINGS.ME_WalkSpeed = s
        setWalkSpeed(s, SETTINGS.ME_WalkSpeedValue)
    end,
})

MoveTab:AddSlider({
    Name      = "WalkSpeed 值",
    Min       = 16, Max = 200, Default = 50, Increment = 1,
    Flag      = "ME_WalkSpeedValue",
    Callback  = function(v)
        SETTINGS.ME_WalkSpeedValue = v
        if SETTINGS.ME_WalkSpeed then
            setWalkSpeed(true, v)
        end
    end,
})

MoveTab:AddSection({ Name = "跳跃" })

MoveTab:AddToggle({
    Name     = "JumpPower",
    Default  = false,
    Flag     = "ME_JumpPowerEnabled",
    Callback = function(s)
        SETTINGS.ME_JumpPower = s
        setJumpPower(s, SETTINGS.ME_JumpPowerValue)
    end,
})

MoveTab:AddSlider({
    Name      = "JumpPower 值",
    Min       = 50, Max = 200, Default = 100, Increment = 1,
    Flag      = "ME_JumpPowerValue",
    Callback  = function(v)
        SETTINGS.ME_JumpPowerValue = v
        if SETTINGS.ME_JumpPower then
            setJumpPower(true, v)
        end
    end,
})

MoveTab:AddToggle({
    Name     = "InfJump (无限跳)",
    Default  = false,
    Flag     = "ME_InfJump",
    Callback = function(s)
        SETTINGS.ME_InfJump = s
        toggleInfJump(s)
    end,
})

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({
    Name     = "NoClip (穿墙)",
    Default  = false,
    Flag     = "ME_NoClip",
    Callback = function(s)
        SETTINGS.ME_NoClip = s
        toggleNoclip(s)
    end,
})

MoveTab:AddToggle({
    Name     = "Fly (飞行)",
    Default  = false,
    Flag     = "ME_Fly",
    Callback = function(s)
        SETTINGS.ME_Fly = s
        toggleFly(s, SETTINGS.ME_FlySpeed)
        if not s then
            notify("飞行已关闭", "", 1.5, "Info")
        end
    end,
})

MoveTab:AddSlider({
    Name      = "Fly Speed",
    Min       = 10, Max = 300, Default = 80, Increment = 5,
    Flag      = "ME_FlySpeed",
    Callback  = function(v)
        SETTINGS.ME_FlySpeed = v
        if SETTINGS.ME_Fly then
            toggleFly(true, v)
        end
    end,
})

-- ── TAB 3: 杂项 ──
local MiscTab = Window:AddTab({
    Name = "杂项",
    Icon = "rbxassetid://6035153470",
})

MiscTab:AddSection({ Name = "功能" })

MiscTab:AddToggle({
    Name     = "Anti-AFK",
    Default  = false,
    Flag     = "ME_AntiAFK",
    Callback = function(s)
        SETTINGS.ME_AntiAFK = s
        toggleAntiAFK(s)
    end,
})

MiscTab:AddButton({
    Name = "💀 重生",
    Callback = function()
        local char = getChar()
        if char then
            pcall(function()
                char:FindFirstChildOfClass("Humanoid").Health = 0
            end)
        end
    end,
})

MiscTab:AddButton({
    Name = "📌 传送到世界一 1 Wins",
    Callback = function()
        fireTeleportWorld(1)
        task.wait(1)
        teleportTo(WORLD1_POINTS[1].Pos)
        notify("传送", "已传送到世界一 1 Wins", 2, "Success")
    end,
})

MiscTab:AddButton({
    Name = "📌 传送到世界二 1M Wins",
    Callback = function()
        fireTeleportWorld(2)
        task.wait(1)
        teleportTo(WORLD2_POINTS[1].Pos)
        notify("传送", "已传送到世界二 1M Wins", 2, "Success")
    end,
})

MiscTab:AddSection({ Name = "信息" })

MiscTab:AddParagraph({
    Title   = "Monkey Escape 辅助 v1.0",
    Content = table.concat({
        "游戏: Active +1 Speed Monkey Escape",
        "PlaceId: " .. tostring(PlaceId),
        "",
        "功能列表:",
        "• 奖励点位传送 (世界一 1win~200Kwins)",
        "• 奖励点位传送 (世界二 1Mwins~1Twins)",
        "• 世界切换 (World 1 / World 2)",
        "• 移动修改 (WalkSpeed/JumpPower/InfJump/NoClip/Fly)",
        "• Anti-AFK",
        "",
        "快捷键:",
        "  RightShift - 隐藏/显示 UI",
        "  T - 世界一循环下一点",
        "  Y - 传送到世界二",
        "  U - 传送到世界一",
        "",
        "注意: 传送需解锁对应世界",
        "      点位传送为本地坐标瞬移",
        "      世界切换使用 RemoteEvent",
    }, "\n"),
})

-- ── 快捷键绑定 ──
local keybinds = {
    [Enum.KeyCode.T] = function()
        local nextIdx = currentPointIndex + 1
        if nextIdx > #WORLD1_POINTS then nextIdx = 1 end
        currentPointIndex = nextIdx
        local p = WORLD1_POINTS[currentPointIndex]
        w1Dropdown:Set(p.Name)
        teleportTo(p.Pos)
        notify("T 快捷键", "→ " .. p.Name, 1.5, "Info")
    end,
    [Enum.KeyCode.Y] = function()
        fireTeleportWorld(2)
    end,
    [Enum.KeyCode.U] = function()
        fireTeleportWorld(1)
    end,
}

local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local key = input.KeyCode
    -- RightShift 由库内部处理，这里只绑定额外快捷键
    for k, cb in pairs(keybinds) do
        if key == k then
            task.spawn(cb)
            break
        end
    end
end)

-- ── 清理函数 ──
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    if inputConn then inputConn:Disconnect() end
    if noclipConn then noclipConn:Disconnect() end
    if infJumpConn then infJumpConn:Disconnect() end
    if flyConn then flyConn:Disconnect() end
    if antiAFKConn then antiAFKConn:Disconnect() end

    if flyBV then flyBV:Destroy() end
    if flyBG then flyBG:Destroy() end

    SETTINGS.ME_WalkSpeed = false
    SETTINGS.ME_JumpPower = false
    SETTINGS.ME_InfJump = false
    SETTINGS.ME_NoClip = false
    SETTINGS.ME_Fly = false
    SETTINGS.ME_AntiAFK = false

    setWalkSpeed(false, 16)
    setJumpPower(false, 50)

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Monkey Escape",
            Text  = "脚本已卸载",
            Duration = 2
        })
    end)
end

_G.MonkeyEscape_Cleanup = cleanup

-- ── 完成通知 ──
task.wait(0.5)
notify("Monkey Escape v1.0", "Active +1 Speed Monkey Escape 辅助已加载\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[MonkeyEscape] %s (PlaceId: %d) 辅助加载完成", GameName, PlaceId))
