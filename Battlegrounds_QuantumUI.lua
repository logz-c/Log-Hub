--[[
    The Strongest Battlegrounds 辅助脚本 v4.0 (Quantum UI 版)

    适配 PlaceId: 10449761463   GameId: 3808081382

    ── v4.0 相比 v3.0 的关键变化 ──────────────────────────────────────
    [修复] Communicate 远程参数格式错误。
           v3.0 写的是 Com:FireServer({ [1] = { Goal = "LeftClick" } })，
           实际发出的第一个参数是「数组包字典」，服务端读 data.Goal 得到 nil，
           等于所有技能/普攻调用全是空操作。v4.0 统一走 Comm(tbl) ->
           Com:FireServer(tbl)，与 Dark-X-Hub / KykyryzoB 等公开源码一致。

    [新增] 角色切换 (Change Character)  内部名映射 Bald/Hunter/Cyborg/Ninja/
           Batter/Blade/Esper/Purple
    [新增] Auto Parry 自动招架 (检测 HunterFists / M1ing + KeyPress F)
    [新增] Aimbot 自瞄 (可锁 Head/Torso/HumanoidRootPart，带平滑)
    [新增] Auto Skill 1/2/3/4 定键连发
    [新增] Anti-State 反状态 (清除 RagdollSim/Ragdoll/Freeze/Slowed/
           StopRunning/NoJump/NoBlock)
    [新增] Counter 自动脱离 / Counter 打断
    [新增] Auto Safe Zone 低血自动进安全区
    [新增] 目标选择模式 (最近/血最少/击杀最少/随机)
    [新增] ESP 追踪线 (Tracer) 与 XRay 透视
    [新增] 地图传送 (Kamuy / SafePort / 各区域) 与 坐标工具
    [改进] 单例清理覆盖 Tracer/ESP/XRay 残留；角色重生后自动恢复状态

    ── 游戏真实结构 (公开源码交叉确认) ────────────────────────────────
      Character.Communicate:FireServer(data)   技能/操作唯一入口
        data.Goal = "LeftClick" / "LeftClickRelease"        M1 普攻
        data.Goal = "Console Move" + data.Tool             使用技能
        data.Goal = "KeyPress"    + data.Key               按键 (G=终极, F=招架)
        data.Goal = "KeyRelease"  + data.Key               松键
        data.Goal = "Change Character" + data.Character    换角色
      LocalPlayer:GetAttribute("Ultimate")                 终极条 0~100
      workspace.Map.Trash                                  垃圾点 (刷钱)
      Character:FindFirstChild("Counter")                  反琦玉判定部件
      Character:FindFirstChild("HunterFists"/"M1ing")      对手出拳中

    ── 免责 ────────────────────────────────────────────────────────
      仅本地逻辑，不采集信息、不 loadstring 任何外部功能代码
      (UI 库除外，那是显示层)。使用脚本违反 Roblox 服务条款，风险自负。

    快捷键: T=传最近敌人  Y=NoClip  U=Fly  R=Kamuy逃生  G=终极  RightShift=UI
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD
-- ══════════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

local function purgeOld()
    if _G.TSB_Cleanup then
        pcall(_G.TSB_Cleanup)
        _G.TSB_Cleanup = nil
    end
    if _G.QuantumUI_Instance then
        pcall(function() _G.QuantumUI_Instance:Destroy() end)
        _G.QuantumUI_Instance = nil
    end
    if _G.QuantumUI_Window then
        pcall(function() _G.QuantumUI_Window:Destroy() end)
        _G.QuantumUI_Window = nil
    end
    local ok = pcall(function()
        for _, child in ipairs(CoreGui:GetChildren()) do
            local n = child.Name
            if n:sub(1, 9) == "QuantumUI" or n:sub(1, 8) == "TSB_ESP_" or n == "TSB_TracerGui" then
                pcall(function() child:Destroy() end)
            end
        end
    end)
    if not ok then
        -- CoreGui 被保护时退回 PlayerGui
        local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, child in ipairs(pg:GetChildren()) do
                local n = child.Name
                if n:sub(1, 9) == "QuantumUI" or n:sub(1, 8) == "TSB_ESP_" or n == "TSB_TracerGui" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
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
    warn("[TSB] 在线加载 Quantum UI 失败:", QuantumUI)
    local okLocal, localLib = pcall(function()
        if isfile and isfile("SciFi-UI-Library/source.lua") then
            return loadstring(readfile("SciFi-UI-Library/source.lua"))()
        end
        return nil
    end)
    if not okLocal or type(localLib) ~= "table" then
        warn("[TSB] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localLib
end

print("[TSB] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players             = game:GetService("Players")
local LocalPlayer         = Players.LocalPlayer
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local TeleportService     = game:GetService("TeleportService")
local VirtualUser         = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService        = game:GetService("TweenService")
local Lighting            = game:GetService("Lighting")
local Workspace           = workspace

-- ══════════════════════════════════════════════════════════════════
-- 3. SETTINGS
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- 战斗
    TSB_AttackAura      = false,
    TSB_AuraRange       = 6,
    TSB_AutoCombo       = false,
    TSB_AutoUltimate    = false,
    TSB_AutoBlock       = false,
    TSB_AutoParry       = false,
    TSB_ParryRange      = 9,

    -- 技能
    TSB_AutoSkill1      = false,
    TSB_AutoSkill2      = false,
    TSB_AutoSkill3      = false,
    TSB_AutoSkill4      = false,
    TSB_SkillDelay      = 0.35,
    TSB_AutoRandomSkill = false,

    -- 自瞄
    TSB_Aimbot          = false,
    TSB_AimbotPart      = "Head",
    TSB_AimbotRange     = 120,
    TSB_AimbotSmooth    = 0.25,

    -- 农场
    TSB_TrashFarm       = false,
    TSB_TrashDelay      = 0.4,
    TSB_KillFarm        = false,
    TSB_FarmRange       = 300,
    TSB_TargetMode      = "最近",
    TSB_AutoReset       = false,
    TSB_AutoResetHP     = 20,
    TSB_SafeZone        = false,
    TSB_SafeZoneHP      = 25,

    -- 反制
    TSB_CounterDetect   = false,
    TSB_CounterColor    = Color3.fromRGB(255, 60, 60),
    TSB_CounterEscape   = false,
    TSB_CounterBreak    = false,
    TSB_AntiState       = false,

    -- 移动
    TSB_WalkSpeed       = false,
    TSB_WalkSpeedValue  = 35,
    TSB_JumpPower       = false,
    TSB_JumpPowerValue  = 100,
    TSB_HipHeight       = 2,
    TSB_Gravity         = 196.2,
    TSB_InfJump         = false,
    TSB_NoClip          = false,
    TSB_Fly             = false,
    TSB_FlySpeed        = 80,
    TSB_NoStun          = false,
    TSB_NoRagdoll       = false,
    TSB_NoDashCooldown  = false,

    -- 视觉
    ESP_Player          = false,
    ESP_Name            = true,
    ESP_Health          = false,
    ESP_Distance        = true,
    ESP_Tracer          = false,
    ESP_Color           = Color3.fromRGB(0, 200, 255),
    ESP_Refresh         = 0.1,
    TSB_XRay            = false,
    TSB_Fullbright      = false,

    -- 杂项
    TSB_AntiAFK         = false,
}

local genv = (getgenv and getgenv()) or _G
if not genv.__tsb then
    genv.__tsb = { lastPos = nil }
end
local STATE = genv.__tsb

-- ══════════════════════════════════════════════════════════════════
-- 4. RUNTIME HANDLES
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false

local auraConn, comboConn, blockConn, parryConn, aimbotConn
local farmConn, safeConn
local walkConn, jumpConn, infJumpConn, noclipConn, flyConn
local noStunConn, noRagdollConn, noDashConn, espConn, tracerConn
local counterConn, antiStateConn, antiAFKConn
local flyBV, flyBG
local espFolder, tracerGui, tracerPool
local savedLighting = {}
local blockHeld = false

local counterHighlights = {}

-- 用世代号管理 task.spawn 循环：task.spawn 返回 thread 而不是 connection，
-- 不能 :Disconnect()，所以靠世代号让旧循环自然退出，避免重复叠加。
local skillGen, trashGen, xrayGen = 0, 0, 0

-- ══════════════════════════════════════════════════════════════════
-- 5. 基础工具
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
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getCommunicate()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("Communicate")
end

local function isAlive(p)
    if not p or not p.Character then return false end
    local hum = p.Character:FindFirstChildOfClass("Humanoid")
    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
    return hum ~= nil and hrp ~= nil and hum.Health > 0
end

-- ══════════════════════════════════════════════════════════════════
-- 6. Communicate 核心 (v4.0 修复: 直接发字典, 不再包一层数组)
-- ══════════════════════════════════════════════════════════════════
local function Comm(data)
    local com = getCommunicate()
    if not com then return false end
    local ok = pcall(function() com:FireServer(data) end)
    return ok
end

-- M1 普攻
local function M1(release)
    local sent = Comm({ Goal = "LeftClick" })
    if release ~= false and sent then
        task.delay(2, function()
            Comm({ Goal = "LeftClickRelease" })
        end)
    end
    return sent
end

-- 使用技能 (Console Move + Tool)
local function UseAbility(abilityName)
    if not abilityName or abilityName == "" then return false end
    local char = LocalPlayer.Character
    local tool = LocalPlayer.Backpack:FindFirstChild(abilityName)
    if not tool and char then
        tool = char:FindFirstChild(abilityName)
    end
    return Comm({
        Goal = "Console Move",
        Tool = tool,
        ToolName = tostring(abilityName),
    })
end

-- 按键 / 松键
local function KeyPress(key)
    return Comm({ Goal = "KeyPress", Key = key, MoveDirection = Vector3.zero })
end
local function KeyRelease(key)
    return Comm({ Goal = "KeyRelease", Key = key, MoveDirection = Vector3.zero })
end

-- 终极 / 觉醒 (G)
local function ActivateUltimate()
    KeyPress(Enum.KeyCode.G)
    task.delay(0.15, function() KeyRelease(Enum.KeyCode.G) end)
end

-- 换角色
local CHARACTERS = {
    ["Saitama"]        = "Bald",
    ["Garou"]          = "Hunter",
    ["Genos"]          = "Cyborg",
    ["Sonic"]          = "Ninja",
    ["Metal Bat"]      = "Batter",
    ["Atomic Samurai"] = "Blade",
    ["Tatsumaki"]      = "Esper",
    ["Suiryu"]         = "Purple",
}
local CHARACTER_LIST = {
    "Saitama", "Garou", "Genos", "Sonic",
    "Metal Bat", "Atomic Samurai", "Tatsumaki", "Suiryu",
}

local function ChangeCharacter(displayName)
    local internal = CHARACTERS[displayName]
    if not internal then
        notify("TSB", "未知角色: " .. tostring(displayName), 3, "Error")
        return
    end
    -- 已是该角色则跳过 (Backpack 里已有技能工具)
    local backpack = LocalPlayer.Backpack
    if backpack and #backpack:GetChildren() > 0 then
        local hum = getHum()
        if hum then
            pcall(function() hum.Health = 0 end)
        end
    else
        local hum = getHum()
        if hum then
            pcall(function() hum.Health = 0 end)
        end
    end

    -- 等重生
    local deadline = tick() + 10
    repeat
        task.wait(0.1)
        local hum = getHum()
        if hum and hum.Health > 0 then break end
    until tick() > deadline

    task.wait(0.6)
    local ok = Comm({ Goal = "Change Character", Character = internal })
    if ok then
        notify("TSB", "已切换角色: " .. displayName .. " (" .. internal .. ")", 3, "Success")
    else
        notify("TSB", "切换失败：Communicate 不可用", 3, "Error")
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 7. 技能栏扫描
-- ══════════════════════════════════════════════════════════════════
local function GetAllReadyAbilities()
    local result = {}
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local hb = pg and pg:FindFirstChild("Hotbar")
    if not hb then return result end
    local bp = hb:FindFirstChild("Backpack")
    local hotbar = bp and bp:FindFirstChild("Hotbar")
    if not hotbar then return result end
    for _, v in ipairs(hotbar:GetChildren()) do
        if v.ClassName ~= "UIListLayout" and v.Visible then
            local base = v:FindFirstChild("Base")
            if base then
                local toolName = base:FindFirstChild("ToolName")
                local text = toolName and toolName.Text or ""
                if text ~= "" and text ~= "N/A" and not base:FindFirstChild("Cooldown") then
                    table.insert(result, text)
                end
            end
        end
    end
    return result
end

local function RandomAbility()
    local list = GetAllReadyAbilities()
    if #list > 0 then
        return list[math.random(1, #list)]
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 目标选择
-- ══════════════════════════════════════════════════════════════════
local function BestTarget(maxDist, mode)
    local myRoot = getRoot()
    if not myRoot then return nil end
    maxDist = maxDist or math.huge
    mode = mode or SETTINGS.TSB_TargetMode or "最近"

    local best, bestScore = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local dist = (myRoot.Position - hrp.Position).Magnitude
            if dist <= maxDist then
                local score
                if mode == "血最少" then
                    score = hum.Health
                elseif mode == "击杀最少" then
                    score = (p:GetAttribute("Kills") or 0) * 10000 + dist * 0.001
                elseif mode == "随机" then
                    score = math.random() * 1000
                else
                    score = dist
                end
                if score < bestScore then
                    bestScore = score
                    best = p
                end
            end
        end
    end
    return best
end

local function FaceTarget(target)
    if not target or not target.Character then return end
    local tHRP = target.Character:FindFirstChild("HumanoidRootPart")
    local myRoot = getRoot()
    if not tHRP or not myRoot then return end
    local predicted = tHRP.Position + tHRP.Velocity * 0.2
    local delta = predicted - myRoot.Position
    if delta.Magnitude < 0.01 then return end
    pcall(function()
        myRoot.CFrame = CFrame.new(myRoot.Position, myRoot.Position + delta.Unit)
    end)
end

local function TeleportToPlayer(player)
    if not isAlive(player) then return end
    local myRoot = getRoot()
    if not myRoot then return end
    local thrp = player.Character:FindFirstChild("HumanoidRootPart")
    pcall(function() myRoot.CFrame = thrp.CFrame end)
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 战斗功能
-- ══════════════════════════════════════════════════════════════════
local function toggleAttackAura(enabled)
    if auraConn then auraConn:Disconnect() auraConn = nil end
    if not enabled then return end
    auraConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local target = BestTarget(SETTINGS.TSB_AuraRange or 6)
        if not target then return end
        FaceTarget(target)
        local ability = RandomAbility()
        if ability then UseAbility(ability) else M1(true) end
    end)
end

local function toggleAutoCombo(enabled)
    if comboConn then comboConn:Disconnect() comboConn = nil end
    if not enabled then return end
    comboConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local target = BestTarget(SETTINGS.TSB_AuraRange or 6)
        if not target then return end
        FaceTarget(target)
        if SETTINGS.TSB_AutoUltimate then
            local ult = LocalPlayer:GetAttribute("Ultimate") or 0
            if ult >= 100 then ActivateUltimate() end
        end
        local list = GetAllReadyAbilities()
        if #list > 0 then UseAbility(list[1]) else M1(true) end
    end)
end

local function pressBlock(hold)
    if blockHeld == hold then return end
    blockHeld = hold
    pcall(function()
        if hold then
            if keypress then keypress(Enum.KeyCode.F) return end
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        else
            if keyrelease then keyrelease(Enum.KeyCode.F) return end
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end
    end)
end

local function toggleAutoBlock(enabled)
    if blockConn then blockConn:Disconnect() blockConn = nil end
    if not enabled then pressBlock(false) return end
    blockConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then pressBlock(false) return end
        local myRoot = getRoot()
        if not myRoot then pressBlock(false) return end
        local need = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and isAlive(player) then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (myRoot.Position - hrp.Position).Magnitude
                    if dist <= 12 then
                        local dir = (myRoot.Position - hrp.Position)
                        if dir.Magnitude > 0.01 and dir.Unit:Dot(hrp.CFrame.LookVector) > 0.7 then
                            need = true
                            break
                        end
                    end
                end
            end
        end
        pressBlock(need)
    end)
end

-- Auto Parry: 对手出拳 (HunterFists / M1ing) 且在范围内 -> 按 F
local function toggleAutoParry(enabled)
    if parryConn then parryConn:Disconnect() parryConn = nil end
    if not enabled then return end
    parryConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        local myRoot = getRoot()
        if not myRoot then return end
        local range = SETTINGS.TSB_ParryRange or 9
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local char = player.Character
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local attacking = char:FindFirstChild("HunterFists") ~= nil
                        or char:FindFirstChild("M1ing") ~= nil
                    if attacking and (myRoot.Position - hrp.Position).Magnitude <= range then
                        KeyPress(Enum.KeyCode.F)
                        task.wait(0.05)
                        KeyRelease(Enum.KeyCode.F)
                        return
                    end
                end
            end
        end
    end)
end

-- Auto Skill 1/2/3/4
local SKILL_KEYMAP = {
    [1] = Enum.KeyCode.One,
    [2] = Enum.KeyCode.Two,
    [3] = Enum.KeyCode.Three,
    [4] = Enum.KeyCode.Four,
}

local function anySkillEnabled()
    return SETTINGS.TSB_AutoSkill1 or SETTINGS.TSB_AutoSkill2
        or SETTINGS.TSB_AutoSkill3 or SETTINGS.TSB_AutoSkill4
        or SETTINGS.TSB_AutoRandomSkill
end

local function toggleAutoSkill(enabled)
    skillGen = skillGen + 1
    local myGen = skillGen
    if not enabled or not anySkillEnabled() then return end
    task.spawn(function()
        while not isDestroyed and myGen == skillGen and anySkillEnabled() do
            local hum = getHum()
            if hum and hum.Health > 0 then
                if SETTINGS.TSB_AutoRandomSkill then
                    local ability = RandomAbility()
                    if ability then UseAbility(ability) end
                end
                for idx = 1, 4 do
                    if SETTINGS["TSB_AutoSkill" .. idx] then
                        local key = SKILL_KEYMAP[idx]
                        KeyPress(key)
                        task.wait(0.05)
                        KeyRelease(key)
                        task.wait(0.05)
                    end
                end
            end
            task.wait(SETTINGS.TSB_SkillDelay or 0.35)
        end
    end)
end

-- Aimbot: 相机锁定目标
local AIMBOT_BIND = "TSB_Aimbot"

local function aimbotStep()
    if isDestroyed or not SETTINGS.TSB_Aimbot then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local target = BestTarget(SETTINGS.TSB_AimbotRange or 120)
    if not target or not target.Character then return end
    local part = target.Character:FindFirstChild(SETTINGS.TSB_AimbotPart or "Head")
        or target.Character:FindFirstChild("Head")
        or target.Character:FindFirstChild("HumanoidRootPart")
    if not part then return end
    local from = cam.CFrame.Position
    if (part.Position - from).Magnitude < 0.05 then return end
    local goal = CFrame.new(from, part.Position)
    local smooth = tonumber(SETTINGS.TSB_AimbotSmooth) or 0.25
    if smooth >= 1 then
        cam.CFrame = goal
    else
        cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(smooth, 0.02, 1))
    end
