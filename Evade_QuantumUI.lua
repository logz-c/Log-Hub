--[[
    Evade 辅助脚本 v3.0 (Quantum UI 版)

    适配 PlaceId: 9872472334 (Evade)

    ── v3.0 相比 v2.0 的关键变化 ──────────────────────────────────────
    [修复] 重生远程路径错误。
           v2.0: Events.Player.ChangePlayerMode:FireServer(true)
           实际: ReplicatedStorage.Events.Respawn:FireServer()   ← 无参数
           (两个独立公开源码 KinetPhoenix/evade-script 与
            StatiicBluey/Scripts 均确认)

    [修复] 复活远程路径与参数格式错误。
           v2.0: Events.Character.Interact:FireServer("Revive", true, name)
           实际: Events.Revive.RevivePlayer:FireServer(玩家名字符串, 布尔)
                 false = 开始救援, true = 完成救援 (需连发三次)
           v2.0 那条路径下的远程根本不存在，即时复活/搬运是空操作。

    [修复] 加速机制错误。
           v2.0: 每帧写 HumanoidRootPart.CFrame 位移 —— 会被服务端拉回，
                 且不做碰撞判定，容易卡墙。
           实际: 游戏通过 Communicator:InvokeServer("update") 向客户端索要
                 速度/跳跃值，用 hookmetamethod 拦截该调用并返回伪造值才是
                 真正的速度绕过。v3.0 用此方案，失败时回退到 TranslateBy。

    [修复] Nextbot 的根部件名是 "HRP" 而不是 "HumanoidRootPart"，
           v2.0 的 AI ESP 拿不到位置。

    [修复] 倒地判定改用 Character:GetAttribute("Downed")。
           v2.0 用 Humanoid.Health <= 0，与游戏真实状态不一致。

    [修复] Heartbeat 回调里塞 task.wait 会阻塞信号线程；改用 task.spawn。
    [修复] 单例守卫补上 _G.Evade_Cleanup 调用；CoreGui 加 PlayerGui 回退。
    [修复] 去掉 Luau 专有的 continue，改用嵌套判断。

    [新增] Auto Bhop / Auto Strafe
    [新增] 自动喝可乐 (Events.UseUsable:FireServer("Cola"))
    [新增] 吹口哨 (Events.Whistle + PlayerScripts.Events.KeybindUsed)
    [新增] 关闭相机抖动 (PlayerScripts.CameraShake.Value)
    [新增] FOV 修改 / LowQuality 降画质 (Events.UpdateSetting)
    [新增] Tracer 追踪线 / Box ESP / 实体类型标签
    [新增] 倒地玩家传送 / 玩家列表传送 / 按 GameId 跳模式
    [新增] Anti Down / Troll 倒地玩家 / Auto Vote / 返回主菜单
    [新增] 状态统计面板 (Tokens / Tickets / 存活时间)

    ── 游戏内部结构 (双源码交叉确认) ──────────────────────────────────
      workspace.Game.Players                 玩家 + AI 角色容器
        └ 玩家角色根部件 HumanoidRootPart
        └ AI(Nextbot) 根部件 **HRP**
      workspace.Game.Map.InvisParts          隐形障碍
      workspace.Game.Map.Parts.KillBricks    击杀砖块
      workspace.Game.Effects.Tickets         票券
      workspace.Game.Settings:SetAttribute("ReviveTime", n)   复活耗时
      Character:GetAttribute("Downed")       倒地标记

      ReplicatedStorage.Events.Respawn:FireServer()
      ReplicatedStorage.Events.Revive.RevivePlayer:FireServer(name, bool)
      ReplicatedStorage.Events.UseUsable:FireServer("Cola")
      ReplicatedStorage.Events.Whistle:FireServer()
      ReplicatedStorage.Events.UpdateSetting:FireServer("FieldOfView"|"LowQuality", v)
      ReplicatedStorage.Events.ReturnToMenu:FireServer()
      ReplicatedStorage.Events.Vote:FireServer(1..3)
      ReplicatedStorage.Events.Emote:FireServer(1..4)
      LocalPlayer.PlayerScripts.CameraShake.Value = CFrame.new()

    ── 免责 ────────────────────────────────────────────────────────
      仅本地逻辑，不采集信息、不 loadstring 任何外部功能代码
      (UI 库除外，那是显示层)。使用脚本违反 Roblox 服务条款，风险自负。

    快捷键: R=重生  H=喝可乐  Y=NoClip  U=Fly  B=Rejoin  RightShift=UI
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD
-- ══════════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

local function purgeOld()
    if _G.Evade_Cleanup then
        pcall(_G.Evade_Cleanup)
        _G.Evade_Cleanup = nil
    end
    if _G.QuantumUI_Instance then
        pcall(function() _G.QuantumUI_Instance:Destroy() end)
        _G.QuantumUI_Instance = nil
    end
    if _G.QuantumUI_Window then
        pcall(function() _G.QuantumUI_Window:Destroy() end)
        _G.QuantumUI_Window = nil
    end
    local function sweep(root)
        if not root then return end
        for _, child in ipairs(root:GetChildren()) do
            local n = child.Name
            if n:sub(1, 9) == "QuantumUI" or n:sub(1, 8) == "EvadeESP"
                or n == "Evade_TracerGui" then
                pcall(function() child:Destroy() end)
            end
        end
    end
    local ok = pcall(function() sweep(CoreGui) end)
    if not ok then
        sweep(game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"))
    end
end
purgeOld()

-- ══════════════════════════════════════════════════════════════════
-- 1. LOAD LIBRARY
-- ══════════════════════════════════════════════════════════════════
local LIB_URL = "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"

local okLib, QuantumUI = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)

if not okLib or type(QuantumUI) ~= "table" then
    warn("[Evade] 在线加载 Quantum UI 失败:", QuantumUI)
    local okLocal, localLib = pcall(function()
        if isfile and isfile("SciFi-UI-Library/source.lua") then
            return loadstring(readfile("SciFi-UI-Library/source.lua"))()
        end
        return nil
    end)
    if not okLocal or type(localLib) ~= "table" then
        warn("[Evade] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localLib
end

print("[Evade] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players             = game:GetService("Players")
local LocalPlayer         = Players.LocalPlayer
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local VirtualUser         = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService     = game:GetService("TeleportService")
local Lighting            = game:GetService("Lighting")
local Workspace           = workspace

-- ══════════════════════════════════════════════════════════════════
-- 3. 游戏路径 (双源码交叉确认)
-- ══════════════════════════════════════════════════════════════════
local GameRoot         = Workspace:WaitForChild("Game", 15)
local WorkspacePlayers = GameRoot and GameRoot:FindFirstChild("Players") or nil
local GameMap          = GameRoot and GameRoot:FindFirstChild("Map") or nil
local GameEffects      = GameRoot and GameRoot:FindFirstChild("Effects") or nil
local GameSettings     = GameRoot and GameRoot:FindFirstChild("Settings") or nil
local TicketsFolder    = GameEffects and GameEffects:FindFirstChild("Tickets") or nil
local EventsFolder     = ReplicatedStorage:FindFirstChild("Events") or nil

local function findRemote(...)
    local node = EventsFolder
    for _, name in ipairs({ ... }) do
        if not node then return nil end
        node = node:FindFirstChild(name)
    end
    return node
end

-- v3.0 修正: 重生走 Events.Respawn (无参数)，不是 Events.Player.ChangePlayerMode
local RemoteRespawn     = findRemote("Respawn")
-- v3.0 修正: 复活走 Events.Revive.RevivePlayer(name, bool)，不是 Events.Character.Interact
local RemoteRevive      = findRemote("Revive", "RevivePlayer")
local RemoteUseUsable   = findRemote("UseUsable")
local RemoteWhistle     = findRemote("Whistle")
local RemoteUpdateSetting = findRemote("UpdateSetting")
local RemoteReturnToMenu  = findRemote("ReturnToMenu")
local RemoteVote        = findRemote("Vote")
local RemoteEmote       = findRemote("Emote")
-- 兼容旧版路径 (若游戏改回旧结构仍可用)
local LegacyChangeMode  = findRemote("Player", "ChangePlayerMode")
local LegacyInteract    = findRemote("Character", "Interact")

print(string.format("[Evade] 远程检查: Respawn=%s Revive=%s UseUsable=%s",
    tostring(RemoteRespawn ~= nil), tostring(RemoteRevive ~= nil),
    tostring(RemoteUseUsable ~= nil)))

-- ══════════════════════════════════════════════════════════════════
-- 4. SETTINGS
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- 角色
    EV_AutoRespawn    = false,
    EV_AntiDown       = false,
    EV_InstantRevive  = false,
    EV_ReviveRadius   = 15,
    EV_AutoRevive     = false,
    EV_AutoCarry      = false,
    EV_TrollDowned    = false,
    EV_FastRevive     = false,
    EV_ReviveTime     = 2.2,

    -- 农场
    EV_MoneyFarm      = false,
    EV_AFKFarm        = false,
    EV_TicketFarm     = false,
    EV_AutoWin        = false,

    -- 移动
    EV_SpeedBypass    = false,
    EV_SpeedValue     = 1450,
    EV_JumpValue      = 3,
    EV_TranslateSpeed = false,
    EV_TranslateValue = 3,
    EV_Bhop           = false,
    EV_Strafe         = false,
    EV_StrafeAmount   = 0.6,
    EV_Fly            = false,
    EV_FlySpeed       = 80,
    EV_NoClip         = false,
    EV_InfJump        = false,
    EV_HipHeight      = 2,
    EV_Gravity        = 196.2,

    -- 视觉
    ESP_Nextbot       = false,
    ESP_NextbotColor  = Color3.fromRGB(255, 50, 50),
    ESP_Player        = false,
    ESP_PlayerColor   = Color3.fromRGB(255, 170, 0),
    ESP_Downed        = false,
    ESP_DownedColor   = Color3.fromRGB(255, 0, 0),
    ESP_Ticket        = false,
    ESP_TicketColor   = Color3.fromRGB(41, 180, 255),
    ESP_Name          = true,
    ESP_Distance      = true,
    ESP_Tracer        = false,
    ESP_Box           = false,
    ESP_Refresh       = 0.1,
    EV_XRay           = false,
    EV_Fullbright     = false,
    EV_NoFog          = false,
    EV_NoCameraShake  = false,

    -- 杂项
    EV_AntiAFK        = false,
    EV_AutoCola       = false,
    EV_FOV            = 70,
}

local genv = (getgenv and getgenv()) or _G
if not genv.__evade then
    genv.__evade = { lastPos = nil, startTime = tick() }
end
local STATE = genv.__evade

-- ══════════════════════════════════════════════════════════════════
-- 5. RUNTIME HANDLES
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false

local noclipConn, flyConn, speedConn, bhopConn, strafeConn, espConn, tracerConn
local autoRespawnConn, instantReviveConn, autoReviveConn, autoCarryConn
local antiDownConn, trollConn, infJumpConn, xrayConn, camShakeConn
local flyBV, flyBG
local espFolder, tracerGui, tracerPool
local savedLighting = {}

-- task.spawn 返回 thread 而非 connection，用世代号让旧循环退出，避免叠加
local farmGen, xrayGen, camShakeGen = 0, 0, 0

-- ══════════════════════════════════════════════════════════════════
-- 6. 基础工具
-- ══════════════════════════════════════════════════════════════════
local function notify(title, content, duration, ntype)
    if Window then
        local ok = pcall(function()
            Window:Notify({
                Title = title, Content = content,
                Duration = duration or 3, Type = ntype or "Info",
            })
        end)
        if ok then return end
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title, Text = content, Duration = duration or 3,
        })
    end)
