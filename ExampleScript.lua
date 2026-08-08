--[[
    ============================================================
     Quantum UI Library - API 展示脚本 (纯演示，无真实功能)
     所有回调仅 print 到后台控制台

     Library Source:
       https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua
    ============================================================
--]]

-- ══════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD — 防止重复注入
-- ══════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

if _G.QuantumUI_Instance then
    pcall(function() _G.QuantumUI_Instance:Destroy() end)
    _G.QuantumUI_Instance = nil
end
for _, child in ipairs(CoreGui:GetChildren()) do
    if child:IsA("ScreenGui") and child.Name:sub(1, 9) == "QuantumUI_" then
        pcall(function() child:Destroy() end)
    end
end
if _G.QuantumUI_Window then
    pcall(function() _G.QuantumUI_Window:Destroy() end)
    _G.QuantumUI_Window = nil
end

-- ══════════════════════════════════════════════════════════════
-- 1. LOAD LIBRARY
-- ══════════════════════════════════════════════════════════════
local success, QuantumUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"))()
end)

if not success then
    warn("[API Demo] 加载 Quantum UI 库失败:", QuantumUI)
    return
end

print("[API Demo] Quantum UI v" .. QuantumUI.Version .. " 加载成功")

-- ══════════════════════════════════════════════════════════════
-- 2. KEY AUTH — 可选：启用密钥授权（脚本开发者使用）
-- ══════════════════════════════════════════════════════════════
-- 方式 A: 启动时强制门控（未授权弹窗阻塞，直到通过/Cancel 销毁 UI）
-- QuantumUI.RequireKeyAuth({
--     -- 推荐哈希模式：key 放源码里别人搜不到
--     Hashes = {
--         -- 用 QuantumUI.HashKey("DEMO-KEY-1234") 预生成：
--         QuantumUI.HashKey("QUANTUM-2024-ALPHA-001"),
--         QuantumUI.HashKey("QUANTUM-2024-ALPHA-002"),
--     },
--     BindToHWID = true,      -- 首次激活绑定 HWID（防止一人发群）
--     AllowTrial = true,      -- 允许试用
--     TrialSeconds = 600,     -- 试用时长 10 分钟
--     HWIDWhitelist = {       -- 开发者自己的 HWID 免绑定
--         -- QuantumUI.GetHWID() 可以在控制台打印自己的 HWID
--     },
--     OnSuccess = function(key)
--         print("[KeyAuth] 授权成功, key =", key)
--     end,
--     OnFail = function(reason)
--         warn("[KeyAuth] 授权失败:", reason)
--     end,
-- })
--
-- 方式 B: 先 SetupKeyAuth（不强制 gate），在界面里 AddKeyAuth 元素让用户输入
-- QuantumUI.SetupKeyAuth({
--     Keys = {"PLAINTEXT-KEY-EXAMPLE"},
--     BindToHWID = true,
-- })

-- ══════════════════════════════════════════════════════════════
-- 3. CREATE MAIN WINDOW
-- ══════════════════════════════════════════════════════════════
local Window = QuantumUI.new({
    Title = "Quantum API Demo",
    Subtitle = "纯接口展示 (无真实功能)",
    ThemeColor = Color3.fromRGB(0, 200, 255),
    Transparency = 0.3,
    Size = UDim2.new(0, 620, 0, 480),
    Keybind = Enum.KeyCode.RightControl,
})

task.wait(3.5)
_G.QuantumUI_Window = Window

-- ══════════════════════════════════════════════════════════════
-- 3. MAIN TAB - 滑块 / 开关 / 按钮 API
-- ══════════════════════════════════════════════════════════════
local MainTab = Window:AddTab({
    Name = "Main",
    Icon = "rbxassetid://6034287594",
})

MainTab:AddSection({ Name = "Section: AddSlider" })

MainTab:AddSlider({
    Name = "Slider Demo (整数)",
    Min = 0, Max = 100, Default = 50, Increment = 1,
    Suffix = "%",
    Flag = "Demo_SliderInt",
    Callback = function(value)
        print("[API Demo] Slider (整数) 值变更:", value)
    end,
})

MainTab:AddSlider({
    Name = "Slider Demo (浮点)",
    Min = 0, Max = 10, Default = 5, Increment = 0.1,
    Suffix = "x",
    Flag = "Demo_SliderFloat",
    Callback = function(value)
        print("[API Demo] Slider (浮点) 值变更:", value)
    end,
})

MainTab:AddSection({ Name = "Section: AddToggle" })