end

local function toggleAimbot(enabled)
    pcall(function()
        RunService:UnbindFromRenderStep(AIMBOT_BIND)
    end)
    if aimbotConn then aimbotConn:Disconnect() aimbotConn = nil end
    if not enabled then return end
    local ok = pcall(function()
        RunService:BindToRenderStep(AIMBOT_BIND, Enum.RenderPriority.Camera.Value + 1, aimbotStep)
    end)
    if not ok then
        -- 退回普通 RenderStepped
        aimbotConn = RunService.RenderStepped:Connect(aimbotStep)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 农场功能
-- ══════════════════════════════════════════════════════════════════
local function doTrashPickup()
    local myRoot = getRoot()
    if not myRoot then return end
    local map = Workspace:FindFirstChild("Map")
    local trashFolder = map and map:FindFirstChild("Trash")
    if not trashFolder then return end
    local items = trashFolder:GetChildren()
    if #items == 0 then return end
    local chosen = items[math.random(1, #items)]
    local targetPart
    if chosen:IsA("Model") then
        targetPart = chosen.PrimaryPart or chosen:FindFirstChildWhichIsA("BasePart")
    elseif chosen:IsA("BasePart") then
        targetPart = chosen
    end
    if not targetPart then return end
    local original = myRoot.CFrame
    pcall(function() myRoot.CFrame = targetPart.CFrame + Vector3.new(0, 0, 2.2) end)
    task.wait(0.4)
    M1(false)
    task.wait(SETTINGS.TSB_TrashDelay or 0.4)
    pcall(function() myRoot.CFrame = original end)
end

local function toggleTrashFarm(enabled)
    trashGen = trashGen + 1
    local myGen = trashGen
    if not enabled then return end
    task.spawn(function()
        while not isDestroyed and myGen == trashGen and SETTINGS.TSB_TrashFarm do
            pcall(doTrashPickup)
            task.wait(0.05)
        end
    end)
end

local function toggleKillFarm(enabled)
    if farmConn then farmConn:Disconnect() farmConn = nil end
    if not enabled then return end
    farmConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        local hum = getHum()
        if not hum then return end

        if SETTINGS.TSB_AutoReset and hum.Health > 0 then
            local pct = (hum.Health / hum.MaxHealth) * 100
            if pct <= (SETTINGS.TSB_AutoResetHP or 20) then
                pcall(function() hum.Health = 0 end)
                task.wait(2)
                return
            end
        end

        if SETTINGS.TSB_AutoUltimate then
            local ult = LocalPlayer:GetAttribute("Ultimate") or 0
            if ult >= 100 then ActivateUltimate() end
        end

        local target = BestTarget(SETTINGS.TSB_FarmRange or 300)
        if target then
            TeleportToPlayer(target)
            FaceTarget(target)
            local ability = RandomAbility()
            if ability then UseAbility(ability) else M1(true) end
        end
    end)
end

-- Auto Safe Zone: 低血自动去安全区，血回上来再回来
local SAFE_POS = CFrame.new(-27529, -485, -38183)
local function toggleSafeZone(enabled)
    if safeConn then safeConn:Disconnect() safeConn = nil end
    if not enabled then return end
    local inside = false
    safeConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        local hum = getHum()
        local root = getRoot()
        if not hum or not root then return end
        local pct = (hum.Health / hum.MaxHealth) * 100
        if not inside and pct <= (SETTINGS.TSB_SafeZoneHP or 25) then
            STATE.lastPos = root.CFrame
            pcall(function() root.CFrame = SAFE_POS end)
            inside = true
        elseif inside and pct >= math.min(95, (SETTINGS.TSB_SafeZoneHP or 25) + 40) then
            if STATE.lastPos then
                pcall(function() root.CFrame = STATE.lastPos end)
            end
            inside = false
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 反制功能
-- ══════════════════════════════════════════════════════════════════
local COUNTER_OBJECTS = { "Counter", "HunterCounter", "AtomicCounter" }
local ANTI_STATE_OBJECTS = {
    "RagdollSim", "Ragdoll", "Freeze",
    "Slowed", "StopRunning", "NoJump", "NoBlock",
}

local function hasCounter(char)
    for _, name in ipairs(COUNTER_OBJECTS) do
        if char:FindFirstChild(name) then return true end
    end
    return false
end

-- Counter 检测 + 可选自动脱离 / 打断
local function toggleCounterDetect(enabled)
    if counterConn then counterConn:Disconnect() counterConn = nil end
    for _, hl in pairs(counterHighlights) do
        pcall(function() hl:Destroy() end)
    end
    counterHighlights = {}
    if not enabled then return end

    local breaking = {}

    counterConn = RunService.RenderStepped:Connect(function()
        if isDestroyed then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local char = p.Character
                local detected = hasCounter(char)

                -- 高亮
                local hl = counterHighlights[char]
                if detected then
                    if not hl or not hl.Parent then
                        if hl then pcall(function() hl:Destroy() end) end
                        hl = Instance.new("Highlight")
                        hl.Name = "TSB_Counter_HL"
                        hl.FillColor = SETTINGS.TSB_CounterColor
                        hl.OutlineColor = SETTINGS.TSB_CounterColor
                        hl.FillTransparency = 0.4
                        hl.OutlineTransparency = 0
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Parent = char
                        counterHighlights[char] = hl
                    else
                        hl.FillColor = SETTINGS.TSB_CounterColor
                        hl.OutlineColor = SETTINGS.TSB_CounterColor
                    end

                    -- 自动脱离: 检测到自己正在打的反琦玉目标时瞬移离开
                    if SETTINGS.TSB_CounterEscape then
                        local root = getRoot()
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if root and hrp and (root.Position - hrp.Position).Magnitude <= 14 then
                            pcall(function()
                                root.CFrame = root.CFrame - (hrp.Position - root.Position).Unit * 30
                            end)
                        end
                    end

                    -- 打断: 短暂把对手角色移出 Workspace 让服务端判定落空
                    if SETTINGS.TSB_CounterBreak and not breaking[char] then
                        breaking[char] = true
                        task.spawn(function()
                            pcall(function() char.Parent = game.LogService end)
                            task.wait(0.25)
                            pcall(function()
                                local live = Workspace:FindFirstChild("Live")
                                char.Parent = live or Workspace
                            end)
                            task.wait(0.35)
                            breaking[char] = nil
                        end)
                    end
                else
                    if hl then
                        pcall(function() hl:Destroy() end)
                        counterHighlights[char] = nil
                    end
                end
            end
        end
    end)
end

-- Anti-State: 持续清除布娃娃/冻结/减速等状态对象
local function toggleAntiState(enabled)
    if antiStateConn then antiStateConn:Disconnect() antiStateConn = nil end
    if not enabled then return end
    antiStateConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, name in ipairs(ANTI_STATE_OBJECTS) do
            local obj = char:FindFirstChild(name)
            if obj then
                pcall(function() obj:Destroy() end)
            end
        end
    end)
