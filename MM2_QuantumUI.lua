--[[
    MM2 Hub | Murder Mystery 2 (Quantum UI 版)
    游戏：Murder Mystery 2 / 造船寻宝
    功能：Chams ESP、Role Detection (凶手/警长/无辜)、Gun ESP、Xray、Grab Gun、Rejoin
    快捷键：
        右 Shift  - 隐藏/显示 UI (可改)
        X         - Xray 开关 (可改)
        Settings Tab - 保存/加载配置
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD — 防止重复注入
-- ══════════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

if _G.MM2_QuantumUI_Window then
    pcall(function() _G.MM2_QuantumUI_Window:Destroy() end)
    _G.MM2_QuantumUI_Window = nil
end
if _G.QuantumUI_Instance then
    pcall(function() _G.QuantumUI_Instance:Destroy() end)
    _G.QuantumUI_Instance = nil
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
    warn("[MM2 Hub] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[MM2 Hub] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[MM2 Hub] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[MM2 Hub] Quantum UI v" .. QuantumUI.Version .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. ROBLOX SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UIS = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local Workspace = workspace

-- ══════════════════════════════════════════════════════════════════
-- 3. 预设颜色
-- ══════════════════════════════════════════════════════════════════
local PRESET_COLORS = {
    Color3.fromRGB(255, 60, 60),    -- 凶手红
    Color3.fromRGB(80, 150, 255),   -- 警长蓝
    Color3.fromRGB(0, 255, 100),    -- 无辜绿
    Color3.fromRGB(170, 120, 255),  -- Gun紫
    Color3.fromRGB(0, 200, 255),    -- 青色
    Color3.fromRGB(255, 200, 50),   -- 金色
    Color3.fromRGB(255, 105, 180),  -- 粉色
    Color3.fromRGB(255, 255, 255),  -- 白色
}

-- ══════════════════════════════════════════════════════════════════
-- 4. SETTINGS (通过 Flag 绑定到 Quantum UI 配置系统)
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- ESP
    ChamsESPEnabled = true,
    RoleESPEnabled = true,
    GunESPEnabled = true,
    XrayEnabled = false,

    -- Colors
    MurdererColor = Color3.fromRGB(255, 60, 60),
    SheriffColor = Color3.fromRGB(80, 150, 255),
    InnocentColor = Color3.fromRGB(0, 255, 100),
    GunColor = Color3.fromRGB(170, 120, 255),

    -- Chams 参数
    ChamsFillTrans = 0.75,
    ChamsOutlineTrans = 0.25,

    -- Xray 参数
    XrayTransparency = 0.65,

    -- ESP 刷新间隔
    ESPRefreshRate = 0.4,
}

-- ══════════════════════════════════════════════════════════════════
-- 5. 全局变量
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false
local RoleCache = {}
local xrayCache = {}
local xrayConn = nil
local espLoopConn = nil
local gunDescendantConn = nil

-- ══════════════════════════════════════════════════════════════════
-- 6. 通知辅助函数
-- ══════════════════════════════════════════════════════════════
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
-- 7. 角色检测 (Role Detection)
-- ══════════════════════════════════════════════════════════════════
local function ParseRoleText(t)
    t = (t or ""):lower()
    if t:find("murder") then return "Murderer" end
    if t:find("sheriff") then return "Sheriff" end
    if t:find("innocent") then return "Innocent" end
    return nil
end

local function SetLocalRole(role)
    if role then
        RoleCache[LocalPlayer] = role
    end
end

local function HookRoleLabel(lbl)
    if not lbl or not lbl:IsA("TextLabel") then return end
    local role = ParseRoleText(lbl.Text)
    if role then SetLocalRole(role) end
    lbl:GetPropertyChangedSignal("Text"):Connect(function()
        local r = ParseRoleText(lbl.Text)
        if r then SetLocalRole(r) end
    end)
end

local function ScanRoleLabel()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d.Name == "Role" and d:IsA("TextLabel") then
            HookRoleLabel(d)
        end
    end
end

local function HookPlayerGui()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 10)
    if not pg then return end

    pg.DescendantAdded:Connect(function(d)
        if d.Name == "Role" and d:IsA("TextLabel") then
            HookRoleLabel(d)
        end
    end)

    ScanRoleLabel()
end

HookPlayerGui()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    ScanRoleLabel()
end)