MainTab:AddToggle({
    Name = "Toggle Demo A",
    Default = false,
    Flag = "Demo_ToggleA",
    Callback = function(state)
        print("[API Demo] Toggle A 状态变更:", state)
    end,
})

MainTab:AddToggle({
    Name = "Toggle Demo B",
    Default = true,
    Flag = "Demo_ToggleB",
    Callback = function(state)
        print("[API Demo] Toggle B 状态变更:", state)
    end,
})

MainTab:AddSection({ Name = "Section: AddButton" })

MainTab:AddButton({
    Name = "Button Demo (打印)",
    Callback = function()
        print("[API Demo] Button 被点击")
    end,
})

MainTab:AddButton({
    Name = "Button Demo (通知)",
    Callback = function()
        Window:Notify({
            Title = "API Demo",
            Content = "这是一个通知示例",
            Duration = 3,
            Type = "Info",
        })
        print("[API Demo] Button 触发通知")
    end,
})

-- ══════════════════════════════════════════════════════════════
-- 4. VISUALS TAB - 颜色选择器 / 下拉框 API
-- ══════════════════════════════════════════════════════════════
local VisualsTab = Window:AddTab({
    Name = "Visuals",
    Icon = "rbxassetid://6034509993",
})

VisualsTab:AddSection({ Name = "Section: AddColorPicker" })

VisualsTab:AddColorPicker({
    Name = "ColorPicker Demo (带预设)",
    Default = Color3.fromRGB(0, 200, 255),
    Presets = {
        Color3.fromRGB(0, 200, 255),
        Color3.fromRGB(0, 255, 100),
        Color3.fromRGB(255, 200, 0),
    },
    Flag = "Demo_ColorPickerA",
    Callback = function(color)
        print("[API Demo] ColorPicker A 选色:", color)
    end,
})

VisualsTab:AddColorPicker({
    Name = "ColorPicker Demo (无预设)",
    Default = Color3.fromRGB(255, 80, 80),
    Flag = "Demo_ColorPickerB",
    Callback = function(color)
        print("[API Demo] ColorPicker B 选色:", color)
    end,
})

VisualsTab:AddSection({ Name = "Section: AddDropdown (单选)" })

VisualsTab:AddDropdown({
    Name = "Dropdown Demo (单选)",
    Items = {"选项 A", "选项 B", "选项 C", "选项 D"},
    Default = "选项 A",
    Flag = "Demo_DropdownSingle",
    Callback = function(selected)
        print("[API Demo] Dropdown (单选) 选中:", selected)
    end,
})

VisualsTab:AddSection({ Name = "Section: AddDropdown (多选)" })

VisualsTab:AddDropdown({
    Name = "Dropdown Demo (多选)",
    Items = {"AutoFarm", "AutoQuest", "AutoSell", "AntiAFK"},
    Multi = true,
    Default = {"AutoFarm", "AntiAFK"},
    Flag = "Demo_DropdownMulti",
    Callback = function(selectedTable)
        local list = {}
        for name, enabled in pairs(selectedTable) do
            if enabled then table.insert(list, name) end
        end
        print("[API Demo] Dropdown (多选) 选中:", table.concat(list, ", "))
    end,
})

-- ══════════════════════════════════════════════════════════════
-- 5. MISC TAB - 文本框 / 段落 / 标签 / 快捷键 API
-- ══════════════════════════════════════════════════════════════
local MiscTab = Window:AddTab({
    Name = "Misc",
    Icon = "rbxassetid://6031280882",
})

MiscTab:AddSection({ Name = "Section: AddTextbox" })

MiscTab:AddTextbox({
    Name = "Textbox Demo (回车触发)",
    Placeholder = "输入文字后按回车...",
    Default = "",
    ClearOnFocus = false,
    Flag = "Demo_TextboxEnter",
    Callback = function(text, enterPressed)
        print("[API Demo] Textbox 内容:", text, "| 回车:", enterPressed)
    end,
})

MiscTab:AddTextbox({
    Name = "Textbox Demo (实时)",
    Placeholder = "实时输出...",
    Flag = "Demo_TextboxLive",
    Callback = function(text)
        print("[API Demo] Textbox (实时):", text)
    end,
})

MiscTab:AddSection({ Name = "Section: AddKeybind" })

MiscTab:AddKeybind({
    Name = "Keybind Demo",
    Default = Enum.KeyCode.F,
    Flag = "Demo_Keybind",
    ChangedCallback = function(key)
        print("[API Demo] Keybind 已改绑:", key.Name)
    end,
    Callback = function()
        print("[API Demo] Keybind 按键触发")
    end,
})