end

-- 逃生
local KAMUY_POS = CFrame.new(-27529, -485, -38183)

local function escapeTo(cf, seconds, label)
    local root = getRoot()
    if not root then return end
    local original = root.CFrame
    pcall(function() root.CFrame = cf end)
    task.wait(seconds or 2)
    pcall(function() root.CFrame = original end)
    if label then print("[TSB] " .. label .. " done") end
end

local function kamuyEscape()
    escapeTo(KAMUY_POS, 2, "kamuy")
end

-- ══════════════════════════════════════════════════════════════════
-- 12. 移动功能
-- ══════════════════════════════════════════════════════════════════
local function toggleWalkSpeed(enabled)
    if walkConn then walkConn:Disconnect() walkConn = nil end
    if enabled then
        walkConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if hum and hum.Health > 0 then
                pcall(function() hum.WalkSpeed = SETTINGS.TSB_WalkSpeedValue end)
            end
        end)
    else
        local hum = getHum()
        if hum then pcall(function() hum.WalkSpeed = 16 end) end
    end
end

local function toggleJumpPower(enabled)
    if jumpConn then jumpConn:Disconnect() jumpConn = nil end
    if enabled then
        jumpConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if hum and hum.Health > 0 then
                pcall(function()
                    hum.UseJumpPower = true
                    hum.JumpPower = SETTINGS.TSB_JumpPowerValue
                end)
            end
        end)
    else
        local hum = getHum()
        if hum then pcall(function() hum.JumpPower = 50 end) end
    end
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