local function GetMurdererV1()
    for _, v in pairs(Players:GetPlayers()) do
        if v.Character and (v.Character:FindFirstChild("Knife") or v.Backpack:FindFirstChild("Knife")) then
            return v.Character
        end
    end
    return nil
end

local function GetSheriffV1()
    for _, v in pairs(Players:GetPlayers()) do
        if v.Character and (v.Character:FindFirstChild("Gun") or v.Backpack:FindFirstChild("Gun")) then
            return v.Character
        end
    end
    return nil
end

local function ResolveRoleFromCache(char)
    for plr, role in pairs(RoleCache) do
        if plr.Character == char then
            return role
        end
    end
    return nil
end

local function GetRoleColor(char)
    if SETTINGS.RoleESPEnabled then
        local cached = ResolveRoleFromCache(char)
        if cached == "Murderer" then
            return SETTINGS.MurdererColor
        elseif cached == "Sheriff" then
            return SETTINGS.SheriffColor
        end

        local murderer = GetMurdererV1()
        local sheriff = GetSheriffV1()
        if char == murderer then
            return SETTINGS.MurdererColor
        elseif char == sheriff then
            return SETTINGS.SheriffColor
        end
    end
    return SETTINGS.InnocentColor
end

-- ══════════════════════════════════════════════════════════════════
-- 8. CHAMS ESP
-- ══════════════════════════════════════════════════════════════════
local function RemoveChamsESP()
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character then
            local esp = player.Character:FindFirstChild("ChamsESP")
            if esp then esp:Destroy() end
        end
    end
end

local function ApplyChams(char, color)
    if not char then return end

    local existing = char:FindFirstChild("ChamsESP")
    if existing then
        existing.FillColor = color
        existing.OutlineColor = color
        existing.FillTransparency = SETTINGS.ChamsFillTrans
        existing.OutlineTransparency = SETTINGS.ChamsOutlineTrans
        return
    end

    local h = Instance.new("Highlight")
    h.Name = "ChamsESP"
    h.FillTransparency = SETTINGS.ChamsFillTrans
    h.OutlineTransparency = SETTINGS.ChamsOutlineTrans
    h.FillColor = color
    h.OutlineColor = color
    h.Parent = char
end

-- ══════════════════════════════════════════════════════════════════
-- 9. GUN ESP
-- ══════════════════════════════════════════════════════════════════
local function RemoveGunESP()
    for _, v in pairs(Workspace:GetDescendants()) do
        if v.Name == "GunESP" then
            v:Destroy()
        end
    end
end

local function CreateGunESP(gun)
    if not SETTINGS.GunESPEnabled then return end
    if gun:FindFirstChild("GunESP") then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "GunESP"
    highlight.FillColor = SETTINGS.GunColor
    highlight.FillTransparency = 0.7
    highlight.OutlineTransparency = 0.2
    highlight.Parent = gun

    local billboard = Instance.new("BillboardGui", gun)
    billboard.Name = "GunESP"
    billboard.Size = UDim2.new(0, 120, 0, 20)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true

    local text = Instance.new("TextLabel", billboard)
    text.Size = UDim2.new(1, 0, 1, 0)
    text.BackgroundTransparency = 1
    text.Text = "🔫 Gun Dropped"
    text.TextColor3 = SETTINGS.GunColor
    text.Font = Enum.Font.GothamBold
    text.TextScaled = true
    text.TextStrokeTransparency = 0
end

