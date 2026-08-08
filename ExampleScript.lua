--[[
    ============================================================
     Quantum UI Library - Full Example Script Hub
     Library Source:
       https://raw.githubusercontent.com/logz-c/logz-ui-lib/refs/heads/main/Source.lua
     Covers:
       Window / Multiple Tabs / All Element Types / Config System
       Notifications / Theme Customization / Background / Keybinds
    ============================================================
--]]

-- ══════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD — prevent duplicate injections
-- ══════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

-- Method 1: Destroy via _G global (shared across loadstring calls)
if _G.QuantumUI_Instance then
    pcall(function() _G.QuantumUI_Instance:Destroy() end)
    _G.QuantumUI_Instance = nil
end

-- Method 2: Scan CoreGui for orphaned QuantumUI ScreenGuis
for _, child in ipairs(CoreGui:GetChildren()) do
    if child:IsA("ScreenGui") and child.Name:sub(1, 9) == "QuantumUI_" then
        pcall(function() child:Destroy() end)
    end
end

-- Method 3: Clear any global window reference
if _G.QuantumUI_Window then
    pcall(function() _G.QuantumUI_Window:Destroy() end)
    _G.QuantumUI_Window = nil
end

-- ══════════════════════════════════════════════════════════════
-- 1. LOAD LIBRARY
-- ══════════════════════════════════════════════════════════════
local success, QuantumUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/logz-ui-lib/refs/heads/main/Source.lua"))()
end)

if not success then
    warn("[Script Hub] Failed to load Quantum UI library:", QuantumUI)
    return
end

print("[Script Hub] Quantum UI v" .. QuantumUI.Version .. " loaded.")

-- ══════════════════════════════════════════════════════════════
-- 2. CREATE MAIN WINDOW
-- ══════════════════════════════════════════════════════════════
local Window = QuantumUI.new({
    Title = "Quantum Script Hub",
    Subtitle = "Full Example v1.0",
    ThemeColor = Color3.fromRGB(0, 200, 255),   -- 主色调：青色
    Transparency = 0.3,                          -- 背景透明度
    Size = UDim2.new(0, 620, 0, 480),            -- 窗口大小
    Keybind = Enum.KeyCode.RightControl,          -- UI 切换快捷键
    -- 可选：自定义背景图
    -- BackgroundImage = "rbxassetid://1234567890",
    -- BackgroundTransparency = 0.5
})

-- 等待启动动画（3.5 秒），之后再添加 Tab
task.wait(3.5)

-- 注册全局窗口引用，防止重复注入
_G.QuantumUI_Window = Window

-- ══════════════════════════════════════════════════════════════
-- 3. SERVICES & UTILITIES
-- ══════════════════════════════════════════════════════════════
local Players        = game:GetService("Players")
local Lighting       = game:GetService("Lighting")
local UIS            = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local TeleportService= game:GetService("TeleportService")
local LocalPlayer    = Players.LocalPlayer

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end
local function getHumanoid()
    local char = getCharacter()
    return char:FindFirstChildOfClass("Humanoid")
end
local function notify(title, content, duration, ntype)
    Window:Notify({
        Title    = title,
        Content  = content,
        Duration = duration or 4,
        Type     = ntype or "Info"
    })
end

-- ══════════════════════════════════════════════════════════════
-- 4. MAIN TAB (核心功能)
-- ══════════════════════════════════════════════════════════════
local MainTab = Window:AddTab({
    Name = "Main",
    Icon = "rbxassetid://6034287594"
})

-- ---------------- 角色移动 ----------------
MainTab:AddSection({ Name = "🏃 Movement" })

MainTab:AddSlider({
    Name = "WalkSpeed",
    Min = 16, Max = 500, Default = 16, Increment = 1,
    Suffix = " studs/s",
    Flag = "Movement_WalkSpeed",
    Callback = function(value)
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = value end
    end
})

MainTab:AddSlider({
    Name = "JumpPower",
    Min = 50, Max = 500, Default = 50, Increment = 1,
    Suffix = "",
    Flag = "Movement_JumpPower",
    Callback = function(value)
        local hum = getHumanoid()
        if hum then hum.JumpPower = value end
    end
})

MainTab:AddToggle({
    Name = "Infinite Jump",
    Default = false,
    Flag = "Movement_InfiniteJump",
    Callback = function(state)
        _G.InfiniteJumpEnabled = state
    end
})