local function toggleFly(enabled, speed)
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end
    if not enabled then return end

    local root = getRoot()
    if not root then return end

    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "TSB_FlyBV"
    flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = root

    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "TSB_FlyBG"
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
        local spd = speed or SETTINGS.TSB_FlySpeed or 80
        if move.Magnitude > 0 then move = move.Unit * spd end
        flyBV.Velocity = move
        local r = getRoot()
        if r then flyBG.CFrame = CFrame.new(r.Position) * cam.CFrame.Rotation end
    end)
end

local function toggleNoStun(enabled)
    if noStunConn then noStunConn:Disconnect() noStunConn = nil end
    if not enabled then return end
    noStunConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        local hum = getHum()
        if not hum then return end
        pcall(function()
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Stunned then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end)
    end)
end

local function toggleNoRagdoll(enabled)
    if noRagdollConn then noRagdollConn:Disconnect() noRagdollConn = nil end
    if not enabled then return end
    noRagdollConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        local hum = getHum()
        if not hum then return end
        pcall(function()
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Ragdoll
                or st == Enum.HumanoidStateType.FallingDown then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        end)
    end)
end

local function toggleNoDashCooldown(enabled)
    if noDashConn then noDashConn:Disconnect() noDashConn = nil end
    if not enabled then return end
    noDashConn = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        pcall(function()
            local char = LocalPlayer.Character
            if not char then return end
            for _, v in ipairs(char:GetDescendants()) do
                local name = string.lower(v.Name)
                if (v:IsA("NumberValue") or v:IsA("IntValue")) and string.find(name, "dash") then
                    v.Value = 0
                end
                if v:IsA("BoolValue") and string.find(name, "dash") and string.find(name, "cd") then
                    v.Value = false
                end
            end
        end)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 13. ESP / 视觉
-- ══════════════════════════════════════════════════════════════════
local function getGuiParent()
    local ok, res = pcall(function() return CoreGui end)
    if ok and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end
end

local function espEnabled()
    return SETTINGS.ESP_Player or SETTINGS.ESP_Health or SETTINGS.ESP_Distance or SETTINGS.ESP_Name
end

local function runESPLoop()
    if not espFolder or not espFolder.Parent then
        espFolder = Instance.new("Folder")
        espFolder.Name = "TSB_ESP_Folder"
        espFolder.Parent = getGuiParent()
    end

    local myRoot = getRoot()
    local color = SETTINGS.ESP_Color
    local seen = {}

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) then
            local char = p.Character
            seen[char] = true
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")

            local old = char:FindFirstChild("TSB_ESP_HL")
            if old then pcall(function() old:Destroy() end) end
            local oldBB = char:FindFirstChild("TSB_ESP_BB")
            if oldBB then pcall(function() oldBB:Destroy() end) end

            local label = p.Name
            if SETTINGS.ESP_Health then
                label = label .. string.format("  HP:%d", math.floor(hum.Health))
            end
            if SETTINGS.ESP_Distance and myRoot then
                label = label .. string.format("  [%dm]", math.floor((myRoot.Position - hrp.Position).Magnitude))
            end

            pcall(function()
                if SETTINGS.ESP_Player then
                    local hl = Instance.new("Highlight")
                    hl.Name = "TSB_ESP_HL"
                    hl.FillColor = color
                    hl.OutlineColor = color
                    hl.FillTransparency = 0.5
                    hl.OutlineTransparency = 0.2
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Parent = char
                end

                if SETTINGS.ESP_Name or SETTINGS.ESP_Health or SETTINGS.ESP_Distance then
                    local bb = Instance.new("BillboardGui")
                    bb.Name = "TSB_ESP_BB"
                    bb.Size = UDim2.new(0, 220, 0, 26)
                    bb.StudsOffset = Vector3.new(0, 4, 0)
                    bb.AlwaysOnTop = true
                    local tl = Instance.new("TextLabel")
                    tl.Size = UDim2.new(1, 0, 1, 0)
                    tl.BackgroundTransparency = 1
                    tl.Text = label
                    tl.TextColor3 = color
                    tl.TextStrokeTransparency = 0.3
                    tl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                    tl.Font = Enum.Font.GothamBold
                    tl.TextSize = 14
                    tl.Parent = bb
                    bb.Parent = char
                end
            end)
        end
    end

    -- 清理离场玩家
    for _, obj in ipairs(espFolder:GetChildren()) do
        if not seen[obj] then
            pcall(function() obj:Destroy() end)
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
    tracerGui.Name = "TSB_TracerGui"
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

