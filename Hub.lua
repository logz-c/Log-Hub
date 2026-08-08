--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║                         LOG-HUB 脚本中心                          ║
    ║                      Version 1.0.0 - Initial Release             ║
    ║                         Created by log_quick                     ║
    ║                                                                  ║
    ║  功能：                                                          ║
    ║  • 自动检测当前游戏 (通过 PlaceId)                                ║
    ║  • 自动加载对应游戏脚本                                           ║
    ║  • 支持手动选择/切换脚本                                         ║
    ║  • 统一 UI 库加载入口                                            ║
    ╚══════════════════════════════════════════════════════════════════╝

    使用方法:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/Hub.lua"))()
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 1. 配置区 - 游戏注册表
-- ══════════════════════════════════════════════════════════════════

local GITHUB_BASE = "https://raw.githubusercontent.com/logz-c/Log-Hub/main"

local GAME_REGISTRY = {
    {
        Name = "兵工厂 (Arsenal)",
        PlaceIds = { 286090429, 3285367695, 8216580756 },
        ScriptPath = "/FPS_QuantumUI.lua",
        Icon = "rbxassetid://6034509993",
        Description = "FPS 辅助: ESP / 自瞄 / 扳机 / 概率瞄准 / NPC透视",
    },
    -- 未来扩展:
    -- {
    --     Name = "Phantom Forces",
    --     PlaceIds = { 292439477 },
    --     ScriptPath = "/Games/PhantomForces.lua",
    --     Icon = "rbxassetid://...",
    --     Description = "...",
    -- },
}

-- 通用示例脚本 (无匹配游戏时显示)
local FALLBACK_SCRIPT = {
    Name = "通用示例 (Universal)",
    ScriptPath = "/ExampleScript.lua",
    Icon = "rbxassetid://6031280882",
    Description = "Quantum UI 完整功能演示",
}

-- ══════════════════════════════════════════════════════════════════
-- 2. 游戏检测
-- ══════════════════════════════════════════════════════════════════

local PlaceId = game.PlaceId
local GameName = game.Name

local function detectGame()
    for _, game_entry in ipairs(GAME_REGISTRY) do
        for _, id in ipairs(game_entry.PlaceIds) do
            if id == PlaceId then
                return game_entry
            end
        end
    end
    return nil
end

local detectedGame = detectGame()

-- ══════════════════════════════════════════════════════════════════
-- 3. 脚本加载器
-- ══════════════════════════════════════════════════════════════════

local function loadScript(scriptEntry)
    if not scriptEntry then return false end

    local url = GITHUB_BASE .. scriptEntry.ScriptPath
    local success, result = pcall(function()
        return game:HttpGet(url)
    end)

    if not success then
        warn("[Log-Hub] 获取脚本失败:", result)
        return false
    end

    local execSuccess, execErr = pcall(function()
        loadstring(result)()
    end)

    if not execSuccess then
        warn("[Log-Hub] 执行脚本失败:", execErr)
        return false
    end

    return true
end

-- ══════════════════════════════════════════════════════════════════
-- 4. 加载 Quantum UI 库 (用于 Hub 自身界面)
-- ══════════════════════════════════════════════════════════════════

local function loadUILibrary()
    local url = GITHUB_BASE .. "/SciFi-UI-Library/source.lua"
    local success, QuantumUI = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if not success then
        warn("[Log-Hub] 加载 UI 库失败:", QuantumUI)
        return nil
    end
    return QuantumUI
end

-- ══════════════════════════════════════════════════════════════════
-- 5. 主流程
-- ══════════════════════════════════════════════════════════════════

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

-- 单例保护
if _G.LogHub_Loaded then
    warn("[Log-Hub] 已加载过，跳过重复注入")
    return
end
_G.LogHub_Loaded = true

-- 通知函数
local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5,
        })
    end)
end

print(string.format("[Log-Hub] 当前游戏: %s (PlaceId: %d)", GameName, PlaceId))

-- 自动检测并加载对应脚本
if detectedGame then
    print(string.format("[Log-Hub] 检测到匹配游戏: %s", detectedGame.Name))
    notify("Log-Hub", "检测到: " .. detectedGame.Name .. "\n正在加载脚本...", 4)

    local loaded = loadScript(detectedGame)
    if loaded then
        print(string.format("[Log-Hub] %s 脚本加载成功", detectedGame.Name))
    else
        warn(string.format("[Log-Hub] %s 脚本加载失败", detectedGame.Name))
        notify("Log-Hub", detectedGame.Name .. " 加载失败，启动 Hub 界面...", 5)
    end
else
    print("[Log-Hub] 未检测到匹配游戏")
    notify("Log-Hub", "未检测到支持的游戏\n启动通用 Hub 界面...", 5)
end