-- 无限跳处理
UIS.JumpRequest:Connect(function()
    if _G.InfiniteJumpEnabled then
        local hum = getHumanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

MainTab:AddToggle({
    Name = "No Clip",
    Default = false,
    Flag = "Movement_NoClip",
    Callback = function(state)
        _G.NoClipEnabled = state
    end
})

-- NoClip 处理（RenderStepped 遍历 BasePart CanCollide）
local noclipConn
_G.NoclipStored = {}
RunService.RenderStepped:Connect(function()
    if not _G.NoClipEnabled then
        if noclipConn then
            for part, orig in pairs(_G.NoclipStored) do
                pcall(function() part.CanCollide = orig end)
            end
            table.clear(_G.NoclipStored)
            noclipConn = nil
        end
        return
    end
    local char = LocalPlayer.Character
    if not char then return end
    for _, v in pairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            if not _G.NoclipStored[v] then
                _G.NoclipStored[v] = v.CanCollide
            end
            v.CanCollide = false
        end
    end
end)

-- ---------------- 战斗 ----------------
MainTab:AddSection({ Name = "⚔️ Combat" })

MainTab:AddToggle({
    Name = "God Mode",
    Default = false,
    Flag = "Combat_GodMode",
    Callback = function(state)
        local hum = getHumanoid()
        if hum then
            hum.MaxHealth = state and math.huge or 100
            hum.Health    = state and math.huge or hum.MaxHealth
        end
    end
})

MainTab:AddSlider({
    Name = "Damage Multiplier",
    Min = 1, Max = 20, Default = 1, Increment = 0.5,
    Suffix = "x",
    Flag = "Combat_DmgMult",
    Callback = function(value)
        _G.DamageMult = value
    end
})

-- ---------------- 快捷键 ----------------
MainTab:AddSection({ Name = "⌨️ Keybinds" })

MainTab:AddKeybind({
    Name = "Fly Toggle",
    Default = Enum.KeyCode.F,
    Flag = "Keybind_Fly",
    ChangedCallback = function(key)
        notify("Keybind Updated", "Fly key changed to: " .. key.Name, 3, "Info")
    end,
    Callback = function()
        _G.FlyEnabled = not _G.FlyEnabled
        notify("Fly", _G.FlyEnabled and "Enabled" or "Disabled", 2,
               _G.FlyEnabled and "Success" or "Warning")
    end
})

MainTab:AddKeybind({
    Name = "Toggle UI",
    Default = Enum.KeyCode.RightShift,
    Flag = "Keybind_ToggleUI",
    Callback = function()
        -- RightShift 也能切换 UI（附加快捷键）
        if Window.Minimized then
            Window:RestoreFromMinimize()
        else
            Window:MinimizeToButton()
        end
    end
})

-- ---------------- 操作按钮 ----------------
MainTab:AddSection({ Name = "🎮 Actions" })

MainTab:AddButton({
    Name = "🔄 Rejoin Server",
    Callback = function()
        notify("Rejoining...", "Teleporting you back to server.", 2, "Info")
        task.wait(0.6)
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
})

MainTab:AddButton({
    Name = "💀 Reset Character",
    Callback = function()
        local hum = getHumanoid()
        if hum then hum.Health = 0 end
        notify("Reset", "Character has been reset.", 2, "Warning")
    end
})

-- ══════════════════════════════════════════════════════════════
-- 5. VISUALS TAB (视觉 / ESP)
-- ══════════════════════════════════════════════════════════════
local VisualsTab = Window:AddTab({
    Name = "Visuals",
    Icon = "rbxassetid://6034509993"
})

-- ---------------- ESP 设置 ----------------
VisualsTab:AddSection({ Name = "👁️ ESP Settings" })

VisualsTab:AddToggle({
    Name = "Player ESP (Box)",
    Default = false,
    Flag = "Visuals_PlayerESP",
    Callback = function(state)
        _G.PlayerESPEnabled = state
    end
})

VisualsTab:AddToggle({
    Name = "Show Names",
    Default = true,
    Flag = "Visuals_ShowNames",
    Callback = function(state) _G.ShowESPNames = state end
})

VisualsTab:AddToggle({
    Name = "Show Distance",
    Default = true,
    Flag = "Visuals_ShowDistance",
    Callback = function(state) _G.ESPDistance = state end
})

VisualsTab:AddColorPicker({
    Name = "Team Color",
    Default = Color3.fromRGB(0, 200, 255),
    Presets = {
        Color3.fromRGB(0, 200, 255),
        Color3.fromRGB(0, 255, 100),
        Color3.fromRGB(255, 200, 0),
    },
    Flag = "Visuals_TeamColor",
    Callback = function(color) _G.TeamESPColor = color end
})

VisualsTab:AddColorPicker({
    Name = "Enemy Color",
    Default = Color3.fromRGB(255, 80, 80),
    Flag = "Visuals_EnemyColor",
    Callback = function(color) _G.EnemyESPColor = color end
})

VisualsTab:AddDropdown({
    Name = "Box Style",
    Items = {"2D Box", "Corner", "3D Box", "Outline"},
    Default = "2D Box",
    Flag = "Visuals_BoxStyle",
    Callback = function(selected)
        print("ESP Box Style:", selected)
    end
})

VisualsTab:AddSlider({
    Name = "ESP Max Distance",
    Min = 50, Max = 5000, Default = 1500, Increment = 50,
    Suffix = " studs",
    Flag = "Visuals_ESP_MaxDist",
    Callback = function(value) _G.ESPMaxDistance = value end
})

-- ---------------- 世界环境 ----------------
VisualsTab:AddSection({ Name = "🌍 World / Lighting" })

VisualsTab:AddToggle({
    Name = "Fullbright",
    Default = false,
    Flag = "World_Fullbright",
    Callback = function(state)
        Lighting.Brightness = state and 3 or 1
        Lighting.Ambient    = state and Color3.fromRGB(200, 200, 200)
                                         or Color3.fromRGB(80, 80, 80)
    end
})

VisualsTab:AddSlider({
    Name = "Clock Time",
    Min = 0, Max = 24, Default = 14, Increment = 0.5,
    Suffix = "h",
    Flag = "World_ClockTime",
    Callback = function(value) Lighting.ClockTime = value end
})

VisualsTab:AddSlider({
    Name = "Fog Start",
    Min = 0, Max = 2000, Default = 500, Increment = 10,
    Suffix = "",
    Flag = "World_FogStart",
    Callback = function(value) Lighting.FogStart = value end
})

VisualsTab:AddDropdown({
    Name = "Skybox",
    Items = {"Default", "Sunset", "Night", "Space", "Neon"},
    Default = "Default",
    Flag = "World_Skybox",
    Callback = function(selected)
        local skyboxes = {
            Sunset = { Top = Color3.fromRGB(255,150,50), Bottom = Color3.fromRGB(120,30,80) },
            Night  = { Top = Color3.fromRGB(10,10,40),   Bottom = Color3.fromRGB(30,30,70)  },
            Space  = { Top = Color3.fromRGB(0,0,0),      Bottom = Color3.fromRGB(5,5,20)   },
            Neon   = { Top = Color3.fromRGB(80,0,120),   Bottom = Color3.fromRGB(0,80,120) },
        }
        local sk = skyboxes[selected]
        if sk then
            Lighting:SetMinutesAfterMidnight(12 * 60)
            Lighting.OutdoorAmbient = sk.Bottom
            Lighting.ColorShift_Top = sk.Top
        else
            Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 80)
            Lighting.ColorShift_Top = Color3.fromRGB(200, 200, 200)
        end
        notify("Skybox", "Applied: " .. selected, 2.5, "Success")
    end
})

