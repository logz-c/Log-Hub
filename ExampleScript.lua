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
-- 7. KEY AUTH TAB - 密钥输入 / HWID 展示（配合 QuantumUI.SetupKeyAuth 使用）
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