local function tracerStep()
    if isDestroyed or not SETTINGS.ESP_Tracer then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local gui = getTracerGui()
    if not gui then return end
    tracerPool = tracerPool or {}

    local origin = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
    local alive = {}

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isAlive(p) then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
            if onScreen and sp.Z > 0 then
                local frame = tracerPool[p]
                if not frame or not frame.Parent then
                    frame = Instance.new("Frame")
                    frame.Name = "TSB_Tracer"
                    frame.BackgroundColor3 = SETTINGS.ESP_Color
                    frame.BorderSizePixel = 0
                    frame.AnchorPoint = Vector2.new(0, 0.5)
                    frame.ZIndex = 2
                    frame.Parent = gui
                    tracerPool[p] = frame
                end
                frame.BackgroundColor3 = SETTINGS.ESP_Color
                local delta = Vector2.new(sp.X, sp.Y) - origin
                local length = delta.Magnitude
                frame.Size = UDim2.fromOffset(math.max(length, 1), 1)
                frame.Position = UDim2.fromOffset(origin.X, origin.Y)
                frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                frame.Visible = true
                alive[p] = true
            else
                local frame = tracerPool[p]
                if frame then frame.Visible = false end
            end
        end
    end

    for p, frame in pairs(tracerPool) do
        if not alive[p] and frame and frame.Parent then
            pcall(function() frame:Destroy() end)
            tracerPool[p] = nil
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