-- ══════════════════════════════════════════════════════════════════
-- 6. Hub 界面 (游戏未匹配 / 用户想手动选择时)
-- ══════════════════════════════════════════════════════════════════

-- 延迟加载 Hub UI (给已加载的脚本 UI 时间初始化)
task.delay(1, function()
    local QuantumUI = loadUILibrary()
    if not QuantumUI then return end

    local Window = QuantumUI.new({
        Title = "Log-Hub",
        Subtitle = "脚本中心 v1.0.0",
        ThemeColor = Color3.fromRGB(0, 200, 255),
        Transparency = 0.3,
        Size = UDim2.new(0, 550, 0, 400),
        Keybind = Enum.KeyCode.RightControl,
    })

    task.wait(3.5)
    _G.QuantumUI_Window = Window

    -- ── 游戏信息 Tab ──
    local InfoTab = Window:AddTab({
        Name = "游戏信息",
        Icon = "rbxassetid://6034287594",
    })

    InfoTab:AddSection({ Name = "当前游戏" })

    InfoTab:AddLabel({ Text = "游戏名称: " .. GameName })
    InfoTab:AddLabel({ Text = "PlaceId: " .. tostring(PlaceId) })

    if detectedGame then
        InfoTab:AddLabel({ Text = "匹配脚本: " .. detectedGame.Name })
        InfoTab:AddLabel({ Text = "状态: " .. (_G.LogHub_Loaded and "已加载" or "未加载") })
    else
        InfoTab:AddLabel({ Text = "匹配脚本: 无 (未支持的游戏)" })
    end

    -- ── 脚本列表 Tab ──
    local ScriptsTab = Window:AddTab({
        Name = "脚本列表",
        Icon = "rbxassetid://6034509993",
    })

    ScriptsTab:AddSection({ Name = "可用脚本" })

    -- 注册游戏脚本
    for i, game_entry in ipairs(GAME_REGISTRY) do
        local isCurrentGame = (detectedGame == game_entry)
        ScriptsTab:AddButton({
            Name = (isCurrentGame and "[当前] " or "") .. game_entry.Name,
            Callback = function()
                Window:Notify({
                    Title = "Log-Hub",
                    Content = "正在加载: " .. game_entry.Name,
                    Duration = 3,
                    Type = "Info",
                })
                local ok = loadScript(game_entry)
                if ok then
                    Window:Notify({
                        Title = "成功",
                        Content = game_entry.Name .. " 已加载!",
                        Duration = 3,
                        Type = "Success",
                    })
                else
                    Window:Notify({
                        Title = "错误",
                        Content = game_entry.Name .. " 加载失败",
                        Duration = 3,
                        Type = "Error",
                    })
                end
            end,
        })
    end

    -- 通用示例脚本
    ScriptsTab:AddButton({
        Name = FALLBACK_SCRIPT.Name,
        Callback = function()
            Window:Notify({
                Title = "Log-Hub",
                Content = "正在加载通用示例脚本...",
                Duration = 3,
                Type = "Info",
            })
            loadScript(FALLBACK_SCRIPT)
        end,
    })

    -- ── 关于 Tab ──
    local AboutTab = Window:AddTab({
        Name = "关于",
        Icon = "rbxassetid://6031280882",
    })

    AboutTab:AddSection({ Name = "Log-Hub" })

    AboutTab:AddParagraph({
        Title = "Log-Hub 脚本中心",
        Content = table.concat({
            "版本: v1.0.0",
            "作者: log_quick",
            "",
            "功能:",
            "• 自动检测当前游戏并加载对应脚本",
            "• 支持手动选择和加载脚本",
            "• 统一 UI 库 (Quantum UI) 加载入口",
            "",
            "GitHub: github.com/logz-c/Log-Hub",
        }, "\n"),
    })

    AboutTab:AddSection({ Name = "支持的游戏" })

    local gameList = {}
    for _, entry in ipairs(GAME_REGISTRY) do
        local ids = {}
        for _, id in ipairs(entry.PlaceIds) do
            table.insert(ids, tostring(id))
        end
        table.insert(gameList, entry.Name .. " (ID: " .. table.concat(ids, ", ") .. ")")
    end
    table.insert(gameList, FALLBACK_SCRIPT.Name)

    AboutTab:AddParagraph({
        Title = "游戏列表",
        Content = table.concat(gameList, "\n"),
    })

    -- 加载完成通知
    task.wait(0.3)
    Window:Notify({
        Title = "Log-Hub 已就绪!",
        Content = "按 RightControl 切换 UI\n检测到: " .. (detectedGame and detectedGame.Name or "无匹配游戏"),
        Duration = 6,
        Type = "Success",
    })

    print("[Log-Hub] Hub 界面初始化完成")
end)