local function HookGunDrops()
    if gunDescendantConn then
        gunDescendantConn:Disconnect()
    end
    gunDescendantConn = Workspace.DescendantAdded:Connect(function(obj)
        if obj.Name == "GunDrop" and obj:IsA("BasePart") and SETTINGS.GunESPEnabled then
            CreateGunESP(obj)
        end
    end)
    -- 扫描现有掉落物
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name == "GunDrop" and obj:IsA("BasePart") then
            CreateGunESP(obj)
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 10. XRAY
-- ══════════════════════════════════════════════════════════════════
local function IsPlayerPart(part)
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character and part:IsDescendantOf(p.Character) then
            return true
        end
    end
    return false
end

local function ApplyXrayToPart(part)
    if not part:IsA("BasePart") then return end
    if IsPlayerPart(part) then return end
    if xrayCache[part] == nil then
        xrayCache[part] = part.LocalTransparencyModifier
    end
    part.LocalTransparencyModifier = SETTINGS.XrayTransparency
end

local function EnableXray()
    for _, v in pairs(Workspace:GetDescendants()) do
        ApplyXrayToPart(v)
    end
    if xrayConn then xrayConn:Disconnect() end
    xrayConn = Workspace.DescendantAdded:Connect(function(v)
        ApplyXrayToPart(v)
    end)
end

local function DisableXray()
    if xrayConn then
        xrayConn:Disconnect()
        xrayConn = nil
    end
    for part, old in pairs(xrayCache) do
        if part and part.Parent then
            part.LocalTransparencyModifier = old
        end
    end
    xrayCache = {}
end

-- ══════════════════════════════════════════════════════════════════
-- 11. ESP LOOP
-- ══════════════════════════════════════════════════════════════════
local function StartESPLoop()
    if espLoopConn then
        espLoopConn:Disconnect()
    end
    espLoopConn = RunService.Heartbeat:Connect(function()
        -- 用 Heartbeat 但内部节流
    end)
    -- 独立 task.spawn 循环（保持原 MM2 的 0.4s 节奏）
    task.spawn(function()
        while not isDestroyed do
            task.wait(SETTINGS.ESPRefreshRate)
            if not SETTINGS.ChamsESPEnabled then continue end
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local color = GetRoleColor(player.Character)
                    ApplyChams(player.Character, color)
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 12. 传送功能
-- ══════════════════════════════════════════════════════════════════
local function GrabGun()
    local char = LocalPlayer.Character
    if not char then
        notify("Grab Gun", "你尚未生成角色", 2, "Warning")
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        notify("Grab Gun", "无法获取 HumanoidRootPart", 2, "Warning")
        return
    end

    local gun = Workspace:FindFirstChild("GunDrop", true)
    if not gun then
        notify("Grab Gun", "地图上没有掉落的枪", 2, "Warning")
        return
    end

    local originalCFrame = hrp.CFrame
    local target = gun:IsA("BasePart") and gun or gun:FindFirstChildWhichIsA("BasePart")
    if not target then
        notify("Grab Gun", "无法定位枪", 2, "Warning")
        return
    end

    hrp.CFrame = target.CFrame + Vector3.new(0, 2, 0)
    notify("Grab Gun", "已传送到枪支位置", 1, "Success")
    task.wait(0.15)
    hrp.CFrame = originalCFrame
end

local function TeleportToPlayer(targetPlayer)
    local char = LocalPlayer.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local targetChar = targetPlayer.Character
    if not targetChar then return false end
    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return false end
    hrp.CFrame = targetHRP.CFrame + Vector3.new(0, 3, 0)
    return true
end

-- ══════════════════════════════════════════════════════════════════
-- 13. 杂项功能
-- ══════════════════════════════════════════════════════════════════
local function RejoinServer()
    notify("Rejoin", "正在重新连接服务器...", 2, "Info")
    task.wait(0.6)
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end

local function DestroyScript()
    if isDestroyed then return end
    isDestroyed = true
    -- 清理 ESP
    RemoveChamsESP()
    RemoveGunESP()
    -- 清理 Xray
    DisableXray()
    -- 清理连接
    if espLoopConn then espLoopConn:Disconnect(); espLoopConn = nil end
    if gunDescendantConn then gunDescendantConn:Disconnect(); gunDescendantConn = nil end
    -- 清理窗口
    if Window then pcall(function() Window:Destroy() end) end
    if _G.MM2_QuantumUI_Window then _G.MM2_QuantumUI_Window = nil end
    notify("销毁", "MM2 Hub 已彻底销毁", 2, "Warning")
    print("[MM2 Hub] 脚本已销毁")
end

-- ══════════════════════════════════════════════════════════════════
-- 14. 构建 Quantum UI 界面
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title = "MM2 Hub",
    Subtitle = "Murder Mystery 2",
    ThemeColor = Color3.fromRGB(255, 120, 80),
    Transparency = 0.3,
    Size = UDim2.new(0, 620, 0, 500),
    Keybind = Enum.KeyCode.RightShift,
})