-- ---------------- 自定义背景 ----------------
VisualsTab:AddSection({ Name = "🖼️ Custom Background" })

local bgTextbox = VisualsTab:AddTextbox({
    Name = "Background Image ID",
    Placeholder = "rbxassetid://...",
    Default = "rbxassetid://11112222333",
    Flag = "Visuals_BgId",
    Callback = function(text) _G.CurrentBgId = text end
})

VisualsTab:AddButton({
    Name = "✅ Apply Background",
    Callback = function()
        local currentBg = bgTextbox and bgTextbox:Get() or _G.CurrentBgId or ""
        if currentBg == "" then
            notify("Error", "Enter an asset ID first!", 3, "Error")
            return
        end
        Window:SetBackground(currentBg, 0.6)
        notify("Background", "Applied!", 3, "Success")
    end
})

VisualsTab:AddButton({
    Name = "❌ Remove Background",
    Callback = function()
        Window:RemoveBackground()
    end
})

-- ══════════════════════════════════════════════════════════════
-- 6. MISC TAB (杂项 / 文本 / 段落)
-- ══════════════════════════════════════════════════════════════
local MiscTab = Window:AddTab({
    Name = "Misc",
    Icon = "rbxassetid://6031280882"
})

MiscTab:AddSection({ Name = "📝 Textbox Examples" })