MiscTab:AddSection({ Name = "Section: AddParagraph / AddLabel" })

MiscTab:AddParagraph({
    Title = "段落标题 (AddParagraph)",
    Content = table.concat({
        "这是 AddParagraph 的内容区域。",
        "支持多行文本，用 \\n 分隔。",
        "",
        "此脚本仅展示 Quantum UI 的 API 接口，",
        "所有回调仅 print 到后台控制台。",
    }, "\n"),
})

MiscTab:AddLabel({ Text = "这是一个标签 (AddLabel)" })

-- ══════════════════════════════════════════════════════════════
-- 6. TOOLS TAB - 主题 / 彩虹边框 API
-- ══════════════════════════════════════════════════════════════
local ToolsTab = Window:AddTab({
    Name = "Tools",
    Icon = "rbxassetid://6034281467",
})

ToolsTab:AddSection({ Name = "Section: 彩虹边框" })

ToolsTab:AddToggle({
    Name = "Rainbow Animation",
    Default = true,
    Flag = "Demo_Rainbow",
    Callback = function(state)
        QuantumUI.RainbowEnabled = state
        print("[API Demo] 彩虹边框:", state and "ON" or "OFF")
    end,
})

ToolsTab:AddSlider({
    Name = "Rainbow Speed",
    Min = 0.1, Max = 5, Default = 1, Increment = 0.1,
    Suffix = "x",
    Flag = "Demo_RainbowSpeed",
    Callback = function(value)
        QuantumUI.RainbowSpeed = value
        print("[API Demo] 彩虹速度:", value)
    end,
})

ToolsTab:AddSection({ Name = "Section: 主题预设" })

ToolsTab:AddDropdown({
    Name = "Preset Theme",
    Items = {"Cyan", "Purple", "Green", "Red", "Gold", "Pink"},
    Default = "Cyan",
    Multi = false,
    Flag = "Demo_ThemePreset",
    Callback = function(selected)
        local themes = {
            Cyan   = Color3.fromRGB(0, 200, 255),
            Purple = Color3.fromRGB(180, 60, 255),
            Green  = Color3.fromRGB(0, 255, 120),
            Red    = Color3.fromRGB(255, 70, 90),
            Gold   = Color3.fromRGB(255, 200, 50),
            Pink   = Color3.fromRGB(255, 105, 180),
        }
        local color = themes[selected]
        if color then
            Window.ThemeColor = color
            QuantumUI.ThemeColor = color
            print("[API Demo] 主题切换:", selected)
        end
    end,
})

ToolsTab:AddSection({ Name = "Section: 背景 API" })

local bgTextbox = ToolsTab:AddTextbox({
    Name = "Background Image ID",
    Placeholder = "rbxassetid://...",
    Default = "",
    Flag = "Demo_BgId",
    Callback = function(text)
        print("[API Demo] 背景图ID输入:", text)
    end,
})

ToolsTab:AddButton({
    Name = "Apply Background",
    Callback = function()
        local id = bgTextbox and bgTextbox:Get() or ""
        if id == "" then
            print("[API Demo] 背景ID为空，未应用")
            return
        end
        Window:SetBackground(id, 0.6)
        print("[API Demo] 背景已应用:", id)
    end,
})

ToolsTab:AddButton({
    Name = "Remove Background",
    Callback = function()
        Window:RemoveBackground()
        print("[API Demo] 背景已移除")
    end,
})

-- ══════════════════════════════════════════════════════════════
-- 7. MOVEMENT TAB - 移动类功能（WalkSpeed / JumpPower / InfJump / NoClip / Fly / TP）
-- ══════════════════════════════════════════════════════════════
local MovementTab = Window:AddTab({
    Name = "Movement",
    Icon = "rbxassetid://6034466796",
})

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- 全局状态
local movementState = {
    WalkSpeed = 16,
    JumpPower = 50,
    SetWalkSpeed = false,
    SetJumpPower = false,
    InfJump = false,
    NoClip = false,
    FlyEnabled = false,
    FlySpeed = 50,
}

-- 辅助：获取角色
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

-- ═══ WalkSpeed ═══
MovementTab:AddSection({ Name = "WalkSpeed" })

MovementTab:AddSlider({
    Name = "WalkSpeed Value",
    Min = 16, Max = 500, Default = 16, Increment = 1,
    Suffix = "",
    Flag = "Move_WalkSpeed",
    Callback = function(value)
        movementState.WalkSpeed = value
    end,
})