_G.MM2_QuantumUI_Window = Window

-- 等待启动动画
task.wait(3.5)

-- ========== TAB 1: ESP 设置 ==========
local ESPTab = Window:AddTab({
    Name = "ESP",
    Icon = "rbxassetid://6034509993"
})

ESPTab:AddSection({ Name = "👁️ ESP 开关" })

ESPTab:AddToggle({
    Name = "Chams ESP 玩家高亮",
    Default = SETTINGS.ChamsESPEnabled,
    Flag = "MM2_ChamsESP",
    Callback = function(val)
        SETTINGS.ChamsESPEnabled = val
        if not val then RemoveChamsESP() end
        notify("Chams ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "Role Detection 角色检测",
    Default = SETTINGS.RoleESPEnabled,
    Flag = "MM2_RoleESP",
    Callback = function(val)
        SETTINGS.RoleESPEnabled = val
        notify("角色检测", val and "已启用 (凶手红/警长蓝)" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "Gun ESP 掉落枪支",
    Default = SETTINGS.GunESPEnabled,
    Flag = "MM2_GunESP",
    Callback = function(val)
        SETTINGS.GunESPEnabled = val
        if val then
            HookGunDrops()
        else
            RemoveGunESP()
        end
        notify("Gun ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "Xray 透视墙壁",
    Default = SETTINGS.XrayEnabled,
    Flag = "MM2_Xray",
    Callback = function(val)
        SETTINGS.XrayEnabled = val
        if val then
            EnableXray()
        else
            DisableXray()
        end
        notify("Xray", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddSection({ Name = "🎨 ESP 颜色" })

ESPTab:AddColorPicker({
    Name = "凶手 (Murderer) 颜色",
    Default = SETTINGS.MurdererColor,
    Presets = PRESET_COLORS,
    Flag = "MM2_MurdererColor",
    Callback = function(c)
        SETTINGS.MurdererColor = c
        notify("颜色", "凶手颜色已更新", 1.5, "Success")
    end
})

ESPTab:AddColorPicker({
    Name = "警长 (Sheriff) 颜色",
    Default = SETTINGS.SheriffColor,
    Presets = PRESET_COLORS,
    Flag = "MM2_SheriffColor",
    Callback = function(c)
        SETTINGS.SheriffColor = c
        notify("颜色", "警长颜色已更新", 1.5, "Success")
    end
})

ESPTab:AddColorPicker({
    Name = "无辜者 (Innocent) 颜色",
    Default = SETTINGS.InnocentColor,
    Presets = PRESET_COLORS,
    Flag = "MM2_InnocentColor",
    Callback = function(c)
        SETTINGS.InnocentColor = c
        notify("颜色", "无辜者颜色已更新", 1.5, "Success")
    end
})

ESPTab:AddColorPicker({
    Name = "枪支 (Gun) 颜色",
    Default = SETTINGS.GunColor,
    Presets = PRESET_COLORS,
    Flag = "MM2_GunColor",
    Callback = function(c)
        SETTINGS.GunColor = c
        -- 重新应用现有 Gun ESP
        if SETTINGS.GunESPEnabled then
            RemoveGunESP()
            HookGunDrops()
        end
        notify("颜色", "枪支颜色已更新", 1.5, "Success")
    end
})

ESPTab:AddSection({ Name = "⚙️ ESP 参数" })

ESPTab:AddSlider({
    Name = "Chams 填充透明度",
    Min = 0, Max = 1, Default = SETTINGS.ChamsFillTrans, Increment = 0.05,
    Flag = "MM2_ChamsFillTrans",
    Callback = function(val)
        SETTINGS.ChamsFillTrans = val
    end
})

ESPTab:AddSlider({
    Name = "Chams 轮廓透明度",
    Min = 0, Max = 1, Default = SETTINGS.ChamsOutlineTrans, Increment = 0.05,
    Flag = "MM2_ChamsOutlineTrans",
    Callback = function(val)
        SETTINGS.ChamsOutlineTrans = val
    end
})

ESPTab:AddSlider({
    Name = "Xray 透视程度",
    Min = 0.1, Max = 0.95, Default = SETTINGS.XrayTransparency, Increment = 0.05,
    Flag = "MM2_XrayTrans",
    Callback = function(val)
        SETTINGS.XrayTransparency = val
        if SETTINGS.XrayEnabled then
            DisableXray()
            EnableXray()
        end
    end
})

ESPTab:AddSlider({
    Name = "ESP 刷新间隔",
    Min = 0.1, Max = 2, Default = SETTINGS.ESPRefreshRate, Increment = 0.1,
    Suffix = " s",
    Flag = "MM2_ESPRefresh",
    Callback = function(val)
        SETTINGS.ESPRefreshRate = val
    end
})

-- ========== TAB 2: 传送 ==========
local TeleportTab = Window:AddTab({
    Name = "Teleport",
    Icon = "rbxassetid://6034287594"
})

TeleportTab:AddSection({ Name = "🎯 物品传送" })

TeleportTab:AddButton({
    Name = "🔫 抓取掉落枪支 (Grab Gun)",
    Callback = function()
        GrabGun()
    end
})

TeleportTab:AddLabel({ Text = "💡 短暂传送到掉落枪支的位置然后返回，快速拾取" })

TeleportTab:AddSection({ Name = "👥 玩家传送" })

TeleportTab:AddParagraph({
    Title = "玩家列表",
    Content = "下方将显示当前服务器所有玩家，点击按钮传送到对应玩家位置。"
})

-- 动态添加玩家按钮 (通过循环，但 Quantum UI 的 Tab 不支持动态添加，所以用 Dropdown + Button)
local playerList = {}
for _, p in pairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then
        table.insert(playerList, p.Name)
    end
end
if #playerList == 0 then
    table.insert(playerList, "(暂无其他玩家)")
end

local selectedPlayerName = playerList[1]

local playerDropdown = TeleportTab:AddDropdown({
    Name = "选择目标玩家",
    Items = playerList,
    Default = selectedPlayerName,
    Flag = "MM2_TargetPlayer",
    Callback = function(selected)
        selectedPlayerName = selected
    end
})

TeleportTab:AddButton({
    Name = "🚀 传送到选中玩家",
    Callback = function()
        if selectedPlayerName == "(暂无其他玩家)" or not selectedPlayerName then
            notify("传送", "没有可选的目标玩家", 2, "Warning")
            return
        end
        local targetPlayer = Players:FindFirstChild(selectedPlayerName)
        if not targetPlayer then
            notify("传送", "玩家不存在或已离开", 2, "Warning")
            return
        end
        local ok = TeleportToPlayer(targetPlayer)
        if ok then
            notify("传送", "已传送到 " .. targetPlayer.Name, 2, "Success")
        else
            notify("传送", "传送失败 (角色未生成)", 2, "Warning")
        end
    end
})

-- 刷新玩家列表按钮
TeleportTab:AddButton({
    Name = "🔄 刷新玩家列表",
    Callback = function()
        local newList = {}
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                table.insert(newList, p.Name)
            end
        end
        if #newList == 0 then
            table.insert(newList, "(暂无其他玩家)")
        end
        playerList = newList
        notify("玩家列表", "已刷新，共 " .. tostring(#newList - (newList[1] == "(暂无其他玩家)" and 1 or 0)) .. " 名玩家", 2, "Success")
    end
})

-- ========== TAB 3: Keybinds ==========
local KeybindTab = Window:AddTab({
    Name = "Keybinds",
    Icon = "rbxassetid://6034281467"
})

KeybindTab:AddSection({ Name = "⌨️ 快捷键绑定" })

KeybindTab:AddKeybind({
    Name = "UI 显示/隐藏",
    Default = Enum.KeyCode.RightShift,
    Flag = "MM2_UIKeybind",
    ChangedCallback = function(key)
        notify("快捷键", "UI 切换键已改为: " .. key.Name, 2, "Info")
    end,
    Callback = function()
        -- 附加快捷键（UI切换由库的 Keybind 参数处理，这里只做备份）
    end
})

KeybindTab:AddKeybind({
    Name = "Xray 开关",
    Default = Enum.KeyCode.X,
    Flag = "MM2_XrayKeybind",
    ChangedCallback = function(key)
        notify("快捷键", "Xray 切换键已改为: " .. key.Name, 2, "Info")
    end,
    Callback = function()
        SETTINGS.XrayEnabled = not SETTINGS.XrayEnabled
        if Window and Window.Flags and Window.Flags["MM2_Xray"] then
            pcall(function() Window.Flags["MM2_Xray"]:Set(SETTINGS.XrayEnabled) end)
        end
        if SETTINGS.XrayEnabled then
            EnableXray()
        else
            DisableXray()
        end
        notify("Xray", SETTINGS.XrayEnabled and "已启用" or "已禁用", 1.5, SETTINGS.XrayEnabled and "Success" or "Warning")
    end
})

KeybindTab:AddSection({ Name = "ℹ️ 说明" })

KeybindTab:AddParagraph({
    Title = "使用方法",
    Content = table.concat({
        "1. 点击按键框进入绑定模式",
        "2. 按下你想设置的键盘按键",
        "3. 设置会自动保存（通过 Flag）",
        "4. 使用 Settings Tab 可保存/加载完整配置"
    }, "\n")
})

-- ========== TAB 4: Misc ==========
local MiscTab = Window:AddTab({
    Name = "Misc",
    Icon = "rbxassetid://6031280882"
})

MiscTab:AddSection({ Name = "🎮 游戏操作" })

MiscTab:AddButton({
    Name = "🔄 重新加入服务器 (Rejoin)",
    Callback = function()
        RejoinServer()
    end
})

MiscTab:AddButton({
    Name = "💀 彻底销毁脚本",
    Callback = function()
        DestroyScript()
    end
})

MiscTab:AddSection({ Name = "🌈 UI 美化" })

MiscTab:AddToggle({
    Name = "彩虹边框动画",
    Default = QuantumUI.RainbowEnabled,
    Flag = "MM2_Rainbow",
    Callback = function(state)
        QuantumUI.RainbowEnabled = state
    end
})

MiscTab:AddSlider({
    Name = "彩虹速度",
    Min = 0.1, Max = 5, Default = QuantumUI.RainbowSpeed or 1, Increment = 0.1,
    Suffix = "x",
    Flag = "MM2_RainbowSpeed",
    Callback = function(value)
        QuantumUI.RainbowSpeed = value
    end
})

MiscTab:AddDropdown({
    Name = "预设主题色",
    Items = {"Murderer Red", "Sheriff Blue", "Innocent Green", "Cyan", "Purple", "Gold", "Pink"},
    Default = "Murderer Red",
    Flag = "MM2_ThemePreset",
    Callback = function(selected)
        local themes = {
            ["Murderer Red"]   = Color3.fromRGB(255, 80, 80),
            ["Sheriff Blue"]   = Color3.fromRGB(80, 150, 255),
            ["Innocent Green"] = Color3.fromRGB(0, 255, 120),
            ["Cyan"]           = Color3.fromRGB(0, 200, 255),
            ["Purple"]         = Color3.fromRGB(180, 60, 255),
            ["Gold"]           = Color3.fromRGB(255, 200, 50),
            ["Pink"]           = Color3.fromRGB(255, 105, 180),
        }
        local color = themes[selected]
        if color then
            Window.ThemeColor = color
            QuantumUI.ThemeColor = color
            Window:RefreshTheme()
            notify("主题", "已切换: " .. selected, 2, "Success")
        end
    end
})

MiscTab:AddSection({ Name = "ℹ️ 关于" })

MiscTab:AddParagraph({
    Title = "MM2 Hub | Quantum UI 版",
    Content = table.concat({
        "游戏: Murder Mystery 2 (造船寻宝)",
        "UI框架: Quantum UI Library",
        "",
        "✅ Chams ESP  - 玩家高亮",
        "✅ Role ESP   - 凶手/警长角色识别",
        "✅ Gun ESP    - 掉落枪支透视",
        "✅ Xray       - 墙壁透视",
        "✅ Grab Gun   - 快速抓枪传送",
        "✅ TP Player  - 玩家传送",
        "✅ Keybinds   - 自定义快捷键",
        "✅ Config     - 配置保存/加载"
    }, "\n")
})

MiscTab:AddLabel({ Text = "💡 前往 Settings Tab 保存你的配置！" })

-- ══════════════════════════════════════════════════════════════════
-- 15. 主初始化
-- ══════════════════════════════════════════════════════════════════
task.wait(0.5)

-- 启动 ESP 循环
StartESPLoop()

-- 初始化 Gun Drop hook
HookGunDrops()

-- 初始化 Xray (如果默认开启)
if SETTINGS.XrayEnabled then
    EnableXray()
end

-- 玩家添加/移除（刷新玩家下拉菜单不用处理，由刷新按钮手动）
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        if isDestroyed then return end
        task.wait(0.2)
        -- 如果有 Chams，刷新一下
        if SETTINGS.ChamsESPEnabled and player ~= LocalPlayer and player.Character then
            local color = GetRoleColor(player.Character)
            ApplyChams(player.Character, color)
        end
    end)
end)

-- ══════════════════════════════════════════════════════════════════
-- 16. 额外的快捷键处理 (Delete 销毁)
-- ══════════════════════════════════════════════════════════════════
UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or isDestroyed then return end
    if input.KeyCode == Enum.KeyCode.Delete then
        DestroyScript()
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 17. 加载完成通知
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
notify("✅ MM2 Hub 加载完成!",
    "Murder Mystery 2 Quantum UI 版本就绪\n" ..
    "按右 Shift 切换 UI 显示\n" ..
    "按 X 开关 Xray 透视\n" ..
    "前往 Settings Tab 保存你的配置!",
    6, "Success")

print("========================================")
print(" MM2 Hub (Quantum UI 版) 加载完成")
print("   游戏: Murder Mystery 2 / 造船寻宝")
print("   RightShift - 隐藏/显示 UI")
print("   X          - Xray 透视开关")
print("   Delete     - 彻底销毁脚本")
print("   Settings Tab - 保存/加载配置")
print("========================================")