-- XRay 透视
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
    local ok = pcall(function()
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
    if not ok then
        warn("[TSB] XRay 扫描中断（工作区过大）")
    end
end

local function toggleXRay(enabled)
    xrayGen = xrayGen + 1
    local myGen = xrayGen
    applyXRay(enabled)
    if not enabled then return end
    -- 低频补扫新生成部件
    task.spawn(function()
        while not isDestroyed and myGen == xrayGen and SETTINGS.TSB_XRay do
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

-- 全亮
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

-- ══════════════════════════════════════════════════════════════════
-- 14. 服务器 / 杂项
-- ══════════════════════════════════════════════════════════════════
local function rejoin()
    pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end)
end

local function serverHop()
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end

local function setupAntiAFK()
    if antiAFKConn then antiAFKConn:Disconnect() antiAFKConn = nil end
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
    antiAFKConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 15. 传送点
-- ══════════════════════════════════════════════════════════════════
local TELEPORTS = {
    ["Kamuy 安全点"] = CFrame.new(-27529, -485, -38183),
    ["SafePort"]     = CFrame.new(-775.410583, -145.237183, 137.471039),
    ["中心"] = CFrame.new(147.013214, 440.755981, 2.61009812,
        0.941463232, -2.97720497e-08, 0.337115616,
        3.02179259e-09, 1, 7.98750932e-08,
        -0.337115616, -7.41807753e-08, 0.941463232),
    ["竞技场"] = CFrame.new(-148.684708, 439.510559, -431.699738,
        0.106254414, -3.18543556e-08, 0.994338989,
        -3.15558921e-08, 1, 3.5407755e-08,
        -0.994338989, -3.51394824e-08, 0.106254414),
    ["山丘"] = CFrame.new(-12.057066, 652.52124, -407.857605,
        -0.93605727, 1.72861583e-08, -0.351847649,
        2.38445974e-08, 1, -1.43066181e-08,
        0.351847649, -2.17814797e-08, -0.93605727),
    ["高空"] = CFrame.new(61.6776695, 5631.31055, -176.666,
        -0.890406489, 0.441104233, -0.112264581,
        -3.21421321e-05, 0.246584311, 0.969121337,
        0.455166221, 0.862915516, -0.219546095),
}
local TELEPORT_NAMES = { "Kamuy 安全点", "SafePort", "中心", "竞技场", "山丘", "高空" }

-- ══════════════════════════════════════════════════════════════════
-- 16. 构建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title        = "The Strongest Battlegrounds",
    Subtitle     = "最强战场 v4.0",
    ThemeColor   = Color3.fromRGB(255, 120, 60),
    Transparency = 0.3,
    Size         = UDim2.new(0, 660, 0, 600),
    Keybind      = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

local function safe(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn("[TSB] " .. label .. " 构建失败: " .. tostring(err))
    end
    return ok
end

-- ── TAB 1: 战斗 ─────────────────────────────────────────────────
local CombatTab = Window:AddTab({ Name = "战斗", Icon = "rbxassetid://6034287594" })

CombatTab:AddSection({ Name = "攻击" })

CombatTab:AddToggle({
    Name = "Attack Aura (范围内自动出招)", Default = false, Flag = "TSB_AttackAura",
    Callback = function(s)
        SETTINGS.TSB_AttackAura = s
        toggleAttackAura(s)
        notify("TSB", s and "Attack Aura 已开启" or "Attack Aura 已关闭", 2, s and "Success" or "Info")
    end,
})

CombatTab:AddSlider({
    Name = "Attack Aura 范围", Min = 3, Max = 40, Default = 6, Increment = 1,
    Suffix = " studs", Flag = "TSB_AuraRange",
    Callback = function(v) SETTINGS.TSB_AuraRange = v end,
})

CombatTab:AddToggle({
    Name = "Auto Combo (自动连招)", Default = false, Flag = "TSB_AutoCombo",
    Callback = function(s) SETTINGS.TSB_AutoCombo = s; toggleAutoCombo(s) end,
})

CombatTab:AddToggle({
    Name = "Auto Ultimate (终极条满自动开)", Default = false, Flag = "TSB_AutoUltimate",
    Callback = function(s) SETTINGS.TSB_AutoUltimate = s end,
})

CombatTab:AddSection({ Name = "防御" })

CombatTab:AddToggle({
    Name = "Auto Block (自动格挡 F)", Default = false, Flag = "TSB_AutoBlock",
    Callback = function(s) SETTINGS.TSB_AutoBlock = s; toggleAutoBlock(s) end,
})

CombatTab:AddToggle({
    Name = "Auto Parry (对手出拳自动招架)", Default = false, Flag = "TSB_AutoParry",
    Callback = function(s)
        SETTINGS.TSB_AutoParry = s
        toggleAutoParry(s)
        notify("TSB", s and "Auto Parry 已开启" or "Auto Parry 已关闭", 2, s and "Success" or "Info")
    end,
})

CombatTab:AddSlider({
    Name = "Auto Parry 范围", Min = 4, Max = 25, Default = 9, Increment = 1,
    Suffix = " studs", Flag = "TSB_ParryRange",
    Callback = function(v) SETTINGS.TSB_ParryRange = v end,
})

CombatTab:AddSection({ Name = "自瞄" })

CombatTab:AddToggle({
    Name = "Aimbot (相机锁定目标)", Default = false, Flag = "TSB_Aimbot",
    Callback = function(s) SETTINGS.TSB_Aimbot = s; toggleAimbot(s) end,
})

CombatTab:AddDropdown({
    Name = "自瞄部位", Items = { "Head", "Torso", "UpperTorso", "HumanoidRootPart" },
    Default = "Head", Flag = "TSB_AimbotPart",
    Callback = function(v) SETTINGS.TSB_AimbotPart = v end,
})

CombatTab:AddSlider({
    Name = "自瞄平滑度 (1=瞬锁)", Min = 0.05, Max = 1, Default = 0.25, Increment = 0.05,
    Flag = "TSB_AimbotSmooth",
    Callback = function(v) SETTINGS.TSB_AimbotSmooth = v end,
})

CombatTab:AddSlider({
    Name = "自瞄范围", Min = 20, Max = 500, Default = 120, Increment = 10,
    Suffix = " studs", Flag = "TSB_AimbotRange",
    Callback = function(v) SETTINGS.TSB_AimbotRange = v end,
})

-- ── TAB 2: 技能 ─────────────────────────────────────────────────
local SkillTab = Window:AddTab({ Name = "技能", Icon = "rbxassetid://6034466796" })

SkillTab:AddSection({ Name = "自动技能 (按键 1/2/3/4)" })

for idx = 1, 4 do
    local flag = "TSB_AutoSkill" .. idx
    SkillTab:AddToggle({
        Name = "自动按技能 " .. idx, Default = false, Flag = flag,
        Callback = function(s)
            SETTINGS[flag] = s
            toggleAutoSkill(anySkillEnabled())
        end,
    })
end

SkillTab:AddToggle({
    Name = "随机使用可用技能 (Console Move)", Default = false, Flag = "TSB_AutoRandomSkill",
    Callback = function(s)
        SETTINGS.TSB_AutoRandomSkill = s
        toggleAutoSkill(anySkillEnabled())
    end,
})

SkillTab:AddSlider({
    Name = "技能循环间隔", Min = 0.1, Max = 2, Default = 0.35, Increment = 0.05,
    Suffix = "s", Flag = "TSB_SkillDelay",
    Callback = function(v) SETTINGS.TSB_SkillDelay = v end,
})

SkillTab:AddSection({ Name = "手动" })

SkillTab:AddButton({
    Name = "立即使用随机可用技能",
    Callback = function()
        local ability = RandomAbility()
        if ability then
            UseAbility(ability)
            notify("TSB", "使用技能: " .. ability, 2, "Success")
        else
            notify("TSB", "当前没有可用技能（冷却中或未读到技能栏）", 2, "Warning")
        end
    end,
})

SkillTab:AddButton({
    Name = "立即释放终极 (G)",
    Callback = function()
        ActivateUltimate()
        notify("TSB", "已发送终极键 G", 2, "Info")
    end,
})

SkillTab:AddButton({
    Name = "打印当前可用技能列表",
    Callback = function()
        local list = GetAllReadyAbilities()
        if #list == 0 then
            notify("TSB", "没有读到可用技能", 3, "Warning")
        else
            notify("TSB", table.concat(list, " / "), 5, "Info")
        end
    end,
})

SkillTab:AddParagraph({
    Title = "技能触发原理",
    Content = table.concat({
        "技能走的是 Character.Communicate 远程：",
        "  Goal = 'Console Move' + Tool = 技能工具实例",
        "",
        "技能栏读取自 PlayerGui.Hotbar.Backpack.Hotbar，",
        "只挑「有 ToolName 且没有 Cooldown 子对象」的格子，",
        "所以冷却中的技能不会被误判为可用。",
        "",
        "v4.0 修正了 v3.0 的参数格式问题：之前多包了一层数组，",
        "服务端读不到 Goal 字段，等于所有技能调用都是空操作。",
    }, "\n"),
})

-- ── TAB 3: 农场 ─────────────────────────────────────────────────
local FarmTab = Window:AddTab({ Name = "农场", Icon = "rbxassetid://6031280882" })

FarmTab:AddSection({ Name = "Trash 垃圾农场" })

FarmTab:AddToggle({
    Name = "Trash Farm (传送捡垃圾刷钱)", Default = false, Flag = "TSB_TrashFarm",
    Callback = function(s)
        SETTINGS.TSB_TrashFarm = s
        toggleTrashFarm(s)
        notify("TSB", s and "Trash 农场已开启" or "Trash 农场已关闭", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddSlider({
    Name = "捡取间隔", Min = 0.2, Max = 2, Default = 0.4, Increment = 0.1,
    Suffix = "s", Flag = "TSB_TrashDelay",
    Callback = function(v) SETTINGS.TSB_TrashDelay = v end,
})

FarmTab:AddSection({ Name = "Kill Farm" })

FarmTab:AddToggle({
    Name = "Kill Farm (传送+攻击)", Default = false, Flag = "TSB_KillFarm",
    Callback = function(s)
        SETTINGS.TSB_KillFarm = s
        toggleKillFarm(s)
        notify("TSB", s and "Kill Farm 已开启" or "Kill Farm 已关闭", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddDropdown({
    Name = "目标选择模式", Items = { "最近", "血最少", "击杀最少", "随机" },
    Default = "最近", Flag = "TSB_TargetMode",
    Callback = function(v) SETTINGS.TSB_TargetMode = v end,
})

FarmTab:AddSlider({
    Name = "Kill Farm 范围", Min = 50, Max = 1000, Default = 300, Increment = 25,
    Suffix = " studs", Flag = "TSB_FarmRange",
    Callback = function(v) SETTINGS.TSB_FarmRange = v end,
})

FarmTab:AddSection({ Name = "自动重置 / 安全区" })

FarmTab:AddToggle({
    Name = "Auto Reset (低血量自动重置)", Default = false, Flag = "TSB_AutoReset",
    Callback = function(s) SETTINGS.TSB_AutoReset = s end,
})

FarmTab:AddSlider({
    Name = "重置血量阈值", Min = 5, Max = 80, Default = 20, Increment = 5,
    Suffix = "%", Flag = "TSB_AutoResetHP",
    Callback = function(v) SETTINGS.TSB_AutoResetHP = v end,
})

FarmTab:AddToggle({
    Name = "Auto Safe Zone (低血自动进安全区)", Default = false, Flag = "TSB_SafeZone",
    Callback = function(s)
        SETTINGS.TSB_SafeZone = s
        toggleSafeZone(s)
    end,
})

FarmTab:AddSlider({
    Name = "进安全区血量阈值", Min = 5, Max = 80, Default = 25, Increment = 5,
    Suffix = "%", Flag = "TSB_SafeZoneHP",
    Callback = function(v) SETTINGS.TSB_SafeZoneHP = v end,
})

-- ── TAB 4: 反制 ─────────────────────────────────────────────────
local AntiTab = Window:AddTab({ Name = "反制", Icon = "rbxassetid://6035032976" })

AntiTab:AddSection({ Name = "反琦玉 (Saitama Counter)" })

AntiTab:AddToggle({
    Name = "Counter 检测 (敌方开反琦玉红色高亮)", Default = false, Flag = "TSB_CounterDetect",
    Callback = function(s)
        SETTINGS.TSB_CounterDetect = s
        toggleCounterDetect(s)
    end,
})

AntiTab:AddColorPicker({
    Name = "Counter 高亮颜色", Default = Color3.fromRGB(255, 60, 60), Flag = "TSB_CounterColor",
    Callback = function(c) SETTINGS.TSB_CounterColor = c end,
})

AntiTab:AddToggle({
    Name = "Counter 自动脱离 (贴脸时弹开)", Default = false, Flag = "TSB_CounterEscape",
    Callback = function(s) SETTINGS.TSB_CounterEscape = s end,
})

AntiTab:AddDangerToggle({
    Name = "Counter 打断 (高级 · 短暂移出对手角色)", Default = false, Flag = "TSB_CounterBreak",
    Callback = function(s)
        SETTINGS.TSB_CounterBreak = s
        if s then
            notify("TSB", "已开启 Counter 打断：检测到反琦玉时会把对手角色临时移出工作区", 4, "Warning")
        end
    end,
})

AntiTab:AddSection({ Name = "状态防抗" })

AntiTab:AddToggle({
    Name = "Anti-State (清除布娃娃/冻结/减速等)", Default = false, Flag = "TSB_AntiState",
    Callback = function(s)
        SETTINGS.TSB_AntiState = s
        toggleAntiState(s)
    end,
})

AntiTab:AddParagraph({
    Title = "被清除的状态对象",
    Content = table.concat({
        "RagdollSim / Ragdoll  布娃娃",
        "Freeze                冻结",
        "Slowed                减速",
        "StopRunning           禁止奔跑",
        "NoJump                禁止跳跃",
        "NoBlock               禁止格挡",
        "",
        "检测的 Counter 部件: Counter / HunterCounter / AtomicCounter",
    }, "\n"),
})

AntiTab:AddSection({ Name = "逃生" })

AntiTab:AddButton({
    Name = "Kamuy 逃生 (传送安全点 2 秒后返回) [R]",
    Callback = function() kamuyEscape() end,
})

AntiTab:AddButton({
    Name = "记录当前位置",
    Callback = function()
        local root = getRoot()
        if root then
            STATE.lastPos = root.CFrame
            notify("TSB", "已记录当前位置", 2, "Success")
        end
    end,
})

AntiTab:AddButton({
    Name = "返回记录位置",
    Callback = function()
        local root = getRoot()
        if root and STATE.lastPos then
            pcall(function() root.CFrame = STATE.lastPos end)
            notify("TSB", "已返回记录位置", 2, "Success")
        else
            notify("TSB", "还没有记录位置", 2, "Warning")
        end
    end,
})

-- ── TAB 5: 移动 ─────────────────────────────────────────────────
local MoveTab = Window:AddTab({ Name = "移动", Icon = "rbxassetid://6034466796" })

MoveTab:AddSection({ Name = "基础移动" })

MoveTab:AddToggle({
    Name = "WalkSpeed", Default = false, Flag = "TSB_WalkSpeed",
    Callback = function(s) SETTINGS.TSB_WalkSpeed = s; toggleWalkSpeed(s) end,
})
MoveTab:AddSlider({
    Name = "WalkSpeed 值", Min = 16, Max = 300, Default = 35, Increment = 1, Flag = "TSB_WalkSpeedValue",
    Callback = function(v)
        SETTINGS.TSB_WalkSpeedValue = v
        if SETTINGS.TSB_WalkSpeed then toggleWalkSpeed(true) end
    end,
})

MoveTab:AddToggle({
    Name = "JumpPower", Default = false, Flag = "TSB_JumpPower",
    Callback = function(s) SETTINGS.TSB_JumpPower = s; toggleJumpPower(s) end,
})
MoveTab:AddSlider({
    Name = "JumpPower 值", Min = 50, Max = 300, Default = 100, Increment = 5, Flag = "TSB_JumpPowerValue",
    Callback = function(v)
        SETTINGS.TSB_JumpPowerValue = v
        if SETTINGS.TSB_JumpPower then toggleJumpPower(true) end
    end,
})

MoveTab:AddToggle({
    Name = "InfJump (无限跳)", Default = false, Flag = "TSB_InfJump",
    Callback = function(s) SETTINGS.TSB_InfJump = s; toggleInfJump(s) end,
})

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({
    Name = "NoClip (穿墙) [Y]", Default = false, Flag = "TSB_NoClip",
    Callback = function(s) SETTINGS.TSB_NoClip = s; toggleNoclip(s) end,
})

MoveTab:AddToggle({
    Name = "Fly (飞行 WASD+Space/Ctrl) [U]", Default = false, Flag = "TSB_Fly",
    Callback = function(s) SETTINGS.TSB_Fly = s; toggleFly(s, SETTINGS.TSB_FlySpeed) end,
})
MoveTab:AddSlider({
    Name = "Fly Speed", Min = 10, Max = 400, Default = 80, Increment = 5, Flag = "TSB_FlySpeed",
    Callback = function(v)
        SETTINGS.TSB_FlySpeed = v
        if SETTINGS.TSB_Fly then toggleFly(true, v) end
    end,
})

MoveTab:AddSlider({
    Name = "HipHeight (髋部高度)", Min = 0, Max = 20, Default = 2, Increment = 0.5, Flag = "TSB_HipHeight",
    Callback = function(v)
        SETTINGS.TSB_HipHeight = v
        local hum = getHum()
        if hum then pcall(function() hum.HipHeight = v end) end
    end,
})

MoveTab:AddSlider({
    Name = "Gravity (全局重力)", Min = 0, Max = 400, Default = 196.2, Increment = 5, Flag = "TSB_Gravity",
    Callback = function(v)
        SETTINGS.TSB_Gravity = v
        pcall(function() Workspace.Gravity = v end)
    end,
})

MoveTab:AddSection({ Name = "状态防抗" })

MoveTab:AddToggle({
    Name = "No Stun (防眩晕)", Default = false, Flag = "TSB_NoStun",
    Callback = function(s) SETTINGS.TSB_NoStun = s; toggleNoStun(s) end,
})
MoveTab:AddToggle({
    Name = "No Ragdoll (防布娃娃)", Default = false, Flag = "TSB_NoRagdoll",
    Callback = function(s) SETTINGS.TSB_NoRagdoll = s; toggleNoRagdoll(s) end,
})
MoveTab:AddToggle({
    Name = "No Dash Cooldown (无冲刺冷却)", Default = false, Flag = "TSB_NoDashCooldown",
    Callback = function(s) SETTINGS.TSB_NoDashCooldown = s; toggleNoDashCooldown(s) end,
})

-- ── TAB 6: 视觉 ─────────────────────────────────────────────────
local VisualTab = Window:AddTab({ Name = "视觉", Icon = "rbxassetid://6035153470" })

VisualTab:AddSection({ Name = "ESP" })

VisualTab:AddToggle({
    Name = "玩家 ESP (高亮)", Default = false, Flag = "ESP_Player",
    Callback = function(s) SETTINGS.ESP_Player = s; toggleESP(espEnabled()) end,
})
VisualTab:AddToggle({
    Name = "显示名字", Default = true, Flag = "ESP_Name",
    Callback = function(s) SETTINGS.ESP_Name = s; toggleESP(espEnabled()) end,
})
VisualTab:AddToggle({
    Name = "显示血量", Default = false, Flag = "ESP_Health",
    Callback = function(s) SETTINGS.ESP_Health = s; toggleESP(espEnabled()) end,
})
VisualTab:AddToggle({
    Name = "显示距离", Default = true, Flag = "ESP_Distance",
    Callback = function(s) SETTINGS.ESP_Distance = s; toggleESP(espEnabled()) end,
})
VisualTab:AddToggle({
    Name = "追踪线 (Tracer)", Default = false, Flag = "ESP_Tracer",
    Callback = function(s) SETTINGS.ESP_Tracer = s; toggleTracer(s) end,
})
VisualTab:AddColorPicker({
    Name = "ESP 颜色", Default = Color3.fromRGB(0, 200, 255), Flag = "ESP_Color",
    Callback = function(c) SETTINGS.ESP_Color = c end,
})
VisualTab:AddButton({
    Name = "清除所有 ESP",
    Callback = function()
        clearESP()
        clearTracers()
        notify("TSB", "已清除 ESP", 2, "Success")
    end,
})

VisualTab:AddSection({ Name = "世界" })

VisualTab:AddToggle({
    Name = "XRay (透视墙体)", Default = false, Flag = "TSB_XRay",
    Callback = function(s)
        SETTINGS.TSB_XRay = s
        toggleXRay(s)
        notify("TSB", s and "XRay 已开启" or "XRay 已关闭", 2, "Info")
    end,
})

VisualTab:AddToggle({
    Name = "全亮 (Fullbright)", Default = false, Flag = "TSB_Fullbright",
    Callback = function(s) SETTINGS.TSB_Fullbright = s; toggleFullbright(s) end,
})

-- ── TAB 7: 角色 ─────────────────────────────────────────────────
local CharTab = Window:AddTab({ Name = "角色", Icon = "rbxassetid://6034287594" })

CharTab:AddSection({ Name = "角色切换" })

local selectedCharacter = "Saitama"
CharTab:AddDropdown({
    Name = "选择角色", Items = CHARACTER_LIST, Default = "Saitama", Flag = "TSB_Character",
    Callback = function(v) selectedCharacter = v end,
})

CharTab:AddButton({
    Name = "切换角色 (先重置再发送 Change Character)",
    Callback = function()
        notify("TSB", "正在切换到 " .. selectedCharacter .. " ...", 3, "Info")
        task.spawn(function() ChangeCharacter(selectedCharacter) end)
    end,
})

CharTab:AddParagraph({
    Title = "角色内部名映射",
    Content = table.concat({
        "Saitama        -> Bald",
        "Garou          -> Hunter",
        "Genos          -> Cyborg",
        "Sonic          -> Ninja",
        "Metal Bat      -> Batter",
        "Atomic Samurai -> Blade",
        "Tatsumaki      -> Esper",
        "Suiryu         -> Purple",
        "",
        "流程：先把血量清零触发重生，等角色回来后再发",
        "Goal = 'Change Character' + Character = <内部名>。",
        "直接发而不重生，服务端通常会忽略这次请求。",
    }, "\n"),
})

-- ── TAB 8: 服务器 / 杂项 ────────────────────────────────────────
local MiscTab = Window:AddTab({ Name = "杂项", Icon = "rbxassetid://6031280882" })

MiscTab:AddSection({ Name = "传送" })

MiscTab:AddDropdown({
    Name = "地图传送点", Items = TELEPORT_NAMES, Default = TELEPORT_NAMES[1], Flag = "TSB_Teleport",
    Callback = function() end,
})

MiscTab:AddButton({
    Name = "传送到所选地点",
    Callback = function()
        -- 从下拉读取当前值比较麻烦，这里改用循环按钮更直观，见下方各地点按钮
        notify("TSB", "请使用下方各地点按钮", 2, "Info")
    end,
})

for _, name in ipairs(TELEPORT_NAMES) do
    MiscTab:AddButton({
        Name = "→ " .. name,
        Callback = function()
            local root = getRoot()
            local cf = TELEPORTS[name]
            if root and cf then
                pcall(function() root.CFrame = cf end)
                notify("TSB", "已传送到 " .. name, 2, "Success")
            end
        end,
    })
end

MiscTab:AddSection({ Name = "服务器" })

MiscTab:AddButton({
    Name = "重新加入 (Rejoin)",
    Callback = function()
        notify("TSB", "正在重新加入...", 2, "Info")
        rejoin()
    end,
})
MiscTab:AddButton({
    Name = "服务器跳转 (Server Hop)",
    Callback = function()
        notify("TSB", "正在跳转服务器...", 2, "Info")
        serverHop()
    end,
})

MiscTab:AddSection({ Name = "Anti-AFK" })

MiscTab:AddToggle({
    Name = "Anti-AFK (防挂机踢出)", Default = false, Flag = "TSB_AntiAFK",
    Callback = function(s)
        SETTINGS.TSB_AntiAFK = s
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
            notify("TSB", "已复制: " .. s, 3, "Success")
        end
    end,
})

MiscTab:AddSection({ Name = "脚本" })

MiscTab:AddButton({
    Name = "卸载脚本 (清理全部改动)",
    Callback = function()
        if _G.TSB_Cleanup then _G.TSB_Cleanup() end
    end,
})

MiscTab:AddParagraph({
    Title = "The Strongest Battlegrounds v4.0",
    Content = table.concat({
        "PlaceId: 10449761463   GameId: 3808081382",
        "",
        "v4.0 主要变化:",
        "  • 修复 Communicate 参数格式（v3.0 所有技能调用均为空操作）",
        "  • 新增 角色切换 / Auto Parry / Aimbot / Auto Skill 1-4",
        "  • 新增 Anti-State / Counter 脱离与打断 / Auto Safe Zone",
        "  • 新增 目标选择模式 / 追踪线 / XRay / 地图传送",
        "  • 单例清理覆盖 Tracer / ESP / XRay 残留",
        "",
        "快捷键: T=传最近敌人  Y=NoClip  U=Fly  R=Kamuy逃生  RightShift=UI",
    }, "\n"),
})

-- ══════════════════════════════════════════════════════════════════
-- 17. 快捷键
-- ══════════════════════════════════════════════════════════════════
local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed or isDestroyed then return end
    local key = input.KeyCode

    if key == Enum.KeyCode.T then
        local target = BestTarget(300)
        if target then
            TeleportToPlayer(target)
            notify("T", "→ " .. (target.DisplayName or target.Name), 1.5, "Info")
        end
    elseif key == Enum.KeyCode.Y then
        local newState = not SETTINGS.TSB_NoClip
        SETTINGS.TSB_NoClip = newState
        toggleNoclip(newState)
        notify("Y", newState and "NoClip ON" or "NoClip OFF", 1.5, "Info")
    elseif key == Enum.KeyCode.U then
        local newState = not SETTINGS.TSB_Fly
        SETTINGS.TSB_Fly = newState
        toggleFly(newState, SETTINGS.TSB_FlySpeed)
        notify("U", newState and "Fly ON" or "Fly OFF", 1.5, "Info")
    elseif key == Enum.KeyCode.R then
        kamuyEscape()
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 18. 角色重生恢复
-- ══════════════════════════════════════════════════════════════════
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if isDestroyed then return end
    if SETTINGS.TSB_WalkSpeed then toggleWalkSpeed(true) end
    if SETTINGS.TSB_JumpPower then toggleJumpPower(true) end
    if SETTINGS.TSB_NoClip then toggleNoclip(true) end
    if SETTINGS.TSB_Fly then toggleFly(true, SETTINGS.TSB_FlySpeed) end
    if SETTINGS.TSB_NoRagdoll then toggleNoRagdoll(true) end
    if SETTINGS.TSB_NoStun then toggleNoStun(true) end
    if SETTINGS.TSB_AntiState then toggleAntiState(true) end
    local hum = getHum()
    if hum then
        pcall(function()
            hum.HipHeight = SETTINGS.TSB_HipHeight or 2
        end)
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 19. 清理
-- ══════════════════════════════════════════════════════════════════
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    local conns = {
        inputConn, charAddedConn, auraConn, comboConn, blockConn, parryConn,
        aimbotConn, farmConn, safeConn, walkConn, jumpConn,
        infJumpConn, noclipConn, flyConn, noStunConn, noRagdollConn,
        noDashConn, espConn, tracerConn, counterConn, antiStateConn,
        antiAFKConn,
    }
    for _, c in ipairs(conns) do
        if c then pcall(function() c:Disconnect() end) end
    end

    pcall(function() RunService:UnbindFromRenderStep(AIMBOT_BIND) end)

    pressBlock(false)
    if flyBV then pcall(function() flyBV:Destroy() end) end
    if flyBG then pcall(function() flyBG:Destroy() end) end

    applyXRay(false)
    clearESP()
    clearTracers()

    for _, hl in pairs(counterHighlights) do
        pcall(function() hl:Destroy() end)
    end
    counterHighlights = {}

    toggleFullbright(false)

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
            Title = "TSB", Text = "脚本已卸载", Duration = 2,
        })
    end)
end

_G.TSB_Cleanup = cleanup

task.wait(0.5)
notify("TSB v4.0", "The Strongest Battlegrounds 辅助已加载\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[TSB] v4.0 (PlaceId: %d) 加载完成", game.PlaceId))