MiscTab:AddTextbox({
    Name = "Command Input",
    Placeholder = "Type command...",
    Default = "",
    ClearOnFocus = false,
    Flag = "Misc_CmdBox",
    Callback = function(text, enterPressed)
        if enterPressed and text ~= "" then
            notify("Command", "Executed: " .. text, 3, "Info")
        end
    end
})

MiscTab:AddTextbox({
    Name = "Player Name",
    Placeholder = "Target player",
    Flag = "Misc_Target",
    Callback = function(text) print("Target:", text) end
})

MiscTab:AddSection({ Name = "📄 Information" })

MiscTab:AddParagraph({
    Title = "How to use",
    Content = table.concat({
        "1. Press [RightControl] to show/hide UI.",
        "2. Adjust toggles/sliders on each tab.",
        "3. Use the Settings tab to save/load your configs.",
        "4. Use Flag on elements to enable config persistence.",
    }, "\n")
})

MiscTab:AddParagraph({
    Title = "Changelog",
    Content = "• v1.0  - Initial release\n" ..
              "• Added all UI element showcases\n" ..
              "• Fixed Tab text clipping (v2.4+)"
})

MiscTab:AddLabel({ Text = "Tip: Click the Save button in Settings after making changes!" })

MiscTab:AddSection({ Name = "🌈 Rainbow Border" })

MiscTab:AddToggle({
    Name = "Rainbow Animation",
    Default = true,
    Callback = function(state)
        QuantumUI.RainbowEnabled = state
    end
})

MiscTab:AddSlider({
    Name = "Rainbow Speed",
    Min = 0.1, Max = 5, Default = 1, Increment = 0.1,
    Suffix = "x",
    Callback = function(value) QuantumUI.RainbowSpeed = value end
})

MiscTab:AddDropdown({
    Name = "Preset Theme",
    Items = {"Cyan", "Purple", "Green", "Red", "Gold", "Pink"},
    Default = "Cyan",
    Multi = false,
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
            notify("Theme", "Applied " .. selected, 2, "Success")
        end
    end
})

-- ══════════════════════════════════════════════════════════════
-- 7. MULTI-SELECT DROPDOWN EXAMPLE
-- ══════════════════════════════════════════════════════════════
local ToolsTab = Window:AddTab({
    Name = "Tools",
    Icon = "rbxassetid://6034281467"
})

ToolsTab:AddSection({ Name = "🛠️ Tool Selection (Multi)" })

ToolsTab:AddDropdown({
    Name = "Enabled Features",
    Items = {"AutoCollect", "AutoFarm", "AutoSell", "AutoQuest", "AutoUpgrade", "AntiAFK"},
    Multi = true,
    Default = {"AutoCollect", "AntiAFK"},
    Flag = "Tools_Features",
    Callback = function(selectedTable)
        -- selectedTable = { AutoCollect = true, AntiAFK = true, ... }
        local list = {}
        for name, enabled in pairs(selectedTable) do
            if enabled then table.insert(list, name) end
        end
        print("[Tools] Enabled:", table.concat(list, ", "))
    end
})

ToolsTab:AddSection({ Name = "🎯 Quick Toggles" })

ToolsTab:AddToggle({
    Name = "Auto Collect Drops",
    Default = false,
    Flag = "Tools_AutoCollect",
    Callback = function(state)
        _G.AutoCollect = state
        notify("AutoCollect", state and "ON" or "OFF", 2,
               state and "Success" or "Warning")
    end
})

ToolsTab:AddToggle({
    Name = "Anti AFK",
    Default = false,
    Flag = "Tools_AntiAFK",
    Callback = function(state)
        _G.AntiAFK = state
    end
})

-- Anti AFK 处理：周期模拟按键
task.spawn(function()
    while true do
        task.wait(60)
        if _G.AntiAFK then
            LocalPlayer.Idled:Fire()
        end
    end
end)

ToolsTab:AddSlider({
    Name = "Auto-Farm Interval",
    Min = 0.05, Max = 5, Default = 0.5, Increment = 0.05,
    Suffix = "s",
    Flag = "Tools_FarmInterval",
    Callback = function(v) _G.FarmInterval = v end
})

-- ══════════════════════════════════════════════════════════════
-- 8. WELCOME NOTIFICATION (加载完成提示)
-- ══════════════════════════════════════════════════════════════
task.wait(0.3)
notify("✅ Script Loaded!",
    "Quantum Script Hub is ready.\n" ..
    "Press RightControl to toggle UI.\n" ..
    "Go to Settings to save your config!",
    6, "Success")

print("[Script Hub] Ready.")
