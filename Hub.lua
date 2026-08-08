--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║                         LOG-HUB 脚本中心                          ║
    ║                      Version 1.3.0                               ║
    ║                         Created by log_quick                     ║
    ║                                                                  ║
    ║  功能：                                                          ║
    ║  • 注入后自动检测当前游戏 (通过 PlaceId)                          ║
    ║  • 匹配成功 → 直接加载对应脚本，不询问用户                         ║
    ║  • 匹配失败 → 通知用户当前游戏不受支持                             ║
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
        Description = "FPS 辅助: ESP / 自瞄 / 扳机 / 概率瞄准 / NPC透视",
    },
    {
        Name = "犯罪 (Criminality)",
        PlaceIds = { 4588604953 },
        ScriptPath = "/Criminality_QuantumUI.lua",
        Description = "Criminality 辅助: 世界/玩家/战斗/视觉/白名单, 5 大 Tab, Config 自动保存",
    },
    {
        Name = "造船寻宝 (Build a Boat for Treasure)",
        PlaceIds = { 537413528 },
        ScriptPath = "/BABFT_QuantumUI.lua",
        Description = "BABFT 辅助: 移动 (WalkSpeed/JumpPower/InfJump/NoClip/Fly/TP) + AutoFarm (CaveStage 分段传送+GoldenChest 触发, 源自 Autofarm.lua) + Anti-AFK",
    },
    -- 未来扩展:
    -- {
    --     Name = "Phantom Forces",
    --     PlaceIds = { 292439477 },
    --     ScriptPath = "/Games/PhantomForces.lua",
    --     Description = "...",
    -- },
}

-- ══════════════════════════════════════════════════════════════════
-- 2. 单例保护
-- ══════════════════════════════════════════════════════════════════

if _G.LogHub_Loaded then
    warn("[Log-Hub] 已加载过，跳过重复注入")
    return
end
_G.LogHub_Loaded = true

-- ══════════════════════════════════════════════════════════════════
-- 3. 游戏检测
-- ══════════════════════════════════════════════════════════════════

local PlaceId   = game.PlaceId
local GameName  = game.Name
local StarterGui = game:GetService("StarterGui")

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title   = title,
            Text    = text,
            Duration = duration or 5,
        })
    end)
end

local function detectGame()
    for _, entry in ipairs(GAME_REGISTRY) do
        for _, id in ipairs(entry.PlaceIds) do
            if id == PlaceId then
                return entry
            end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════
-- 4. 脚本加载器
-- ══════════════════════════════════════════════════════════════════

local function loadScript(scriptEntry)
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
-- 5. 主流程 - 检测 → 直接加载
-- ══════════════════════════════════════════════════════════════════

print(string.format("[Log-Hub] 当前游戏: %s (PlaceId: %d)", GameName, PlaceId))

local detected = detectGame()

if detected then
    -- 匹配成功 → 直接加载，不询问
    print(string.format("[Log-Hub] 检测到: %s → 正在加载脚本...", detected.Name))
    notify("Log-Hub", "检测到: " .. detected.Name .. "\n正在加载脚本...", 3)

    local ok = loadScript(detected)
    if ok then
        print(string.format("[Log-Hub] %s 脚本加载成功", detected.Name))
        notify("Log-Hub", detected.Name .. " 脚本已加载", 4)
    else
        warn(string.format("[Log-Hub] %s 脚本加载失败", detected.Name))
        notify("Log-Hub", detected.Name .. " 脚本加载失败", 5)
    end
else
    -- 匹配失败 → 通知，不弹任何 UI
    print("[Log-Hub] 当前游戏不受支持，无需加载脚本")
    notify("Log-Hub", "当前游戏不受支持\nPlaceId: " .. tostring(PlaceId), 6)
end