MovementTab:AddToggle({
    Name = "Enable WalkSpeed",
    Default = false,
    Flag = "Move_WalkSpeedEnabled",
    Callback = function(state)
        movementState.SetWalkSpeed = state
        if state then
            task.spawn(function()
                while movementState.SetWalkSpeed do
                    local hum = getHum()
                    if hum and hum.Health > 0 and hum.WalkSpeed ~= movementState.WalkSpeed then
                        hum.WalkSpeed = movementState.WalkSpeed
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
MovementTab:AddSection({ Name = "JumpPower" })

MovementTab:AddSlider({
    Name = "JumpPower Value",
    Min = 50, Max = 500, Default = 50, Increment = 1,
    Suffix = "",
    Flag = "Move_JumpPower",
    Callback = function(value)
        movementState.JumpPower = value
    end,
})

MovementTab:AddToggle({
    Name = "Enable JumpPower",
    Default = false,
    Flag = "Move_JumpPowerEnabled",
    Callback = function(state)
        movementState.SetJumpPower = state
        if state then
            task.spawn(function()
                while movementState.SetJumpPower do
                    local hum = getHum()
                    if hum and hum.Health > 0 and hum.JumpPower ~= movementState.JumpPower then
                        hum.JumpPower = movementState.JumpPower
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
MovementTab:AddSection({ Name = "Infinite Jump" })

MovementTab:AddToggle({
    Name = "Infinite Jump",
    Default = false,
    Flag = "Move_InfJump",
    Callback = function(state)
        movementState.InfJump = state
        if state then
            local conn
            conn = UserInputService.JumpRequest:Connect(function()
                if not movementState.InfJump then
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
MovementTab:AddSection({ Name = "NoClip" })

MovementTab:AddToggle({
    Name = "NoClip (穿墙)",
    Default = false,
    Flag = "Move_NoClip",
    Callback = function(state)
        movementState.NoClip = state
        if state then
            task.spawn(function()
                local conn
                conn = RunService.Stepped:Connect(function()
                    if not movementState.NoClip then
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
            -- 恢复碰撞
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
    Name = "Fly Speed",
    Min = 10, Max = 300, Default = 50, Increment = 5,
    Suffix = "",
    Flag = "Move_FlySpeed",
    Callback = function(value)
        movementState.FlySpeed = value
    end,
})

MovementTab:AddKeybind({
    Name = "Fly Toggle Key",
    Default = Enum.KeyCode.F,
    Flag = "Move_FlyKey",
    Callback = function()
        movementState.FlyEnabled = not movementState.FlyEnabled
        if movementState.FlyEnabled then
            task.spawn(function()
                local flyConn
                local flyBV, flyBG
                local function startFly()
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
                end
                local function stopFly()
                    local hum = getHum()
                    if hum then hum.PlatformStand = false end
                    if flyBV then flyBV:Destroy() end
                    if flyBG then flyBG:Destroy() end
                end
                startFly()
                flyConn = RunService.RenderStepped:Connect(function()
                    if not movementState.FlyEnabled then
                        flyConn:Disconnect()
                        stopFly()
                        return
                    end
                    local root = getRoot()
                    local cam = workspace.CurrentCamera
                    if not root or not cam then return end
                    local dir = Vector3.zero
                    local cf = cam.CFrame
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
                    if flyBV then
                        flyBV.Velocity = dir * movementState.FlySpeed
                    end
                    if flyBG then
                        flyBG.CFrame = cam.CFrame
                    end
                end)
            end)
            Window:Notify({
                Title = "Fly",
                Content = "飞行已开启 (WASD移动 / Space上升 / Shift下降)",
                Duration = 3,
                Type = "Info",
            })
        else
            local hum = getHum()
            if hum then hum.PlatformStand = false end
            Window:Notify({
                Title = "Fly",
                Content = "飞行已关闭",
                Duration = 2,
                Type = "Info",
            })
        end
    end,
})

-- ═══ Teleport (BABFT 农场坐标) ═══
MovementTab:AddSection({ Name = "Teleport (BABFT 坐标)" })

local tpLocations = {
    { Name = "起点", Pos = CFrame.new(-25.1, 63.0, 1152.7) },
    { Name = "中段", Pos = CFrame.new(-25.1, 81.0, 1777.4) },
    { Name = "终点附近", Pos = CFrame.new(-25.1, 68.5, 2576.7) },
    { Name = "宝藏区", Pos = CFrame.new(-25.1, 114.3, 3195.2) },
    { Name = "地面 (spawn)", Pos = CFrame.new(-55.7, 70.7, 125) },
    { Name = "地下宝藏", Pos = CFrame.new(-55.7, -360.7, 9492.4) },
}

MovementTab:AddDropdown({
    Name = "Select Location",
    Items = (function()
        local names = {}
        for _, loc in ipairs(tpLocations) do
            table.insert(names, loc.Name)
        end
        return names
    end)(),
    Default = "起点",
    Multi = false,
    Flag = "Move_TPLocation",
    Callback = function(selected)
        for _, loc in ipairs(tpLocations) do
            if loc.Name == selected then
                movementState._SelectedTP = loc
                break
            end
        end
    end,
})

MovementTab:AddButton({
    Name = "Teleport!",
    Callback = function()
        local target = movementState._SelectedTP or tpLocations[1]
        local char = getChar()
        if char and target then
            char:PivotTo(target.Pos)
            print("[API Demo] 传送到:", target.Name)
            Window:Notify({
                Title = "Teleport",
                Content = "已传送到: " .. target.Name,
                Duration = 2,
                Type = "Success",
            })
        else
            Window:Notify({
                Title = "Teleport",
                Content = "角色未找到",
                Duration = 2,
                Type = "Error",
            })
        end
    end,
})

-- ═══ Anti-AFK ═══
MovementTab:AddSection({ Name = "Anti-AFK" })

local antiAfkEnabled = false
local VirtualUser = game:GetService("VirtualUser")

MovementTab:AddToggle({
    Name = "Anti-AFK",
    Default = false,
    Flag = "Move_AntiAFK",
    Callback = function(state)
        antiAfkEnabled = state
    end,
})

LocalPlayer.Idled:Connect(function()
    if antiAfkEnabled then
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end
end)

-- ══════════════════════════════════════════════════════════════
-- 8. KEY AUTH TAB - 密钥输入 / HWID 展示（配合 QuantumUI.SetupKeyAuth 使用）
-- ══════════════════════════════════════════════════════════════
local KeyAuthTab = Window:AddTab({
    Name = "Access",
    Icon = "rbxassetid://6034284153",
})

KeyAuthTab:AddSection({ Name = "Section: 密钥授权" })

local keyAuthEl = KeyAuthTab:AddKeyAuth({
    Name = "密钥激活",
    Placeholder = "QUANTUM-XXXX-XXXX-XXXX",
    ShowHWID = true,
    Callback = function(ok, key, reason)
        print("[API Demo] AddKeyAuth 回调:", ok, key, reason)
        if ok then
            Window:Notify({
                Title = "授权成功",
                Content = "密钥已通过验证",
                Duration = 4,
                Type = "Success",
            })
        else
            Window:Notify({
                Title = "授权失败",
                Content = "请检查密钥是否正确",
                Duration = 4,
                Type = "Error",
            })
        end
    end,
})

KeyAuthTab:AddButton({
    Name = "打印当前 HWID (控制台)",
    Callback = function()
        print("[API Demo] 当前 HWID:", QuantumUI.GetHWID())
        print("[API Demo] 是否授权:", Window:IsKeyAuthorized())
    end,
})

KeyAuthTab:AddButton({
    Name = "预生成哈希 (HashKey 示例)",
    Callback = function()
        local samples = {
            "QUANTUM-2024-ALPHA-001",
            "QUANTUM-2024-ALPHA-002",
        }
        print("[API Demo] —— 预生成的 SHA-256 key 哈希 ——")
        for _, k in ipairs(samples) do
            print(("  [%s] -> %s"):format(k, QuantumUI.HashKey(k)))
        end
        Window:Notify({
            Title = "已生成",
            Content = "哈希值在控制台中查看",
            Duration = 4,
            Type = "Info",
        })
    end,
})

KeyAuthTab:AddButton({
    Name = "Reset 已保存的密钥",
    Callback = function()
        Window:ResetKeyAuth()
        keyAuthEl:Reset()
        Window:Notify({
            Title = "已重置",
            Content = "本地密钥文件已删除",
            Duration = 3,
            Type = "Warning",
        })
    end,
})

-- ══════════════════════════════════════════════════════════════
-- 8. 完成
-- ══════════════════════════════════════════════════════════════
task.wait(0.3)
Window:Notify({
    Title = "API Demo",
    Content = "纯接口展示已加载\n所有回调仅 print 到控制台\n按 RightControl 切换 UI",
    Duration = 6,
    Type = "Success",
})

print("[API Demo] 所有 API 元素已注册完毕")
