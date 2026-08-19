--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║                         LOG-HUB 脚本中心                          ║
    ║                      Version 2.2.0                               ║
    ║                         Created by log_quick                     ║
    ║                                                                  ║
    ║  功能：                                                          ║
    ║  • 注入后自动检测当前游戏 (通过 PlaceId)                          ║
    ║  • 匹配成功 → 直接加载对应游戏脚本，不询问用户                     ║
    ║  • 匹配失败 → 加载通用脚本: Infinite Yield + 杂项 (坐标获取等)   ║
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
        Description = "BABFT 辅助: 移动 (WalkSpeed/JumpPower/InfJump/NoClip/Fly/TP) + AutoFarm (源码照搬: BoatStages.NormalStages CaveStage1-10 + TheEnd.GoldenChest) + Anti-AFK",
    },
    {
        Name = "Murder Mystery 2 (MM2)",
        PlaceIds = { 142823291 },
        ScriptPath = "/MM2_QuantumUI.lua",
        Description = "MM2 辅助: Chams ESP / 角色检测 (凶手红/警长蓝/无辜绿) / Gun ESP / Xray / Grab Gun / 玩家传送 / 自定义热键",
    },
    {
        Name = "Blade Ball (利刃球)",
        PlaceIds = { 13772394625, 14732610803, 14915220621, 15144787112, 15264892126, 15509350986, 16281300371 },
        ScriptPath = "/BladeBall_QuantumUI.lua",
        Description = "利刃球辅助: AutoParry / BallESP / KillAura / Reach / AutoDash / AbilitySpam / 移动 (WalkSpeed/JumpPower/InfJump/NoClip/Fly) + 传送 + 主题",
    },
    {
        Name = "Tower of Hell (地狱塔)",
        PlaceIds = { 1962086868, 3582763398 },
        ScriptPath = "/TowerOfHell_QuantumUI.lua",
        Description = "地狱塔辅助: AutoWin / SkipStages / StageESP / 低重力 / 移动 (WalkSpeed/JumpPower/InfJump/NoClip/Fly) + 关卡传送 + 4 热键",
    },
    {
        Name = "Doors (恐怖门)",
        PlaceIds = { 6839179744, 6839808510, 7894711641, 7542019739, 7951135890, 8114357705 },
        ScriptPath = "/Doors_QuantumUI.lua",
        Description = "Doors v3.1 修复版: ESP过滤(仅真实物品/无装饰) + 抽屉自动打开 + 默认无加速 + Noclip恢复碰撞 + FOV修复 + 全ESP/自动交互躲藏/反实体/矿车/锚点/全楼层",
    },
    {
        Name = "+1 Speed Monkey Escape Codes",
        PlaceIds = { 1169737442 },
        GameIds  = { 10144280947 },
        ScriptPath = "/MonkeyEscape_QuantumUI.lua",
        Description = "v1.2: 奖励点传送 + 锁定循环传送(防拉回/可调延迟) + 自动切换奖励点(可调延迟) + 世界切换 + WalkSpeed/JumpPower/InfJump/NoClip/Fly + AntiAFK",
    },
    {
        Name = "Evade (Nextbot 逃生)",
        PlaceIds = { 9872472334 },
        GameIds  = { 11818772280 },
        ScriptPath = "/Evade_QuantumUI.lua",
        Description = "v2.0: 基于真实源码还原 — 自动重生(ChangePlayerMode) + 即时复活/搬运(Interact Revive/Carry) + 自动复活 + 快速复活(ReviveTime) + Money/AFK/Ticket Farm + CFrame Speed Boost(MoveDirection) + NoClip/Fly + Nextbot/玩家/倒地/票券ESP + 全亮 + 移除障碍/KillBricks + Rejoin + Anti-AFK",
    },
    {
        Name = "The Strongest Battlegrounds (最强战场)",
        PlaceIds = { 10449761463 },
        GameIds  = { 3808081382 },
        ScriptPath = "/Battlegrounds_QuantumUI.lua",
        Description = "v3.0: 基于最近(2025-06)真实源码 Dark-X-Hub 重做 — Communicate:FireServer官方普攻(LeftClick) + 技能(Console Move) + 终极(G) + Trash垃圾农场(workspace.Map.Trash传送拾取) + Counter反琦玉检测(红色高亮) + Kamuy逃生 + AttackAura/AutoCombo/AutoUltimate + KillFarm + AutoBlock(F) + AutoReset + 移动/状态防抗 + PlayerESP(高亮+血量+距离) + 全亮 + 服务器 + Anti-AFK + 坐标 + 快捷键(T传敌/Y穿墙/U飞行/R逃生)",
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
-- 2. 单例保护 — 只拦截"UI 仍在存活"时的重复注入，主动 Destroy 后允许再次注入
-- ══════════════════════════════════════════════════════════════════

local function isUIAlive()
    -- UI 仍存活的判断标准：_G.QuantumUI_Instance 还在且 ScreenGui 未被销毁
    local inst = _G.QuantumUI_Instance
    if inst and pcall(function() return inst.ScreenGui and inst.ScreenGui.Parent end) then
        local ok, parentOk = pcall(function() return inst.ScreenGui and inst.ScreenGui.Parent ~= nil end)
        if ok and parentOk then return true end
    end
    local win = _G.QuantumUI_Window
    if win and win ~= inst and pcall(function() return win.ScreenGui and win.ScreenGui.Parent end) then
        local ok, parentOk = pcall(function() return win.ScreenGui and win.ScreenGui.Parent ~= nil end)
        if ok and parentOk then return true end
    end
    return false
end

if isUIAlive() then
    warn("[Log-Hub] UI 仍处于打开状态，跳过重复注入 (如需重新注入，请先在 Settings 中 Destroy UI)")
    return
end

-- 注入前清场：销毁残留引用 & CoreGui 里的孤儿 ScreenGui (和 ExampleScript / FPS_QuantumUI 开头保持一致)
do
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
end

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
    local gameId = game.GameId
    for _, entry in ipairs(GAME_REGISTRY) do
        for _, id in ipairs(entry.PlaceIds or {}) do
            if id == PlaceId then
                return entry
            end
        end
        if entry.GameIds and gameId and gameId ~= 0 then
            for _, gid in ipairs(entry.GameIds) do
                if gid == gameId then
                    return entry
                end
            end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════
-- 4. 脚本加载器
-- ══════════════════════════════════════════════════════════════════

local function loadScriptByUrl(url, label)
    label = label or "脚本"
    local success, result = pcall(function()
        return game:HttpGet(url)
    end)
    if not success then
        warn(("[Log-Hub] 获取%s失败: %s"):format(label, tostring(result)))
        return false
    end
    -- 先检查 loadstring 是否返回 nil（语法错误）
    local compileFn, compileErr = loadstring(result)
    if not compileFn then
        warn(("[Log-Hub] %s 语法错误: %s"):format(label, tostring(compileErr)))
        return false
    end
    local execOk, execErr = pcall(compileFn)
    if not execOk then
        warn(("[Log-Hub] 执行%s失败: %s"):format(label, tostring(execErr)))
        return false
    end
    return true
end

local function loadScript(scriptEntry)
    local url = GITHUB_BASE .. scriptEntry.ScriptPath
    return loadScriptByUrl(url, scriptEntry.Name .. " 脚本")
end

-- ══════════════════════════════════════════════════════════════════
-- 5. 通用脚本 — 未匹配游戏时使用
--    内容:
--      • Infinite Yield (命令行指令集)
--      • 杂项: 打印坐标 / Clipboard复制坐标 / WalkSpeed / JumpPower / Anti-AFK / 重新注入Hub
-- ══════════════════════════════════════════════════════════════════

local function loadGenericScript()
    print("[Log-Hub] 游戏未匹配，加载通用脚本 (InfiniteYield + 杂项)...")
    notify("Log-Hub", "通用模式\n加载 Infinite Yield + 杂项", 4)

    -- ── 5.1 加载 Infinite Yield ──
    task.spawn(function()
        local iyOk = loadScriptByUrl(
            "https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source",
            "Infinite Yield"
        )
        if iyOk then
            print("[Log-Hub] Infinite Yield 加载成功")
            notify("Log-Hub", "Infinite Yield 已加载\n按 RightShift 打开", 3)
        else
            notify("Log-Hub", "Infinite Yield 加载失败", 3)
        end
    end)

    -- ── 5.2 加载 Quantum UI 库 (为杂项功能提供 UI 容器) ──
    local libOk, QuantumUI = pcall(function()
        return loadstring(game:HttpGet(GITHUB_BASE .. "/SciFi-UI-Library/source.lua"))()
    end)

    if not libOk then
        warn("[Log-Hub] 通用模式: Quantum UI 库加载失败，跳过 UI")
        return
    end

    local Players          = game:GetService("Players")
    local LocalPlayer      = Players.LocalPlayer
    local RunService       = game:GetService("RunService")
    local VirtualUser      = game:GetService("VirtualUser")
    local UserInputService = game:GetService("UserInputService")

    local Window = QuantumUI.new({
        Title    = "通用模式 - " .. GameName,
        Subtitle = "PlaceId: " .. tostring(PlaceId) .. "  |  Log-Hub v2.2.0",
        ThemeColor = Color3.fromRGB(0, 200, 255),
        Transparency = 0.3,
        Size     = UDim2.new(0, 560, 0, 440),
        Keybind  = Enum.KeyCode.RightControl,
    })

    local Icons = QuantumUI.Assets or {}

    task.wait(3.5)
    _G.QuantumUI_Window = Window

    -- ── 辅助函数 ──
    local function getChar()
        return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    end
    local function getHum()
        local c = getChar()
        return c and c:FindFirstChildOfClass("Humanoid")
    end
    local function getRoot()
        local c = getChar()
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    -- 全局状态
    local miscState = {
        WalkSpeed       = 16,
        SetWalkSpeed    = false,
        JumpPower       = 50,
        SetJumpPower    = false,
        AntiAFK         = false,
        LoopTpInterval  = 0.5,
        LoopTpEnabled   = false,
    }

    -- ── TAB 1: 位置 & 信息 ──
    local InfoTab = Window:AddTab({
        Name = "位置/信息",
        Icon = Icons.IconPlayer or "rbxassetid://6034287594",
    })

    InfoTab:AddSection({ Name = "当前游戏信息" })

    InfoTab:AddParagraph({
        Title   = "游戏信息",
        Content = table.concat({
            "Game Name:  " .. GameName,
            "PlaceId:    " .. tostring(PlaceId),
            "JobId:      " .. (tostring(game.JobId) or "N/A"),
            "Player:     " .. (LocalPlayer.Name or "N/A"),
            "UserId:     " .. tostring(LocalPlayer.UserId),
        }, "\n"),
    })

    InfoTab:AddButton({
        Name = "复制 PlaceId 到剪贴板",
        Callback = function()
            if setclipboard then
                setclipboard(tostring(PlaceId))
                Window:Notify({ Title = "已复制", Content = "PlaceId: " .. tostring(PlaceId), Duration = 2, Type = "Success" })
            else
                Window:Notify({ Title = "失败", Content = "当前执行器不支持 setclipboard", Duration = 2, Type = "Error" })
            end
        end,
    })

    InfoTab:AddSection({ Name = "坐标获取" })

    -- 实时显示坐标标签
    local coordsLabel = InfoTab:AddLabel({ Text = "X: 0.00  Y: 0.00  Z: 0.00" })
    local coordsConn
    task.spawn(function()
        coordsConn = RunService.Heartbeat:Connect(function()
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root and coordsLabel then
                local p = root.Position
                coordsLabel:SetText(string.format("X: %.2f   Y: %.2f   Z: %.2f", p.X, p.Y, p.Z))
            end
        end)
    end)

    InfoTab:AddButton({
        Name = "打印当前坐标 (控制台)",
        Callback = function()
            local root = getRoot()
            if root then
                local p = root.Position
                print(("[Log-Hub] 当前坐标: Vector3.new(%.3f, %.3f, %.3f)"):format(p.X, p.Y, p.Z))
                print(("[Log-Hub] CFrame: CFrame.new(%.3f, %.3f, %.3f)"):format(p.X, p.Y, p.Z))
                Window:Notify({
                    Title = "坐标",
                    Content = string.format("X:%.2f Y:%.2f Z:%.2f\n(已输出至控制台)", p.X, p.Y, p.Z),
                    Duration = 4, Type = "Info",
                })
            end
        end,
    })

    InfoTab:AddButton({
        Name = "复制 Vector3 坐标",
        Callback = function()
            local root = getRoot()
            if root then
                local p = root.Position
                local s = string.format("Vector3.new(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
                if setclipboard then
                    setclipboard(s)
                    Window:Notify({ Title = "已复制", Content = s, Duration = 3, Type = "Success" })
                else
                    Window:Notify({ Title = "失败", Content = "执行器不支持剪贴板", Duration = 2, Type = "Error" })
                end
                print("[Log-Hub] 复制坐标:", s)
            end
        end,
    })

    InfoTab:AddButton({
        Name = "复制 CFrame 坐标",
        Callback = function()
            local root = getRoot()
            if root then
                local p = root.Position
                local s = string.format("CFrame.new(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
                if setclipboard then
                    setclipboard(s)
                    Window:Notify({ Title = "已复制", Content = s, Duration = 3, Type = "Success" })
                else
                    Window:Notify({ Title = "失败", Content = "执行器不支持剪贴板", Duration = 2, Type = "Error" })
                end
                print("[Log-Hub] 复制CFrame:", s)
            end
        end,
    })

    InfoTab:AddSection({ Name = "坐标传送" })

    local tbX = InfoTab:AddTextbox({
        Name = "X 坐标",
        Placeholder = "例如: -683.382",
        Default = "0",
        ClearOnFocus = true,
        Flag = "Generic_TpX",
    })

    local tbY = InfoTab:AddTextbox({
        Name = "Y 坐标",
        Placeholder = "例如: 32.139",
        Default = "0",
        ClearOnFocus = true,
        Flag = "Generic_TpY",
    })

    local tbZ = InfoTab:AddTextbox({
        Name = "Z 坐标",
        Placeholder = "例如: -258.695",
        Default = "0",
        ClearOnFocus = true,
        Flag = "Generic_TpZ",
    })

    InfoTab:AddButton({
        Name = "📌 传送到输入坐标",
        Callback = function()
            local root = getRoot()
            if not root then
                Window:Notify({ Title = "失败", Content = "角色未加载", Duration = 2, Type = "Error" })
                return
            end
            local x = tonumber(tbX and tbX:Get() or "")
            local y = tonumber(tbY and tbY:Get() or "")
            local z = tonumber(tbZ and tbZ:Get() or "")
            if not x or not y or not z then
                Window:Notify({ Title = "失败", Content = "X/Y/Z 必须是有效数字", Duration = 3, Type = "Error" })
                return
            end
            local ok, err = pcall(function()
                root.CFrame = CFrame.new(x, y, z)
                local hum = getHum()
                if hum then
                    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
                end
            end)
            if ok then
                Window:Notify({
                    Title = "传送成功",
                    Content = string.format("已传送至 (%.2f, %.2f, %.2f)", x, y, z),
                    Duration = 3, Type = "Success",
                })
                print(("[Log-Hub] 传送到坐标: Vector3.new(%.3f, %.3f, %.3f)"):format(x, y, z))
            else
                Window:Notify({ Title = "传送失败", Content = tostring(err), Duration = 3, Type = "Error" })
                warn("[Log-Hub] 传送失败:", err)
            end
        end,
    })

    InfoTab:AddButton({
        Name = "📥 填入当前坐标到输入框",
        Callback = function()
            local root = getRoot()
            if root then
                local p = root.Position
                if tbX then tbX:Set(string.format("%.3f", p.X)) end
                if tbY then tbY:Set(string.format("%.3f", p.Y)) end
                if tbZ then tbZ:Set(string.format("%.3f", p.Z)) end
                Window:Notify({
                    Title = "已填入",
                    Content = string.format("X:%.2f Y:%.2f Z:%.2f", p.X, p.Y, p.Z),
                    Duration = 2, Type = "Info",
                })
            end
        end,
    })

    InfoTab:AddSection({ Name = "循环传送" })

    InfoTab:AddSlider({
        Name      = "循环间隔",
        Min       = 0.05, Max = 5, Default = 0.5, Increment = 0.05,
        Suffix    = "s",
        Flag      = "Generic_LoopTpInterval",
        Callback  = function(v) miscState.LoopTpInterval = v end,
    })

    InfoTab:AddToggle({
        Name      = "启用循环传送",
        Default   = false,
        Flag      = "Generic_LoopTpEnabled",
        Callback  = function(s)
            miscState.LoopTpEnabled = s
            if s then
                task.spawn(function()
                    local warnCount = 0
                    while miscState.LoopTpEnabled do
                        local root = getRoot()
                        if root then
                            local x = tonumber(tbX and tbX:Get() or "")
                            local y = tonumber(tbY and tbY:Get() or "")
                            local z = tonumber(tbZ and tbZ:Get() or "")
                            if x and y and z then
                                pcall(function()
                                    root.CFrame = CFrame.new(x, y, z)
                                    local hum = getHum()
                                    if hum then
                                        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
                                    end
                                end)
                                warnCount = 0
                            else
                                warnCount = warnCount + 1
                                if warnCount == 1 or warnCount % 20 == 0 then
                                    Window:Notify({ Title = "循环传送跳过", Content = "X/Y/Z 不是有效数字，请检查输入框", Duration = 2, Type = "Warning" })
                                end
                            end
                        end
                        task.wait(miscState.LoopTpInterval)
                    end
                end)
                Window:Notify({ Title = "循环传送", Content = "已启用，每隔 " .. tostring(miscState.LoopTpInterval) .. "s 传送一次", Duration = 2, Type = "Success" })
            else
                Window:Notify({ Title = "循环传送", Content = "已停止", Duration = 1.5, Type = "Info" })
            end
        end,
    })

    InfoTab:AddParagraph({
        Title   = "循环传送说明",
        Content = "用于防止被游戏拉回原位 / 反传送。\n建议间隔 0.3s ~ 1s，间隔太小可能导致卡顿。\n先填入坐标再开启开关。",
    })

    -- ── TAB 2: 场景传送 (该游戏所有子场景) ──
    local SceneTab = Window:AddTab({
        Name = "场景传送",
        Icon = Icons.IconWorld or "rbxassetid://6035153470",
    })

    SceneTab:AddSection({ Name = "当前游戏信息" })

    local sceneInfoLabel = SceneTab:AddLabel({ Text = "加载中..." })
    local function refreshSceneInfo()
        local universeId = game.GameId
        local placeId    = game.PlaceId
        local jobId      = tostring(game.JobId or "N/A")
        sceneInfoLabel:SetText(string.format(
            "UniverseId (GameId):  %d\n当前 PlaceId:         %d\n当前 JobId:           %s\n游戏名:               %s",
            universeId, placeId, jobId, GameName
        ))
    end
    refreshSceneInfo()

    SceneTab:AddButton({
        Name = "📋 复制当前 PlaceId",
        Callback = function()
            if setclipboard then
                setclipboard(tostring(game.PlaceId))
                Window:Notify({ Title = "已复制", Content = "PlaceId: " .. tostring(game.PlaceId), Duration = 2, Type = "Success" })
            else
                Window:Notify({ Title = "失败", Content = "执行器不支持剪贴板", Duration = 2, Type = "Error" })
            end
        end,
    })

    SceneTab:AddSection({ Name = "子场景列表" })

    -- 用 table 缓存 displayName -> placeId，传送时反查
    local sceneCache = {}      -- [displayName] = placeId(number)
    local displayItems = {}    -- 给 Dropdown 用

    local sceneDropdown = SceneTab:AddDropdown({
        Name = "选择目标子场景",
        Items = {},
        Default = nil,
        Multi = false,
        Flag = "Generic_SceneTarget",
    })

    -- 通用：把 placeId + name 写入 cache 并刷新 Dropdown
    local function applyScenes(scenes)
        -- scenes: {{id=.., name=..}, ...}
        sceneCache = {}
        displayItems = {}
        for _, s in ipairs(scenes) do
            local pid = tonumber(s.id)
            local name = tostring(s.name or "未命名")
            -- 避免重名：同名加 PlaceId 后缀
            local displayName = string.format("%s  [%d]", name, pid)
            -- 若仍然重复，再加序号
            while sceneCache[displayName] do
                displayName = displayName .. " "
            end
            sceneCache[displayName] = pid
            table.insert(displayItems, displayName)
        end
        sceneDropdown:Refresh(displayItems)
    end

    SceneTab:AddButton({
        Name = "🔍 自动查询当前游戏子场景",
        Callback = function()
            task.spawn(function()
                local universeId = game.GameId
                if not universeId or universeId == 0 then
                    Window:Notify({ Title = "失败", Content = "无法获取 GameId (UniverseId)", Duration = 3, Type = "Error" })
                    return
                end
                Window:Notify({ Title = "查询中", Content = "正在向 Roblox API 请求子场景...", Duration = 3, Type = "Info" })
                local HttpService = game:GetService("HttpService")
                local scenes = {}
                local cursor = ""
                local pageCount = 0
                -- 分页拉取，最多 5 页防止失控
                while pageCount < 5 do
                    local url = string.format(
                        "https://games.roblox.com/v1/games/%d/places?limit=100%s",
                        universeId,
                        (cursor ~= "" and ("&cursor=" .. cursor)) or ""
                    )
                    local ok, resp = pcall(function() return game:HttpGet(url) end)
                    if not ok then
                        Window:Notify({ Title = "查询失败", Content = "HTTP 请求失败\n" .. tostring(resp):sub(1, 120), Duration = 4, Type = "Error" })
                        return
                    end
                    local data
                    local pok2, perr = pcall(function() data = HttpService:JSONDecode(resp) end)
                    if not pok2 or type(data) ~= "table" then
                        Window:Notify({ Title = "解析失败", Content = "返回不是有效 JSON", Duration = 3, Type = "Error" })
                        return
                    end
                    local arr = data.data or {}
                    for _, p in ipairs(arr) do
                        table.insert(scenes, { id = p.id, name = p.name })
                    end
                    cursor = data.nextPageCursor
                    pageCount = pageCount + 1
                    if not cursor or cursor == "" then break end
                    task.wait(0.3)
                end
                if #scenes == 0 then
                    Window:Notify({ Title = "未找到", Content = "该游戏没有公开的子场景", Duration = 3, Type = "Warning" })
                    return
                end
                applyScenes(scenes)
                Window:Notify({
                    Title = "查询成功",
                    Content = string.format("已加载 %d 个子场景\n可在下拉框中选择", #scenes),
                    Duration = 4, Type = "Success",
                })
                print(("[Log-Hub] 查询到 %d 个子场景"):format(#scenes))
            end)
        end,
    })

    SceneTab:AddButton({
        Name = "🚀 传送到选中子场景",
        Callback = function()
            local selected = sceneDropdown:Get()
            if not selected or selected == "" then
                Window:Notify({ Title = "失败", Content = "请先在下拉框选择目标场景", Duration = 2, Type = "Error" })
                return
            end
            local pid = sceneCache[selected]
            if not pid then
                Window:Notify({ Title = "失败", Content = "无法解析 PlaceId，请重新查询", Duration = 3, Type = "Error" })
                return
            end
            local TeleportService = game:GetService("TeleportService")
            Window:Notify({
                Title = "传送中",
                Content = string.format("正在传送到 PlaceId: %d\n请稍候...", pid),
                Duration = 4, Type = "Info",
            })
            print(("[Log-Hub] 场景传送: PlaceId=%d (%s)"):format(pid, selected))
            task.wait(0.4)
            local ok, err = pcall(function()
                TeleportService:TeleportAsync(pid, { LocalPlayer })
            end)
            if not ok then
                Window:Notify({ Title = "传送失败", Content = tostring(err):sub(1, 200), Duration = 5, Type = "Error" })
                warn("[Log-Hub] 场景传送失败:", err)
            end
        end,
    })

    SceneTab:AddSection({ Name = "手动输入 PlaceId" })

    local manualPlaceId = SceneTab:AddTextbox({
        Name = "目标 PlaceId",
        Placeholder = "例如: 6839179744",
        Default = "",
        ClearOnFocus = true,
        Flag = "Generic_SceneManualPid",
    })

    SceneTab:AddButton({
        Name = "🚀 传送到该 PlaceId",
        Callback = function()
            local pid = tonumber(manualPlaceId and manualPlaceId:Get() or "")
            if not pid then
                Window:Notify({ Title = "失败", Content = "请输入有效的 PlaceId 数字", Duration = 2, Type = "Error" })
                return
            end
            local TeleportService = game:GetService("TeleportService")
            Window:Notify({ Title = "传送中", Content = "正在传送到 PlaceId: " .. pid, Duration = 4, Type = "Info" })
            print(("[Log-Hub] 手动场景传送: PlaceId=%d"):format(pid))
            task.wait(0.4)
            local ok, err = pcall(function()
                TeleportService:TeleportAsync(pid, { LocalPlayer })
            end)
            if not ok then
                Window:Notify({ Title = "传送失败", Content = tostring(err):sub(1, 200), Duration = 5, Type = "Error" })
                warn("[Log-Hub] 手动场景传送失败:", err)
            end
        end,
    })

    SceneTab:AddSection({ Name = "传送至指定服务器 (JobId)" })

    local jobIdTb = SceneTab:AddTextbox({
        Name = "目标 JobId",
        Placeholder = "例如: 00000000-0000-0000-0000-000000000000",
        Default = "",
        ClearOnFocus = true,
        Flag = "Generic_SceneJobId",
    })

    SceneTab:AddButton({
        Name = "🚀 传送至 JobId 服务器",
        Callback = function()
            local pid = tonumber(manualPlaceId and manualPlaceId:Get() or "") or game.PlaceId
            local jid = jobIdTb and jobIdTb:Get() or ""
            if jid == "" then
                Window:Notify({ Title = "失败", Content = "JobId 不能为空", Duration = 2, Type = "Error" })
                return
            end
            local TeleportService = game:GetService("TeleportService")
            Window:Notify({
                Title = "传送中",
                Content = string.format("PlaceId: %d\nJobId: %s", pid, jid),
                Duration = 4, Type = "Info",
            })
            print(("[Log-Hub] JobId 传送: PlaceId=%d JobId=%s"):format(pid, jid))
            task.wait(0.4)
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(pid, jid, LocalPlayer)
            end)
            if not ok then
                Window:Notify({ Title = "传送失败", Content = tostring(err):sub(1, 200), Duration = 5, Type = "Error" })
                warn("[Log-Hub] JobId 传送失败:", err)
            end
        end,
    })

    SceneTab:AddButton({
        Name = "🔄 刷新游戏信息",
        Callback = function()
            refreshSceneInfo()
            Window:Notify({ Title = "已刷新", Content = "当前游戏信息已更新", Duration = 2, Type = "Info" })
        end,
    })

    SceneTab:AddSection({ Name = "说明" })

    SceneTab:AddParagraph({
        Title   = "场景传送说明",
        Content = table.concat({
            "• 子场景 = 同一游戏下的不同 Place",
            "• 自动查询通过 Roblox 官方 API:",
            "  games.roblox.com/v1/games/{UniverseId}/places",
            "• 部分游戏可能未公开子场景列表",
            "• 也可在『手动输入 PlaceId』中输入已知 ID",
            "• JobId 传送可进入指定服务器实例",
            "• 传送需 TeleportService 权限",
            "• 传送后当前脚本会被卸载，需重新注入",
        }, "\n"),
    })

    -- ── TAB 3: 玩家移动 ──
    local PlayerTab = Window:AddTab({
        Name = "玩家",
        Icon = Icons.IconPlayer or "rbxassetid://6034466796",
    })

    PlayerTab:AddSection({ Name = "WalkSpeed (移速)" })
    PlayerTab:AddSlider({
        Name      = "WalkSpeed Value",
        Min       = 16, Max = 500, Default = 16, Increment = 1,
        Flag      = "Generic_WalkSpeed",
        Callback  = function(v) miscState.WalkSpeed = v end,
    })
    PlayerTab:AddToggle({
        Name      = "Enable WalkSpeed",
        Default   = false,
        Flag      = "Generic_WalkSpeedEnabled",
        Callback  = function(s)
            miscState.SetWalkSpeed = s
            if s then
                task.spawn(function()
                    while miscState.SetWalkSpeed do
                        local hum = getHum()
                        if hum and hum.Health > 0 and hum.WalkSpeed ~= miscState.WalkSpeed then
                            hum.WalkSpeed = miscState.WalkSpeed
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

    PlayerTab:AddSection({ Name = "JumpPower (跳跃力)" })
    PlayerTab:AddSlider({
        Name      = "JumpPower Value",
        Min       = 50, Max = 500, Default = 50, Increment = 1,
        Flag      = "Generic_JumpPower",
        Callback  = function(v) miscState.JumpPower = v end,
    })
    PlayerTab:AddToggle({
        Name      = "Enable JumpPower",
        Default   = false,
        Flag      = "Generic_JumpPowerEnabled",
        Callback  = function(s)
            miscState.SetJumpPower = s
            if s then
                task.spawn(function()
                    while miscState.SetJumpPower do
                        local hum = getHum()
                        if hum and hum.Health > 0 and hum.JumpPower ~= miscState.JumpPower then
                            hum.JumpPower = miscState.JumpPower
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

    PlayerTab:AddSection({ Name = "Anti-AFK (防挂机)" })
    PlayerTab:AddToggle({
        Name      = "Anti-AFK",
        Default   = false,
        Flag      = "Generic_AntiAFK",
        Callback  = function(s) miscState.AntiAFK = s end,
    })

    LocalPlayer.Idled:Connect(function()
        if miscState.AntiAFK then
            VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end
    end)

    -- ── TAB 4: 杂项 ──
    local MiscTab = Window:AddTab({
        Name = "杂项",
        Icon = Icons.IconSettings or "rbxassetid://6031280882",
    })

    MiscTab:AddSection({ Name = "快捷操作" })

    MiscTab:AddButton({
        Name = "重生 (Respawn)",
        Callback = function()
            if LocalPlayer.Character then
                LocalPlayer.Character:BreakJoints()
            end
        end,
    })

    MiscTab:AddButton({
        Name = "清除角色死亡状态",
        Callback = function()
            local hum = getHum()
            if hum and hum.Health <= 0 then
                LocalPlayer:LoadCharacter()
            end
        end,
    })

    MiscTab:AddButton({
        Name = "重新注入 Hub",
        Callback = function()
            Window:Notify({
                Title   = "正在重新注入",
                Content = "请稍候...",
                Duration = 2,
                Type    = "Info",
            })
            task.wait(1)
            -- 先销毁当前 UI，再重新加载
            pcall(function() if coordsConn then coordsConn:Disconnect() end end)
            if _G.QuantumUI_Window then pcall(function() _G.QuantumUI_Window:Destroy() end) end
            if _G.QuantumUI_Instance then pcall(function() _G.QuantumUI_Instance:Destroy() end) end
            _G.LogHub_Loaded = nil
            _G.QuantumUI_Window = nil
            _G.QuantumUI_Instance = nil
            task.wait(0.5)
            local reloadOk = pcall(function()
                loadstring(game:HttpGet(GITHUB_BASE .. "/Hub.lua"))()
            end)
            if not reloadOk then
                warn("[Log-Hub] 重新注入失败")
            end
        end,
    })

    MiscTab:AddButton({
        Name = "加载 Infinite Yield (手动)",
        Callback = function()
            task.spawn(function()
                loadScriptByUrl(
                    "https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source",
                    "Infinite Yield (手动)"
                )
            end)
        end,
    })

    MiscTab:AddSection({ Name = "说明" })

    MiscTab:AddParagraph({
        Title   = "通用模式说明",
        Content = table.concat({
            "当前游戏未在注册表中，已加载通用脚本：",
            "",
            "1. Infinite Yield: 按 RightShift 打开命令行",
            "   (已后台自动加载，失败可按上方按钮手动加载)",
            "",
            "2. 位置/信息 Tab: 实时坐标 + 复制坐标",
            "   + 单次传送 (输入 X/Y/Z → 📌 按钮)",
            "   + 循环传送 (防拉回，可调间隔)",
            "   + 一键填入当前坐标到输入框",
            "",
            "3. 场景传送 Tab: 自动查询该游戏所有子场景",
            "   + 下拉框选择 → 一键传送到目标 Place",
            "   + 手动输入 PlaceId 传送",
            "   + JobId 指定服务器传送",
            "",
            "4. 玩家 Tab: WalkSpeed / JumpPower / Anti-AFK",
            "",
            "5. 杂项 Tab: 重生 / 重新注入 Hub",
        }, "\n"),
    })

    -- ── TAB 5: 代码运行 (命令栏) ──
    local CodeTab = Window:AddTab({
        Name = "代码运行",
        Icon = Icons.IconCode or "rbxassetid://6031280882",
    })

    CodeTab:AddSection({ Name = "命令栏 (代码执行器)" })

    CodeTab:AddCommandBar({
        Name = "粘贴代码后运行",
        Placeholder = "在此粘贴要运行的 Lua 代码 (例如 print('hello'))",
        DefaultMode = "single",
        Interval = 0.1,
        Flag = "Generic_CodeBar",
        Callback = function(ok, err, code)
            if ok then
                Window:Notify({
                    Title = "执行完成",
                    Content = "单次运行成功",
                    Duration = 2,
                    Type = "Success",
                })
            else
                Window:Notify({
                    Title = "运行失败",
                    Content = tostring(err),
                    Duration = 4,
                    Type = "Error",
                })
                warn("[Log-Hub] 命令栏执行失败:", err)
            end
        end,
    })

    CodeTab:AddSection({ Name = "使用说明" })

    CodeTab:AddParagraph({
        Title   = "代码运行说明",
        Content = table.concat({
            "• 在上方输入框粘贴 Lua 代码",
            "• 选择运行模式:",
            "  - 单次运行: 执行一次后停止",
            "  - 循环运行: 每隔 0.1s 重复执行，点「停止」结束",
            "• 点击「运行」开始执行，点击「停止」结束循环",
            "• 执行结果 / 错误会输出到控制台 (F9)",
        }, "\n"),
    })

    -- ── 完成通知 ──
    task.wait(0.3)
    Window:Notify({
        Title   = "通用模式已加载",
        Content = "游戏: " .. GameName .. "\nPlaceId: " .. tostring(PlaceId) ..
                  "\n\nInfinite Yield +\n坐标传送 / 循环传送 / 场景传送\nWalkSpeed / Anti-AFK\n按 RightControl 切换 UI",
        Duration = 7,
        Type    = "Info",
    })

    print("[Log-Hub] 通用模式加载完毕 (Game: " .. GameName .. ", PlaceId: " .. tostring(PlaceId) .. ")")
end

-- ══════════════════════════════════════════════════════════════════
-- 6. 主流程 - 检测 → 对应游戏脚本 / 通用脚本
-- ══════════════════════════════════════════════════════════════════

print(string.format("[Log-Hub] 当前游戏: %s (PlaceId: %d)", GameName, PlaceId))

local detected = detectGame()

if detected then
    -- 匹配成功 → 加载对应游戏脚本
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
    -- 匹配失败 → 加载通用脚本 (IY + 杂项)
    task.spawn(loadGenericScript)
end