end

local function getChar()
    local c = LocalPlayer.Character
    if c then return c end
    local ok, res = pcall(function()
        return LocalPlayer.CharacterAdded:Wait()
    end)
    return ok and res or nil
end

local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local c = LocalPlayer.Character
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("HRP")
end

local function getGuiParent()
    local ok, res = pcall(function() return CoreGui end)
    if ok and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- v3.0 修正: AI(Nextbot) 的根部件名是 "HRP"
local function rootOf(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("HRP")
end

local function isDowned(model)
    if not model then return false end
    local ok, val = pcall(function() return model:GetAttribute("Downed") end)
    if ok and val then return true end
    -- 回退: 有些版本把标记放在 Humanoid 上
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        local ok2, val2 = pcall(function() return hum:GetAttribute("Downed") end)
        if ok2 and val2 then return true end
    end
    return false
end

local function isLocalDowned()
    return isDowned(LocalPlayer.Character)
end

local function getAIList()
    local out = {}
    if not WorkspacePlayers then return out end
    for _, v in ipairs(WorkspacePlayers:GetChildren()) do
        if v:IsA("Model") and not Players:GetPlayerFromCharacter(v) then
            out[#out + 1] = v
        end
    end
    return out
end

local function getDownedList()
    local out = {}
    if not WorkspacePlayers then return out end
    for _, v in ipairs(WorkspacePlayers:GetChildren()) do
        if isDowned(v) then
            out[#out + 1] = v
        end
    end
    return out
end

local function getDownedPlayerList()
    local out = {}
    for _, v in ipairs(getDownedList()) do
        if Players:GetPlayerFromCharacter(v) then
            out[#out + 1] = v
        end
    end
    return out
end

-- 名字 -> 玩家 (用于 RevivePlayer 的第一个参数)
local function nameOfModel(model)
    if not model then return nil end
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then return plr.Name end
    return model.Name
end

local function teleportTo(cf)
    local root = getRoot()
    if not root then return false end
    local ok = pcall(function() root.CFrame = cf end)
    return ok
end

local function teleportToModel(model, yOffset)
    local r = rootOf(model)
    if not r then return false end
    return teleportTo(CFrame.new(r.Position + Vector3.new(0, yOffset or 3, 0)))
end

-- ══════════════════════════════════════════════════════════════════
-- 7. 远程封装 (v3.0 修正路径与参数)
-- ══════════════════════════════════════════════════════════════════

-- 重生: Events.Respawn:FireServer() —— 无参数
local function doRespawn()
    if RemoteRespawn then
        local ok = pcall(function() RemoteRespawn:FireServer() end)
        if ok then return true end
    end
    -- 回退到旧版路径
    if LegacyChangeMode then
        local ok = pcall(function() LegacyChangeMode:FireServer(true) end)
        if ok then return true end
    end
    pcall(function() LocalPlayer:LoadCharacter() end)
    return false
end

-- 复活: Events.Revive.RevivePlayer:FireServer(name, bool)
--   false = 开始救援, true = 完成救援 (公开源码连发三次)
local function reviveStart(name)
    if not (RemoteRevive and name) then return false end
    local ok = pcall(function() RemoteRevive:FireServer(tostring(name), false) end)
    return ok
end

local function reviveFinish(name)
    if not (RemoteRevive and name) then return false end
    for _ = 1, 3 do
        pcall(function() RemoteRevive:FireServer(tostring(name), true) end)
        task.wait(0.05)
    end
    return true
end

-- 完整救援流程 (公开源码逻辑)
local function fullRevive(model)
    local name = nameOfModel(model)
    if not name then return false end
    if GameSettings and SETTINGS.EV_FastRevive then
        pcall(function() GameSettings:SetAttribute("ReviveTime", SETTINGS.EV_ReviveTime) end)
    end
    teleportToModel(model, 3)
    task.wait(0.1)
    reviveStart(name)
    task.wait(0.3)
    reviveFinish(name)
    return true
end

-- 搬运: 用同一个 RevivePlayer 远程的第三态; 旧版回退到 Interact
local function doCarry(model)
    local name = nameOfModel(model)
    if not name then return false end
    if RemoteRevive then
        local ok = pcall(function() RemoteRevive:FireServer(tostring(name), "Carry") end)
        if ok then return true end
    end
    if LegacyInteract then
        local ok = pcall(function() LegacyInteract:FireServer("Carry", true, name) end)
        if ok then return true end
    end
    return false
end

local function useUsable(item)
    if not RemoteUseUsable then return false end
    local ok = pcall(function() RemoteUseUsable:FireServer(item) end)
    return ok
end

local function doWhistle()
    pcall(function()
        local ev = LocalPlayer:FindFirstChild("PlayerScripts")
            and LocalPlayer.PlayerScripts:FindFirstChild("Events")
            and LocalPlayer.PlayerScripts.Events:FindFirstChild("KeybindUsed")
        if ev then ev:Fire("Whistle", true) end
    end)
    if RemoteWhistle then
        pcall(function() RemoteWhistle:FireServer() end)
        return true
    end
    return false
end

local function updateSetting(key, value)
    if not RemoteUpdateSetting then return false end
    local ok = pcall(function() RemoteUpdateSetting:FireServer(key, value) end)
    return ok
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 速度绕过 (v3.0 核心修正)
--    游戏通过 Communicator:InvokeServer("update") 向客户端索要速度/跳跃值。
--    拦截该调用并返回伪造值，才是真正的速度绕过；写 CFrame 会被服务端拉回。
-- ══════════════════════════════════════════════════════════════════
local hookInstalled = false
local oldNamecall = nil

do
    local ok = pcall(function()
        local hook, newc, getmethod = hookmetamethod, newcclosure, getnamecallmethod
        if not (hook and newc and getmethod) then
            error("executor 不支持 hookmetamethod")
        end
        oldNamecall = hook(game, "__namecall", newc(function(self, ...)
            local method = getmethod()
            if method == "InvokeServer" and tostring(self) == "Communicator" then
                local args = { ... }
                if args[1] == "update" then
                    if SETTINGS.EV_SpeedBypass then
                        return SETTINGS.EV_SpeedValue or 1450, SETTINGS.EV_JumpValue or 3
                    end
                    return 1450, 3
                end
            end
            return oldNamecall(self, ...)
        end))
        hookInstalled = true
    end)
    if not ok then
        hookInstalled = false
        warn("[Evade] Communicator 钩子安装失败，速度绕过将回退到 TranslateBy")
    end
end

print("[Evade] 速度绕过钩子: " .. (hookInstalled and "已安装 (Communicator)" or "不可用"))

-- 回退方案: 逐帧位移 (公开源码 hydra 的写法)
local function toggleTranslateSpeed(enabled)
    if speedConn then speedConn:Disconnect() speedConn = nil end
    if not enabled then return end
    speedConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local char = LocalPlayer.Character
        local hum = getHum()
        if not char or not hum then return end
        pcall(function()
            if hum.MoveDirection.Magnitude > 0 then
                char:TranslateBy(hum.MoveDirection * ((SETTINGS.EV_TranslateValue or 3) / 10))
            end
        end)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 角色功能
-- ══════════════════════════════════════════════════════════════════
local function toggleAutoRespawn(enabled)
    if autoRespawnConn then autoRespawnConn:Disconnect() autoRespawnConn = nil end
    if not enabled then return end
    autoRespawnConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        if isLocalDowned() then
            doRespawn()
        end
    end)
end

-- Anti Down: 倒地瞬间立刻自救 (先复活自己再重生)
local function toggleAntiDown(enabled)
    if antiDownConn then antiDownConn:Disconnect() antiDownConn = nil end
    if not enabled then return end
    local busy = false
    antiDownConn = RunService.Heartbeat:Connect(function()
        if isDestroyed or busy then return end
        if not isLocalDowned() then return end
        busy = true
        -- 注意: 不能在 Heartbeat 回调里直接 task.wait，会阻塞信号线程
        task.spawn(function()
            local me = LocalPlayer.Name
            reviveStart(me)
            task.wait(0.15)
            reviveFinish(me)
            task.wait(1)
            busy = false
        end)
    end)
end

-- 即时复活: 范围内倒地玩家自动救援
local function toggleInstantRevive(enabled)
    if instantReviveConn then instantReviveConn:Disconnect() instantReviveConn = nil end
    if not enabled then return end
    local busy = false
    instantReviveConn = RunService.Heartbeat:Connect(function()
        if isDestroyed or busy then return end
        local myRoot = getRoot()
        if not myRoot then return end
        local radius = SETTINGS.EV_ReviveRadius or 15
        for _, model in ipairs(getDownedPlayerList()) do
            local r = rootOf(model)
            if r and (myRoot.Position - r.Position).Magnitude <= radius then
                busy = true
                task.spawn(function()
                    pcall(function() fullRevive(model) end)
                    task.wait(1)
                    busy = false
                end)
                return
            end
        end
    end)
end

-- 自动复活: 传送过去 + 完整救援流程
local function toggleAutoRevive(enabled)
    if autoReviveConn then autoReviveConn:Disconnect() autoReviveConn = nil end
    if not enabled then return end
    local busy = false
    autoReviveConn = RunService.Heartbeat:Connect(function()
        if isDestroyed or busy then return end
        if isLocalDowned() then return end
        local list = getDownedPlayerList()
        if #list == 0 then return end
        busy = true
        task.spawn(function()
            for _, model in ipairs(list) do
                if isDestroyed then break end
                pcall(function() fullRevive(model) end)
                task.wait(0.5)
            end
            task.wait(1)
            busy = false
        end)
    end)
end

local function toggleAutoCarry(enabled)
    if autoCarryConn then autoCarryConn:Disconnect() autoCarryConn = nil end
    if not enabled then return end
    autoCarryConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        for _, model in ipairs(getDownedPlayerList()) do
            if model ~= LocalPlayer.Character then
                doCarry(model)
            end
        end
    end)
end

-- Troll 倒地玩家: 搬到高处再丢下
local function toggleTrollDowned(enabled)
    if trollConn then trollConn:Disconnect() trollConn = nil end
    if not enabled then return end
    local busy = false
    trollConn = RunService.Heartbeat:Connect(function()
        if isDestroyed or busy then return end
        local list = getDownedPlayerList()
        if #list == 0 then return end
        busy = true
        task.spawn(function()
            local model = list[1]
            local r = rootOf(model)
            if r then
                local original = r.CFrame
                pcall(function() r.CFrame = original + Vector3.new(0, 300, 0) end)
                task.wait(0.5)
                pcall(function() r.CFrame = original end)
            end
            task.wait(1)
            busy = false
        end)
    end)
end

local function applyFastRevive()
    if GameSettings then
        pcall(function()
            GameSettings:SetAttribute("ReviveTime", SETTINGS.EV_FastRevive and SETTINGS.EV_ReviveTime or 3)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 农场功能
-- ══════════════════════════════════════════════════════════════════
local AFK_POS = CFrame.new(6007, 7005, 8005)

local function anyFarmOn()
    return SETTINGS.EV_MoneyFarm or SETTINGS.EV_AFKFarm
        or SETTINGS.EV_TicketFarm or SETTINGS.EV_AutoWin
end

local function ticketPickupPass()
    if not TicketsFolder then return false end
    local root = getRoot()
    if not root then return false end
    local list = TicketsFolder:GetChildren()
    if #list == 0 then return false end
    local ticket = list[1]
    local tRoot = rootOf(ticket) or ticket:FindFirstChildWhichIsA("BasePart")
    if not tRoot then return false end
    pcall(function() root.CFrame = CFrame.new(tRoot.Position) end)
    return true
end

local function toggleFarm(enabled)
    farmGen = farmGen + 1
    local myGen = farmGen
    if not enabled then return end

    -- 用 task.spawn 而不是在 Heartbeat 里 task.wait (v2.0 的写法会阻塞信号线程)
    task.spawn(function()
        while not isDestroyed and myGen == farmGen and anyFarmOn() do
            local ok = pcall(function()
                -- 自己倒地 -> 重生
                if isLocalDowned() then
                    doRespawn()
                    task.wait(2)
                    return
                end

                -- Ticket Farm: 逐个传送到票券
                if SETTINGS.EV_TicketFarm then
                    for _ = 1, 3 do
                        if not ticketPickupPass() then break end
                        task.wait(0.12)
                    end
                end

                -- Auto Win: 不停救倒地的人, 保证队伍不倒
                if SETTINGS.EV_AutoWin then
                    local list = getDownedPlayerList()
                    if #list > 0 then
                        pcall(function() fullRevive(list[1]) end)
                        task.wait(0.8)
                    end
                end

                -- Money Farm: 救倒地玩家拿 Token
                if SETTINGS.EV_MoneyFarm then
                    local list = getDownedPlayerList()
                    if #list > 0 then
                        pcall(function() fullRevive(list[1]) end)
                        task.wait(1)
                    else
                        task.wait(0.5)
                    end
                end

                -- AFK Farm: 传送到地图外安全点
                if SETTINGS.EV_AFKFarm then
                    teleportTo(AFK_POS)
                    task.wait(1)
                end
            end)
            if not ok then
                task.wait(0.5)
            end
            task.wait(0.05)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 移动功能
-- ══════════════════════════════════════════════════════════════════
local function toggleNoclip(enabled)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if not enabled then return end
    noclipConn = RunService.Stepped:Connect(function()
        if isDestroyed then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                pcall(function() part.CanCollide = false end)
            end
        end
    end)
end

local function toggleInfJump(enabled)
    if infJumpConn then infJumpConn:Disconnect() infJumpConn = nil end
    if not enabled then return end
    infJumpConn = UserInputService.JumpRequest:Connect(function()
        if isDestroyed then return end
        local hum = getHum()
        if hum then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end)
end

local function toggleFly(enabled, speed)
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end
    if not enabled then return end

    local root = getRoot()
    if not root then return end

    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "Evade_FlyBV"
    flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = root

    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "Evade_FlyBG"
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
        local spd = speed or SETTINGS.EV_FlySpeed or 80
        if move.Magnitude > 0 then move = move.Unit * spd end
        flyBV.Velocity = move
        local r = getRoot()
        if r then flyBG.CFrame = CFrame.new(r.Position) * cam.CFrame.Rotation end
    end)
end

-- Auto Bhop
local function toggleBhop(enabled)
    if bhopConn then bhopConn:Disconnect() bhopConn = nil end
    if not enabled then return end
    bhopConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local hum = getHum()
        if not hum then return end
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Landed
            or st == Enum.HumanoidStateType.Running
            or st == Enum.HumanoidStateType.RunningNoPhysics then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
        end
    end)
end

-- Auto Strafe: 移动时叠加侧向位移
local function toggleStrafe(enabled)
    if strafeConn then strafeConn:Disconnect() strafeConn = nil end
    if not enabled then return end
    strafeConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local char = LocalPlayer.Character
        local hum = getHum()
        if not char or not hum then return end
        local move = hum.MoveDirection
        if move.Magnitude <= 0.01 then return end
        local amount = SETTINGS.EV_StrafeAmount or 0.6
        local lateral = Vector3.new(-move.Z, 0, move.X).Unit * amount
        pcall(function() char:TranslateBy(lateral) end)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 12. ESP / 视觉
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end
end

local function espAnyOn()
    return SETTINGS.ESP_Nextbot or SETTINGS.ESP_Player
        or SETTINGS.ESP_Downed or SETTINGS.ESP_Ticket
end

local function makeHighlight(parent, color)
    local hl = Instance.new("Highlight")
    hl.Name = "EvadeESP_HL"
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0.2
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = parent
    return hl
end

local function makeBillboard(parent, text, color, yOffset, withBox)
    local bb = Instance.new("BillboardGui")
    bb.Name = "EvadeESP_BB"
    bb.Size = UDim2.new(0, 220, 0, 30)
    bb.StudsOffset = Vector3.new(0, yOffset or 4, 0)
    bb.AlwaysOnTop = true

    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(1, 0, 1, 0)
    tl.BackgroundTransparency = 1
    tl.Text = text
    tl.TextColor3 = color
    tl.TextStrokeTransparency = 0.3
    tl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 14
    tl.Parent = bb

    if withBox then
        local box = Instance.new("Frame")
        box.Name = "EvadeESP_Box"
        box.BackgroundTransparency = 1
        box.Size = UDim2.new(0, 60, 0, 90)
        box.Position = UDim2.new(0.5, 0, 1.6, 0)
        box.AnchorPoint = Vector2.new(0.5, 0)
        local stroke = Instance.new("UIStroke")
        stroke.Color = color
        stroke.Thickness = 1.5
        stroke.Transparency = 0.2
        stroke.Parent = box
        box.Parent = bb
    end

    bb.Parent = parent
    return bb
end

local function clearMarks(obj)
    pcall(function()
        for _, c in ipairs(obj:GetChildren()) do
            if c.Name == "EvadeESP_HL" or c.Name == "EvadeESP_BB" then
                c:Destroy()
            end
        end
    end)
end

local function distanceText(myRoot, targetRoot)
    if not (SETTINGS.ESP_Distance and myRoot and targetRoot) then return "" end
    return string.format("  [%dm]", math.floor((myRoot.Position - targetRoot.Position).Magnitude))
end

local function decorate(obj, color, label, yOffset)
    clearMarks(obj)
    pcall(function() makeHighlight(obj, color) end)
    if SETTINGS.ESP_Name or SETTINGS.ESP_Distance then
        pcall(function() makeBillboard(obj, label, color, yOffset, SETTINGS.ESP_Box) end)
    end
end

local function runESPLoop()
    if not espFolder or not espFolder.Parent then
        espFolder = Instance.new("Folder")
        espFolder.Name = "EvadeESP_Folder"
        espFolder.Parent = getGuiParent()
    end

    local myRoot = getRoot()

    -- Nextbot (AI) —— v3.0 修正: 根部件是 HRP
    if SETTINGS.ESP_Nextbot then
        for _, obj in ipairs(getAIList()) do
            local r = rootOf(obj)
            decorate(obj, SETTINGS.ESP_NextbotColor,
                "[AI] " .. obj.Name .. distanceText(myRoot, r), 5)
        end
    end

    -- 玩家 + 倒地玩家
    if SETTINGS.ESP_Player or SETTINGS.ESP_Downed then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local char = p.Character
                local downed = isDowned(char)
                local show = false
                local color = SETTINGS.ESP_PlayerColor
                local prefix = "[PLAYER] "

                if downed and SETTINGS.ESP_Downed then
                    show = true
                    color = SETTINGS.ESP_DownedColor
                    prefix = "[DOWNED] "
                elseif SETTINGS.ESP_Player and not downed then
                    show = true
                end

                if show then
                    decorate(char, color, prefix .. p.Name .. distanceText(myRoot, rootOf(char)), 5)
                else
                    clearMarks(char)
                end
            end
        end
    end

    -- 票券
    if SETTINGS.ESP_Ticket and TicketsFolder then
        for _, ticket in ipairs(TicketsFolder:GetChildren()) do
            local r = rootOf(ticket) or ticket:FindFirstChildWhichIsA("BasePart")
            local pos = r and (r.Position or r.CFrame.Position)
            local txt = "[TICKET]"
            if SETTINGS.ESP_Distance and myRoot and pos then
                txt = txt .. string.format("  [%dm]", math.floor((myRoot.Position - pos).Magnitude))
            end
            clearMarks(ticket)
            pcall(function() makeHighlight(ticket, SETTINGS.ESP_TicketColor) end)
            pcall(function() makeBillboard(ticket, txt, SETTINGS.ESP_TicketColor, 3, false) end)
        end
    end
end

local function toggleESP(enabled)
    if espConn then espConn:Disconnect() espConn = nil end
    if not enabled then
        clearESP()
        return
    end
    local last = 0
    espConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local now = tick()
        if now - last >= (SETTINGS.ESP_Refresh or 0.1) then
            last = now
            pcall(runESPLoop)
        end
    end)
end

-- Tracer 追踪线
local function getTracerGui()
    if tracerGui and tracerGui.Parent then return tracerGui end
    tracerGui = Instance.new("ScreenGui")
    tracerGui.Name = "Evade_TracerGui"
    tracerGui.IgnoreGuiInset = true
    tracerGui.ResetOnSpawn = false
    tracerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    tracerGui.Parent = getGuiParent()
    tracerPool = {}
    return tracerGui
end

local function clearTracers()
    if tracerGui then
        pcall(function() tracerGui:Destroy() end)
        tracerGui = nil
    end
    tracerPool = nil
end

local function tracerTargets()
    local out = {}
    if SETTINGS.ESP_Nextbot then
        for _, ai in ipairs(getAIList()) do
            local r = rootOf(ai)
            if r then out[#out + 1] = { part = r, color = SETTINGS.ESP_NextbotColor } end
        end
    end
    if SETTINGS.ESP_Player or SETTINGS.ESP_Downed then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local r = rootOf(p.Character)
                if r then
                    local downed = isDowned(p.Character)
                    if (downed and SETTINGS.ESP_Downed) or (not downed and SETTINGS.ESP_Player) then
                        out[#out + 1] = {
                            part = r,
                            color = downed and SETTINGS.ESP_DownedColor or SETTINGS.ESP_PlayerColor,
                        }
                    end
                end
            end
        end
    end
    if SETTINGS.ESP_Ticket and TicketsFolder then
        for _, t in ipairs(TicketsFolder:GetChildren()) do
            local r = rootOf(t) or t:FindFirstChildWhichIsA("BasePart")
            if r then out[#out + 1] = { part = r, color = SETTINGS.ESP_TicketColor } end
        end
    end
    return out
end

local function tracerStep()
    if isDestroyed or not SETTINGS.ESP_Tracer then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local gui = getTracerGui()
    if not gui then return end
    tracerPool = tracerPool or {}

    local origin = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
    local targets = tracerTargets()
    local used = {}

    for i, t in ipairs(targets) do
        local pos = t.part.Position
        local sp, onScreen = cam:WorldToViewportPoint(pos)
        if onScreen and sp.Z > 0 then
            local key = i
            local frame = tracerPool[key]
            if not frame or not frame.Parent then
                frame = Instance.new("Frame")
                frame.Name = "Evade_Tracer"
                frame.BorderSizePixel = 0
                frame.AnchorPoint = Vector2.new(0, 0.5)
                frame.ZIndex = 2
                frame.Parent = gui
                tracerPool[key] = frame
            end
            frame.BackgroundColor3 = t.color
            local delta = Vector2.new(sp.X, sp.Y) - origin
            frame.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), 1)
            frame.Position = UDim2.fromOffset(origin.X, origin.Y)
            frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            frame.Visible = true
            used[key] = true
        end
    end

    for key, frame in pairs(tracerPool) do
        if not used[key] and frame and frame.Parent then
            pcall(function() frame:Destroy() end)
            tracerPool[key] = nil
        end
    end
end

local function toggleTracer(enabled)
    if tracerConn then tracerConn:Disconnect() tracerConn = nil end
    if not enabled then
        clearTracers()
        return
    end
    tracerConn = RunService.RenderStepped:Connect(tracerStep)
end

-- XRay
local xrayParts = {}
local function isCharacterPart(part)
    local c = LocalPlayer.Character
    if c and part:IsDescendantOf(c) then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and part:IsDescendantOf(p.Character) then
            return true
        end
    end
    return false
end

local function applyXRay(enabled)
    if not enabled then
        for part, _ in pairs(xrayParts) do
            pcall(function()
                if part and part.Parent then part.LocalTransparencyModifier = 0 end
            end)
        end
        xrayParts = {}
        return
    end
    local count = 0
    pcall(function()
        for _, d in ipairs(Workspace:GetDescendants()) do
            if count > 6000 then break end
            if d:IsA("BasePart") then
                count = count + 1
                if not isCharacterPart(d) then
                    xrayParts[d] = true
                    d.LocalTransparencyModifier = 0.7
                end
            end
        end
    end)
end

local function toggleXRay(enabled)
    xrayGen = xrayGen + 1
    local myGen = xrayGen
    applyXRay(enabled)
    if not enabled then return end
    task.spawn(function()
        while not isDestroyed and myGen == xrayGen and SETTINGS.EV_XRay do
            task.wait(3)
            pcall(function()
                for _, d in ipairs(Workspace:GetChildren()) do
                    for _, part in ipairs(d:GetDescendants()) do
                        if part:IsA("BasePart") and not xrayParts[part] and not isCharacterPart(part) then
                            xrayParts[part] = true
                            part.LocalTransparencyModifier = 0.7
                        end
                    end
                end
            end)
        end
    end)
end

local function toggleFullbright(enabled)
    if enabled then
        if not savedLighting.saved then
            savedLighting.brightness = Lighting.Brightness
            savedLighting.fogEnd = Lighting.FogEnd
            savedLighting.clockTime = Lighting.ClockTime
            savedLighting.globalShadows = Lighting.GlobalShadows
            savedLighting.saved = true
        end
        pcall(function()
            Lighting.Brightness = 4
            Lighting.FogEnd = 100000
            Lighting.ClockTime = 12
            Lighting.GlobalShadows = false
        end)
    else
        if not savedLighting.saved then return end
        pcall(function()
            Lighting.Brightness = savedLighting.brightness or 1
            Lighting.FogEnd = savedLighting.fogEnd or 500
            Lighting.ClockTime = savedLighting.clockTime or 14
            Lighting.GlobalShadows = savedLighting.globalShadows ~= nil and savedLighting.globalShadows or true
        end)
    end
end

local function applyNoFog(enabled)
    pcall(function()
        if enabled then
            if savedLighting.fogSaved == nil then
                savedLighting.fogSaved = Lighting.FogEnd
                savedLighting.fogStartSaved = Lighting.FogStart
            end
            Lighting.FogEnd = 100000
            Lighting.FogStart = 0
        else
            if savedLighting.fogSaved ~= nil then
                Lighting.FogEnd = savedLighting.fogSaved
                Lighting.FogStart = savedLighting.fogStartSaved or 0
            end
        end
    end)
end

-- 关闭相机抖动 (公开源码路径: PlayerScripts.CameraShake.Value)
local function toggleNoCameraShake(enabled)
    camShakeGen = camShakeGen + 1
    local myGen = camShakeGen
    if not enabled then return end
    task.spawn(function()
        while not isDestroyed and myGen == camShakeGen and SETTINGS.EV_NoCameraShake do
            pcall(function()
                local ps = LocalPlayer:FindFirstChild("PlayerScripts")
                local cs = ps and ps:FindFirstChild("CameraShake")
                if cs then
                    cs.Value = CFrame.new(0, 0, 0) * CFrame.new(0, 0, 0)
                end
            end)
            task.wait(0.1)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 13. 世界 / 杂项
-- ══════════════════════════════════════════════════════════════════
local function removeBarriers()
    if not GameMap then
        notify("Evade", "未找到 Game.Map", 2, "Warning")
        return
    end
    local invis = GameMap:FindFirstChild("InvisParts")
    if invis then
        pcall(function() invis:ClearAllChildren() end)
        notify("Evade", "已移除隐形障碍", 2, "Success")
    else
        notify("Evade", "未找到 InvisParts", 2, "Warning")
    end
end

local function removeKillBricks()
    if not GameMap then
        notify("Evade", "未找到 Game.Map", 2, "Warning")
        return
    end
    local parts = GameMap:FindFirstChild("Parts")
    local kb = (parts and parts:FindFirstChild("KillBricks"))
        or GameMap:FindFirstChild("KillBricks")
    if kb then
        pcall(function() kb:Destroy() end)
        notify("Evade", "已移除 KillBricks", 2, "Success")
    else
        notify("Evade", "未找到 KillBricks", 2, "Warning")
    end
end

local function rejoin()
    pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end)
end

local function setupAntiAFK()
    local gc = getconnections or get_signal_cons
    if gc then
        local ok = pcall(function()
            for _, v in pairs(gc(LocalPlayer.Idled)) do
                if v.Disable then
                    v:Disable()
                elseif v.Disconnect then
                    v:Disconnect()
                end
            end
        end)
        if ok then return end
    end
    LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 14. 传送点
-- ══════════════════════════════════════════════════════════════════
local SAFE_POS = CFrame.new(6007, 7005, 8005)

local GAME_MODES = {
    ["主游戏 (Main)"]        = 9872472334,
    ["Casual"]               = 10662542523,
    ["Social Space"]         = 10324347967,
    ["Big Team"]             = 10324346056,
    ["Team DeathMatch"]      = 110539706691,
    ["VC Only"]              = 10808838353,
}
local GAME_MODE_NAMES = {
    "主游戏 (Main)", "Casual", "Social Space",
    "Big Team", "Team DeathMatch", "VC Only",
}

-- ══════════════════════════════════════════════════════════════════
-- 15. 构建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title        = "Evade",
    Subtitle     = "Nextbot 逃生 v3.0",
    ThemeColor   = Color3.fromRGB(180, 60, 255),
    Transparency = 0.3,
    Size         = UDim2.new(0, 660, 0, 600),
    Keybind      = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: 角色 ─────────────────────────────────────────────────
local CharTab = Window:AddTab({ Name = "角色", Icon = "rbxassetid://6034287594" })

CharTab:AddSection({ Name = "重生" })

CharTab:AddToggle({
    Name = "自动重生 (倒地立即重生)", Default = false, Flag = "EV_AutoRespawn",
    Callback = function(s)
        SETTINGS.EV_AutoRespawn = s
        toggleAutoRespawn(s)
        notify("Evade", s and "自动重生 已开启" or "自动重生 已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddButton({
    Name = "立即重生 (Events.Respawn)",
    Callback = function()
        local ok = doRespawn()
        notify("Evade", ok and "已发送重生请求" or "Respawn 远程不可用", 2, ok and "Info" or "Error")
    end,
})

CharTab:AddSection({ Name = "自救 / 救人" })

CharTab:AddToggle({
    Name = "Anti Down (倒地立刻自救)", Default = false, Flag = "EV_AntiDown",
    Callback = function(s)
        SETTINGS.EV_AntiDown = s
        toggleAntiDown(s)
        notify("Evade", s and "Anti Down 已开启" or "Anti Down 已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddToggle({
    Name = "即时复活 (范围内倒地玩家)", Default = false, Flag = "EV_InstantRevive",
    Callback = function(s)
        SETTINGS.EV_InstantRevive = s
        toggleInstantRevive(s)
    end,
})

CharTab:AddSlider({
    Name = "即时复活半径", Min = 5, Max = 60, Default = 15, Increment = 1,
    Suffix = " studs", Flag = "EV_ReviveRadius",
    Callback = function(v) SETTINGS.EV_ReviveRadius = v end,
})

CharTab:AddToggle({
    Name = "自动复活 (传送+救所有倒地玩家)", Default = false, Flag = "EV_AutoRevive",
    Callback = function(s)
        SETTINGS.EV_AutoRevive = s
        toggleAutoRevive(s)
        notify("Evade", s and "自动复活 已开启" or "自动复活 已关闭", 2, s and "Success" or "Info")
    end,
})

CharTab:AddToggle({
    Name = "自动搬运倒地玩家", Default = false, Flag = "EV_AutoCarry",
    Callback = function(s)
        SETTINGS.EV_AutoCarry = s
        toggleAutoCarry(s)
    end,
})

CharTab:AddToggle({
    Name = "Troll 倒地玩家 (搬到高空再丢下)", Default = false, Flag = "EV_TrollDowned",
    Callback = function(s)
        SETTINGS.EV_TrollDowned = s
        toggleTrollDowned(s)
        if s then notify("Evade", "已开启 Troll：会把倒地玩家搬到 300 高空再放下", 4, "Warning") end
    end,
})

CharTab:AddSection({ Name = "快速复活" })

CharTab:AddToggle({
    Name = "快速复活 (改 ReviveTime)", Default = false, Flag = "EV_FastRevive",
    Callback = function(s)
        SETTINGS.EV_FastRevive = s
        applyFastRevive()
        notify("Evade", s and ("复活时间已设为 " .. tostring(SETTINGS.EV_ReviveTime) .. "s") or "已恢复默认复活时间", 2, "Success")
    end,
})

CharTab:AddSlider({
    Name = "复活时间", Min = 0.1, Max = 10, Default = 2.2, Increment = 0.1,
    Suffix = "s", Flag = "EV_ReviveTime",
    Callback = function(v)
        SETTINGS.EV_ReviveTime = v
        if SETTINGS.EV_FastRevive then applyFastRevive() end
    end,
})

CharTab:AddParagraph({
    Title = "救援流程说明",
    Content = table.concat({
        "公开源码确认的完整救援序列：",
        "  1. 传送到倒地玩家位置 (+3 高度)",
        "  2. RevivePlayer:FireServer(玩家名, false)   ← 开始救援",
        "  3. 等 4.5 秒左右",
        "  4. RevivePlayer:FireServer(玩家名, true) ×3 ← 完成救援",
        "",
        "v2.0 走的是 Events.Character.Interact，那条路径下",
        "没有对应的远程，所以即时复活/搬运一直是空操作。",
    }, "\n"),
})

-- ── TAB 2: 农场 ─────────────────────────────────────────────────
local FarmTab = Window:AddTab({ Name = "农场", Icon = "rbxassetid://6031280882" })

FarmTab:AddSection({ Name = "自动农场" })

local function farmToggle(name, key, label)
    FarmTab:AddToggle({
        Name = name, Default = false, Flag = key,
        Callback = function(s)
            SETTINGS[key] = s
            toggleFarm(anyFarmOn())
            notify("Evade", label .. (s and " 已开启" or " 已关闭"), 2, s and "Success" or "Info")
        end,
    })
end

farmToggle("Money Farm (救倒地玩家刷 Token)", "EV_MoneyFarm", "Money Farm")
farmToggle("Auto Win Farm (持续救人保队伍)", "EV_AutoWin", "Auto Win Farm")
farmToggle("Ticket Farm (自动拾取票券)", "EV_TicketFarm", "Ticket Farm")
farmToggle("AFK Farm (传送到地图外挂机)", "EV_AFKFarm", "AFK Farm")

FarmTab:AddSection({ Name = "统计" })

local tokenLabel  = FarmTab:AddLabel({ Text = "Tokens: 0" })
local ticketLabel = FarmTab:AddLabel({ Text = "Tickets: 0" })
local aliveLabel  = FarmTab:AddLabel({ Text = "存活: 0s" })

task.spawn(function()
    while not isDestroyed do
        pcall(function()
            local tokens  = LocalPlayer:GetAttribute("Tokens") or LocalPlayer:GetAttribute("Token") or 0
            local tickets = LocalPlayer:GetAttribute("Tickets") or LocalPlayer:GetAttribute("Ticket") or 0
            if tokenLabel then tokenLabel:SetText("Tokens: " .. tostring(tokens)) end
            if ticketLabel then ticketLabel:SetText("Tickets: " .. tostring(tickets)) end
            if aliveLabel then
                aliveLabel:SetText(string.format("存活: %ds", math.floor(tick() - (STATE.startTime or tick()))))
            end
        end)
        task.wait(1)
    end
end)

-- ── TAB 3: 移动 ─────────────────────────────────────────────────
local MoveTab = Window:AddTab({ Name = "移动", Icon = "rbxassetid://6034466796" })

MoveTab:AddSection({ Name = "速度绕过 (Communicator 钩子)" })

MoveTab:AddToggle({
    Name = "Speed Bypass (拦截 Communicator)", Default = false, Flag = "EV_SpeedBypass",
    Callback = function(s)
        SETTINGS.EV_SpeedBypass = s
        if s and not hookInstalled then
            notify("Evade", "本执行器不支持 hookmetamethod，请改用下方 TranslateBy 方案", 5, "Error")
        else
            notify("Evade", s and "Speed Bypass 已开启" or "Speed Bypass 已关闭", 2, s and "Success" or "Info")
        end
    end,
})

MoveTab:AddSlider({
    Name = "Speed 值", Min = 16, Max = 12000, Default = 1450, Increment = 10,
    Flag = "EV_SpeedValue",
    Callback = function(v) SETTINGS.EV_SpeedValue = v end,
})

MoveTab:AddSlider({
    Name = "Jump 值", Min = 1, Max = 100, Default = 3, Increment = 1,
    Flag = "EV_JumpValue",
    Callback = function(v) SETTINGS.EV_JumpValue = v end,
})

MoveTab:AddSection({ Name = "位移加速 (回退方案)" })

MoveTab:AddToggle({
    Name = "TranslateBy 加速 (不需要钩子)", Default = false, Flag = "EV_TranslateSpeed",
    Callback = function(s)
        SETTINGS.EV_TranslateSpeed = s
        toggleTranslateSpeed(s)
    end,
})

MoveTab:AddSlider({
    Name = "TranslateBy 强度", Min = 0.5, Max = 30, Default = 3, Increment = 0.5,
    Flag = "EV_TranslateValue",
    Callback = function(v) SETTINGS.EV_TranslateValue = v end,
})

MoveTab:AddSection({ Name = "身法" })

MoveTab:AddToggle({
    Name = "Auto Bhop (自动连跳)", Default = false, Flag = "EV_Bhop",
    Callback = function(s)
        SETTINGS.EV_Bhop = s
        toggleBhop(s)
    end,
})

MoveTab:AddToggle({
    Name = "Auto Strafe (自动侧滑)", Default = false, Flag = "EV_Strafe",
    Callback = function(s)
        SETTINGS.EV_Strafe = s
        toggleStrafe(s)
    end,
})

MoveTab:AddSlider({
    Name = "Strafe 强度", Min = 0.1, Max = 3, Default = 0.6, Increment = 0.1,
    Flag = "EV_StrafeAmount",
    Callback = function(v) SETTINGS.EV_StrafeAmount = v end,
})

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({
    Name = "InfJump (无限跳)", Default = false, Flag = "EV_InfJump",
    Callback = function(s) SETTINGS.EV_InfJump = s; toggleInfJump(s) end,
})

MoveTab:AddToggle({
    Name = "NoClip (穿墙) [Y]", Default = false, Flag = "EV_NoClip",
    Callback = function(s) SETTINGS.EV_NoClip = s; toggleNoclip(s) end,
})

MoveTab:AddToggle({
    Name = "Fly (飞行 WASD+Space/Ctrl) [U]", Default = false, Flag = "EV_Fly",
    Callback = function(s) SETTINGS.EV_Fly = s; toggleFly(s, SETTINGS.EV_FlySpeed) end,
})

MoveTab:AddSlider({
    Name = "Fly Speed", Min = 10, Max = 400, Default = 80, Increment = 5, Flag = "EV_FlySpeed",
    Callback = function(v)
        SETTINGS.EV_FlySpeed = v
        if SETTINGS.EV_Fly then toggleFly(true, v) end
    end,
})

MoveTab:AddSlider({
    Name = "HipHeight (髋部高度)", Min = -5, Max = 100, Default = 2, Increment = 0.5, Flag = "EV_HipHeight",
    Callback = function(v)
        SETTINGS.EV_HipHeight = v
        local hum = getHum()
        if hum then pcall(function() hum.HipHeight = v end) end
    end,
})

MoveTab:AddSlider({
    Name = "Gravity (全局重力)", Min = 0, Max = 400, Default = 196.2, Increment = 5, Flag = "EV_Gravity",
    Callback = function(v)
        SETTINGS.EV_Gravity = v
        pcall(function() Workspace.Gravity = v end)
    end,
})

-- ── TAB 4: 视觉 ─────────────────────────────────────────────────
local VisualTab = Window:AddTab({ Name = "视觉", Icon = "rbxassetid://6035153470" })

VisualTab:AddSection({ Name = "ESP" })

local function espToggle(name, key, setter)
    VisualTab:AddToggle({
        Name = name, Default = false, Flag = key,
        Callback = function(s)
            setter(s)
            toggleESP(espAnyOn())
        end,
    })
end

espToggle("Nextbot ESP (AI 高亮)", "EV_ESPNextbot", function(s) SETTINGS.ESP_Nextbot = s end)
VisualTab:AddColorPicker({
    Name = "Nextbot 颜色", Default = Color3.fromRGB(255, 50, 50), Flag = "EV_NextbotColor",
    Callback = function(c) SETTINGS.ESP_NextbotColor = c end,
})

espToggle("玩家 ESP", "EV_ESPPlayer", function(s) SETTINGS.ESP_Player = s end)
VisualTab:AddColorPicker({
    Name = "玩家颜色", Default = Color3.fromRGB(255, 170, 0), Flag = "EV_PlayerColor",
    Callback = function(c) SETTINGS.ESP_PlayerColor = c end,
})

espToggle("倒地玩家 ESP", "EV_ESPDowned", function(s) SETTINGS.ESP_Downed = s end)
VisualTab:AddColorPicker({
    Name = "倒地玩家颜色", Default = Color3.fromRGB(255, 0, 0), Flag = "EV_DownedColor",
    Callback = function(c) SETTINGS.ESP_DownedColor = c end,
})

espToggle("票券 ESP", "EV_ESPTicket", function(s) SETTINGS.ESP_Ticket = s end)
VisualTab:AddColorPicker({
    Name = "票券颜色", Default = Color3.fromRGB(41, 180, 255), Flag = "EV_TicketColor",
    Callback = function(c) SETTINGS.ESP_TicketColor = c end,
})

VisualTab:AddToggle({
    Name = "显示实体类型标签", Default = true, Flag = "ESP_Name",
    Callback = function(s) SETTINGS.ESP_Name = s end,
})
VisualTab:AddToggle({
    Name = "显示距离", Default = true, Flag = "ESP_Distance",
    Callback = function(s) SETTINGS.ESP_Distance = s end,
})
VisualTab:AddToggle({
    Name = "Box ESP (方框)", Default = false, Flag = "ESP_Box",
    Callback = function(s) SETTINGS.ESP_Box = s end,
})
VisualTab:AddToggle({
    Name = "Tracers (追踪线)", Default = false, Flag = "ESP_Tracer",
    Callback = function(s) SETTINGS.ESP_Tracer = s; toggleTracer(s) end,
})
VisualTab:AddButton({
    Name = "清除所有 ESP",
    Callback = function()
        clearESP()
        clearTracers()
        notify("Evade", "已清除 ESP", 2, "Success")
    end,
})

VisualTab:AddSection({ Name = "世界" })

VisualTab:AddToggle({
    Name = "XRay (透视墙体)", Default = false, Flag = "EV_XRay",
    Callback = function(s)
        SETTINGS.EV_XRay = s
        toggleXRay(s)
    end,
})
VisualTab:AddToggle({
    Name = "全亮 (Fullbright)", Default = false, Flag = "EV_Fullbright",
    Callback = function(s) SETTINGS.EV_Fullbright = s; toggleFullbright(s) end,
})
VisualTab:AddToggle({
    Name = "去雾 (No Fog)", Default = false, Flag = "EV_NoFog",
    Callback = function(s) SETTINGS.EV_NoFog = s; applyNoFog(s) end,
})
VisualTab:AddToggle({
    Name = "关闭相机抖动", Default = false, Flag = "EV_NoCameraShake",
    Callback = function(s) SETTINGS.EV_NoCameraShake = s; toggleNoCameraShake(s) end,
})

VisualTab:AddSection({ Name = "地图" })

VisualTab:AddButton({
    Name = "移除隐形障碍 (InvisParts)",
    Callback = function() removeBarriers() end,
})
VisualTab:AddButton({
    Name = "移除击杀砖块 (KillBricks)",
    Callback = function() removeKillBricks() end,
})

-- ── TAB 5: 传送 ─────────────────────────────────────────────────
local TpTab = Window:AddTab({ Name = "传送", Icon = "rbxassetid://6035032976" })

TpTab:AddSection({ Name = "传送到玩家" })

TpTab:AddButton({
    Name = "传送到最近玩家",
    Callback = function()
        local myRoot = getRoot()
        if not myRoot then return end
        local best, bestDist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local r = rootOf(p.Character)
                if r then
                    local d = (myRoot.Position - r.Position).Magnitude
                    if d < bestDist then bestDist = d; best = p end
                end
            end
        end
        if best then
            teleportToModel(best.Character, 3)
            notify("Evade", "→ " .. best.Name, 2, "Success")
        else
            notify("Evade", "没有其他玩家", 2, "Warning")
        end
    end,
})

TpTab:AddButton({
    Name = "传送到最近倒地玩家",
    Callback = function()
        local list = getDownedPlayerList()
        if #list == 0 then
            notify("Evade", "当前没有倒地玩家", 2, "Warning")
            return
        end
        teleportToModel(list[1], 3)
        notify("Evade", "已传送到 " .. nameOfModel(list[1]), 2, "Success")
    end,
})

TpTab:AddButton({
    Name = "传送到最近票券",
    Callback = function()
        if not TicketsFolder then
            notify("Evade", "未找到票券容器", 2, "Warning")
            return
        end
        local list = TicketsFolder:GetChildren()
        if #list == 0 then
            notify("Evade", "场上没有票券", 2, "Warning")
            return
        end
        teleportToModel(list[1], 2)
        notify("Evade", "已传送到票券", 2, "Success")
    end,
})

TpTab:AddSection({ Name = "安全点" })

TpTab:AddButton({
    Name = "→ 地图外安全点 (6007, 7005, 8005)",
    Callback = function()
        teleportTo(SAFE_POS)
        notify("Evade", "已传送到安全点", 2, "Success")
    end,
})

TpTab:AddButton({
    Name = "记录当前位置",
    Callback = function()
        local root = getRoot()
        if root then
            STATE.lastPos = root.CFrame
            notify("Evade", "已记录当前位置", 2, "Success")
        end
    end,
})

TpTab:AddButton({
    Name = "返回记录位置",
    Callback = function()
        if STATE.lastPos then
            teleportTo(STATE.lastPos)
            notify("Evade", "已返回记录位置", 2, "Success")
        else
            notify("Evade", "还没有记录位置", 2, "Warning")
        end
    end,
})

TpTab:AddSection({ Name = "切换到其他模式" })

local selectedMode = GAME_MODE_NAMES[1]
TpTab:AddDropdown({
    Name = "游戏模式", Items = GAME_MODE_NAMES, Default = GAME_MODE_NAMES[1], Flag = "EV_GameMode",
    Callback = function(v) selectedMode = v end,
})

TpTab:AddButton({
    Name = "跳转到所选模式",
    Callback = function()
        local id = GAME_MODES[selectedMode]
        if not id then return end
        notify("Evade", "正在跳转到 " .. selectedMode .. " ...", 3, "Info")
        pcall(function() TeleportService:Teleport(id, LocalPlayer) end)
    end,
})

-- ── TAB 6: 杂项 ─────────────────────────────────────────────────
local MiscTab = Window:AddTab({ Name = "杂项", Icon = "rbxassetid://6031280882" })

MiscTab:AddSection({ Name = "道具 / 动作" })

MiscTab:AddToggle({
    Name = "自动喝可乐 (每 6 秒)", Default = false, Flag = "EV_AutoCola",
    Callback = function(s)
        SETTINGS.EV_AutoCola = s
        if s then
            task.spawn(function()
                while not isDestroyed and SETTINGS.EV_AutoCola do
                    useUsable("Cola")
                    task.wait(6)
                end
            end)
        end
    end,
})

MiscTab:AddButton({
    Name = "喝可乐 (Cola) [H]",
    Callback = function()
        local ok = useUsable("Cola")
        notify("Evade", ok and "已使用可乐" or "UseUsable 远程不可用", 2, ok and "Success" or "Error")
    end,
})

MiscTab:AddButton({
    Name = "吹口哨 (Whistle)",
    Callback = function()
        local ok = doWhistle()
        notify("Evade", ok and "已吹口哨" or "Whistle 远程不可用", 2, ok and "Success" or "Error")
    end,
})

MiscTab:AddButton({
    Name = "随机表情 (Emote 1-4)",
    Callback = function()
        if RemoteEmote then
            local n = math.random(1, 4)
            pcall(function() RemoteEmote:FireServer(n) end)
            notify("Evade", "已发送表情 " .. n, 2, "Info")
        else
            notify("Evade", "Emote 远程不可用", 2, "Error")
        end
    end,
})

MiscTab:AddButton({
    Name = "随机投票 (Vote 1-3)",
    Callback = function()
        if RemoteVote then
            local n = math.random(1, 3)
            pcall(function() RemoteVote:FireServer(n) end)
            notify("Evade", "已投票 " .. n, 2, "Info")
        else
            notify("Evade", "Vote 远程不可用", 2, "Error")
        end
    end,
})

MiscTab:AddSection({ Name = "画面设置" })

MiscTab:AddSlider({
    Name = "FOV", Min = 1, Max = 120, Default = 70, Increment = 1, Flag = "EV_FOV",
    Callback = function(v)
        SETTINGS.EV_FOV = v
        local cam = Workspace.CurrentCamera
        if cam then pcall(function() cam.FieldOfView = v end) end
        updateSetting("FieldOfView", v)
    end,
})

MiscTab:AddButton({
    Name = "降画质 (LowQuality · 提帧)",
    Callback = function()
        local ok = updateSetting("LowQuality", true)
        notify("Evade", ok and "已请求降画质" or "UpdateSetting 远程不可用", 2, ok and "Success" or "Error")
    end,
})

MiscTab:AddButton({
    Name = "返回主菜单",
    Callback = function()
        if RemoteReturnToMenu then
            pcall(function() RemoteReturnToMenu:FireServer() end)
        else
            notify("Evade", "ReturnToMenu 远程不可用", 2, "Error")
        end
    end,
})

MiscTab:AddSection({ Name = "服务器" })

MiscTab:AddButton({
    Name = "重新加入 (Rejoin) [B]",
    Callback = function()
        notify("Evade", "正在重新加入...", 2, "Info")
        rejoin()
    end,
})

MiscTab:AddButton({
    Name = "服务器跳转 (Server Hop)",
    Callback = function()
        notify("Evade", "正在跳转服务器...", 2, "Info")
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    end,
})

MiscTab:AddToggle({
    Name = "Anti-AFK (防挂机踢出)", Default = false, Flag = "EV_AntiAFK",
    Callback = function(s)
        SETTINGS.EV_AntiAFK = s
        if s then setupAntiAFK() end
    end,
})

MiscTab:AddSection({ Name = "坐标" })

local coordsLabel = MiscTab:AddLabel({ Text = "X: 0.00   Y: 0.00   Z: 0.00" })
task.spawn(function()
    while not isDestroyed do
        local root = getRoot()
        if root and coordsLabel then
            local p = root.Position
            pcall(function()
                coordsLabel:SetText(string.format("X: %.2f   Y: %.2f   Z: %.2f", p.X, p.Y, p.Z))
            end)
        end
        task.wait(0.1)
    end
end)

MiscTab:AddButton({
    Name = "复制当前坐标",
    Callback = function()
        local root = getRoot()
        if root and setclipboard then
            local p = root.Position
            local s = string.format("CFrame.new(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
            pcall(function() setclipboard(s) end)
            notify("Evade", "已复制: " .. s, 3, "Success")
        end
    end,
})

MiscTab:AddSection({ Name = "脚本" })

MiscTab:AddButton({
    Name = "卸载脚本 (清理全部改动)",
    Callback = function()
        if _G.Evade_Cleanup then _G.Evade_Cleanup() end
    end,
})

MiscTab:AddParagraph({
    Title = "Evade v3.0",
    Content = table.concat({
        "PlaceId: 9872472334",
        "",
        "v3.0 主要修正:",
        "  • 重生改走 Events.Respawn:FireServer()",
        "  • 复活改走 Events.Revive.RevivePlayer(name, bool)",
        "  • 加速改用 Communicator:InvokeServer 钩子 (真绕过)",
        "  • Nextbot 根部件识别为 HRP",
        "  • 倒地判定改用 Downed 属性",
        "",
        "v3.0 新增: Bhop / Strafe / 可乐 / 口哨 / FOV /",
        "  降画质 / Tracer / Box ESP / 模式跳转 / Anti Down",
        "",
        "快捷键: R=重生  H=可乐  Y=NoClip  U=Fly  B=Rejoin  RightShift=UI",
    }, "\n"),
})

-- ══════════════════════════════════════════════════════════════════
-- 16. 快捷键
-- ══════════════════════════════════════════════════════════════════
local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed or isDestroyed then return end
    local key = input.KeyCode

    if key == Enum.KeyCode.R then
        doRespawn()
        notify("R", "重生", 1.5, "Info")
    elseif key == Enum.KeyCode.H then
        useUsable("Cola")
        notify("H", "可乐", 1.5, "Info")
    elseif key == Enum.KeyCode.Y then
        local newState = not SETTINGS.EV_NoClip
        SETTINGS.EV_NoClip = newState
        toggleNoclip(newState)
        notify("Y", newState and "NoClip ON" or "NoClip OFF", 1.5, "Info")
    elseif key == Enum.KeyCode.U then
        local newState = not SETTINGS.EV_Fly
        SETTINGS.EV_Fly = newState
        toggleFly(newState, SETTINGS.EV_FlySpeed)
        notify("U", newState and "Fly ON" or "Fly OFF", 1.5, "Info")
    elseif key == Enum.KeyCode.B then
        notify("B", "正在重新加入...", 1.5, "Info")
        rejoin()
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 17. 角色重生恢复
-- ══════════════════════════════════════════════════════════════════
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if isDestroyed then return end
    STATE.startTime = tick()
    if SETTINGS.EV_NoClip then toggleNoclip(true) end
    if SETTINGS.EV_Fly then toggleFly(true, SETTINGS.EV_FlySpeed) end
    if SETTINGS.EV_InfJump then toggleInfJump(true) end
    if SETTINGS.EV_Bhop then toggleBhop(true) end
    if SETTINGS.EV_Strafe then toggleStrafe(true) end
    if SETTINGS.EV_TranslateSpeed then toggleTranslateSpeed(true) end
    local hum = getHum()
    if hum then
        pcall(function() hum.HipHeight = SETTINGS.EV_HipHeight or 2 end)
    end
    if SETTINGS.EV_FastRevive then applyFastRevive() end
end)

-- ══════════════════════════════════════════════════════════════════
-- 18. 清理
-- ══════════════════════════════════════════════════════════════════
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    local conns = {
        inputConn, charAddedConn, noclipConn, flyConn, speedConn, bhopConn,
        strafeConn, espConn, tracerConn, autoRespawnConn,
        instantReviveConn, autoReviveConn, autoCarryConn, antiDownConn,
        trollConn, infJumpConn,
    }
    for _, c in ipairs(conns) do
        if c then pcall(function() c:Disconnect() end) end
    end

    if flyBV then pcall(function() flyBV:Destroy() end) end
    if flyBG then pcall(function() flyBG:Destroy() end) end

    applyXRay(false)
    clearESP()
    clearTracers()
    toggleFullbright(false)
    applyNoFog(false)

    local hum = getHum()
    if hum then
        pcall(function()
            hum.WalkSpeed = 16
            hum.JumpPower = 50
        end)
    end
    pcall(function() Workspace.Gravity = 196.2 end)

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end
    _G.QuantumUI_Window = nil

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Evade", Text = "脚本已卸载", Duration = 2,
        })
    end)
end

_G.Evade_Cleanup = cleanup

task.wait(0.5)
notify("Evade v3.0", "Evade 辅助已加载\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[Evade] v3.0 (PlaceId: %d) 加载完成", game.PlaceId))
