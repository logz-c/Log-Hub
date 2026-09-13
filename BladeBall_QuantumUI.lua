--[[
    Blade Ball 辅助脚本 v2.0 (Quantum UI 版)

    适配 PlaceId: 13772394625 (Blade Ball / 利刃球)
    Hub 注册的其它实例: 14732610803, 14915220621, 15144787112,
                        15264892126, 15509350986, 16281300371

    ── v2.0 相比 v1.0 的关键变化 ──────────────────────────────────────
    [重写] 远程查找方式。
           v1.0 遍历整个 ReplicatedStorage，把所有名字里带 ball/hit/attack/
           swing/use/dash 的 RemoteEvent 全收集起来，然后「无参数全部 FireServer」。
           这等于往服务器乱扔几十个远程，既不会格挡成功，也极易触发风控。
           实际路径（三份独立公开源码一致）：
             ReplicatedStorage.Remotes.ParryButtonPress   ← 格挡
             ReplicatedStorage.Remotes.AbilityButtonPress ← 技能
           备选名 ParryPress / Parry、AbilityPress / Ability。
           调用形式 :FireServer()，无参数。

    [重写] 球的查找。
           v1.0 每帧多次遍历 workspace 全部后代做名字/形状猜测，性能开销极大。
           实际：球都在 workspace.Balls 里，且真正的那颗带属性 realBall == true
           （或至少有 target 属性）。只遍历这一个文件夹的子项。

    [重写] 格挡判定。
           v1.0 只判断「球距 < 12 studs」，没有速度预测，快速球来不及反应。
           v2.0 用公开源码的相对接近速度模型：
             dirToPlayer  = (charPos - ballPos).Unit
             speedToward  = ballVel:Dot(dirToPlayer) - charVel:Dot(dirToPlayer)
             timeToImpact = (dist - ParryDistance) / speedToward
           当 timeToImpact < 阈值 或 dist <= ParryDistance 时格挡。

    [新增] 格挡冷却读取。
           游戏在 PlayerGui.Hotbar.Block 的 UIGradient.Offset.Y 上暴露格挡冷却
           （< 0.5 表示冷却中）。v2.0 会先查冷却再决定是否按，避免空按。
           技能冷却同理走 Hotbar.Ability。

    [新增] 动态阈值：球越快，留给反应的时间窗口越紧。
    [新增] 球轨迹预测点可视化。
    [新增] 目标指示：判断这颗球是不是在瞄自己。
    [新增] 键盘回退：远程不可用时用 F/Q 键兜底（公开源码做法）。
    [新增] 自动技能 (Raging Deflection / Rapture)、自动 GG、Ping 显示、格挡计数。
    [修复] 去掉 Luau 专有的 continue；Drawing 加可用性检测。
    [修复] Idled 回调里不再 task.wait；销毁时补齐所有连接。
    [修复] 单例守卫补上 _G.BB_Cleanup 调用。

    ── 游戏内部结构 (三份公开源码交叉确认) ────────────────────────────
      workspace.Balls                     球容器 (备选 workspace.Ball)
        └ 有效球: GetAttribute("realBall") == true 或 GetAttribute("target") ~= nil
        └ 正在瞄准你: BrickColor == "Really red"，或角色上出现 Highlight
      workspace.Alive                     存活玩家
      character.Abilities["Raging Deflection" / "Rapture"]   技能节点
      PlayerGui.Hotbar.Block.border1.UIGradient    格挡冷却 (Offset.Y < 0.5 = 冷却中)
      PlayerGui.Hotbar.Ability.border2.UIGradient  技能冷却

      ReplicatedStorage.Remotes.ParryButtonPress:FireServer()
      ReplicatedStorage.Remotes.AbilityButtonPress:FireServer()
      ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
      game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()

    ── 免责 ────────────────────────────────────────────────────────
      仅本地逻辑，不采集信息、不 loadstring 任何外部功能代码
      (UI 库除外，那是显示层)。使用脚本违反 Roblox 服务条款，风险自负。

    快捷键: P=AutoParry  V=NoClip  U=Fly  RightShift=UI
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD
-- ══════════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

local function purgeOld()
    if _G.BB_Cleanup then
        pcall(_G.BB_Cleanup)
        _G.BB_Cleanup = nil
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
            if n:sub(1, 9) == "QuantumUI" or n:sub(1, 7) == "BB_ESP" then
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
    warn("[BladeBall] 在线加载 Quantum UI 失败:", QuantumUI)
    local okLocal, localLib = pcall(function()
        if isfile and isfile("SciFi-UI-Library/source.lua") then
            return loadstring(readfile("SciFi-UI-Library/source.lua"))()
        end
        return nil
    end)
    if not okLocal or type(localLib) ~= "table" then
        warn("[BladeBall] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localLib
end

print("[BladeBall] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

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
local Stats               = game:GetService("Stats")
local Workspace           = workspace

-- 注意: 追踪线用 ScreenGui + Frame 实现, 不依赖 Drawing,
-- 所以下面这个只用来在加载时提示环境能力, 不影响功能。
local hasDrawing = (type(Drawing) == "table" and type(Drawing.new) == "function")

-- ══════════════════════════════════════════════════════════════════
-- 3. 预设颜色 & SETTINGS
-- ══════════════════════════════════════════════════════════════════
local PRESET_COLORS = {
    Color3.fromRGB(255, 80, 160),
    Color3.fromRGB(0, 200, 255),
    Color3.fromRGB(180, 60, 255),
    Color3.fromRGB(0, 255, 120),
    Color3.fromRGB(255, 70, 90),
    Color3.fromRGB(255, 200, 50),
    Color3.fromRGB(255, 105, 180),
    Color3.fromRGB(255, 255, 255),
}

local THEME_PRESETS = {
    ["Pink"]    = Color3.fromRGB(255, 80, 160),
    ["Cyan"]    = Color3.fromRGB(0, 200, 255),
    ["Purple"]  = Color3.fromRGB(180, 60, 255),
    ["Green"]   = Color3.fromRGB(0, 255, 120),
    ["Red"]     = Color3.fromRGB(255, 70, 90),
    ["Gold"]    = Color3.fromRGB(255, 200, 50),
    ["HotPink"] = Color3.fromRGB(255, 105, 180),
}

local SETTINGS = {
    -- 格挡
    BB_AutoParry           = false,
    BB_ParryDistance       = 14,
    BB_PredictionThreshold = 0.12,
    BB_DynamicThreshold    = true,
    BB_CheckCooldown       = true,
    BB_KeyFallback         = true,
    BB_SpamParry           = false,

    -- 技能
    BB_AutoAbility         = false,
    BB_AbilityInterval     = 0.6,
    BB_AbilityCheckCD      = true,

    -- 视觉
    BB_BallESP             = false,
    BB_BallESPColor        = Color3.fromRGB(255, 80, 160),
    BB_BallTracer          = false,
    BB_BallDistance        = true,
    BB_TargetIndicator     = true,
    BB_Trajectory          = false,
    BB_PlayerESP           = false,
    BB_PlayerESPColor      = Color3.fromRGB(0, 200, 255),
    BB_PlayerTracer        = false,
    BB_NightMode           = false,
    BB_FullBright          = false,
    BB_HitboxVis           = false,

    -- 移动
    BB_WalkSpeedEnabled    = false,
    BB_WalkSpeed           = 50,
    BB_JumpPowerEnabled    = false,
    BB_JumpPower           = 100,
    BB_InfJump             = false,
    BB_Noclip              = false,
    BB_Fly                 = false,
    BB_FlySpeed            = 80,

    -- 杂项
    BB_AntiAFK             = false,
    BB_AutoGG              = false,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. RUNTIME HANDLES
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false

local mainConn, noclipConn, infJumpConn, flyConn, idledConn, charAddedConn
local flyBV, flyBG
local espFolder, tracerGui, tracerPool
-- 必须在这里就初始化成空表: pairs(nil) 会直接报错,
-- 而 clearESP() 只在关闭功能时才会把它们置空表。
local ballEspObjects, hitboxBoxes = {}, {}
local trajPart = nil
local savedLighting = {}

local ballsFolder = nil
local parryRemote, abilityRemote = nil, nil

local lastParry, lastAbility = 0, 0
local parryCount = 0
local selectedPlayer = nil
local ggDebounce = false

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
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart
end

local function getGuiParent()
    local ok, res = pcall(function() return CoreGui end)
    if ok and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- ══════════════════════════════════════════════════════════════════
-- 6. 远程获取 (v2.0 精确路径, 不再暴力匹配)
-- ══════════════════════════════════════════════════════════════════
local function getRemotesFolder()
    return ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
end

local function pickRemote(names)
    local folder = getRemotesFolder()
    if not folder then return nil end
    for _, n in ipairs(names) do
        local r = folder:FindFirstChild(n)
        if r and (r:IsA("RemoteEvent") or r:IsA("BindableEvent")) then
            return r
        end
    end
    return nil
end

local function refreshRemotes()
    parryRemote = pickRemote({ "ParryButtonPress", "ParryPress", "Parry" })
    abilityRemote = pickRemote({ "AbilityButtonPress", "AbilityPress", "Ability" })
end
refreshRemotes()

print(string.format("[BladeBall] 远程: Parry=%s Ability=%s",
    parryRemote and parryRemote.Name or "未找到",
    abilityRemote and abilityRemote.Name or "未找到"))

-- ══════════════════════════════════════════════════════════════════
-- 7. 冷却读取 (游戏在 Hotbar 的 UIGradient 上暴露冷却)
-- ══════════════════════════════════════════════════════════════════
local function readGradientOffset(slotName, borderName)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local hotbar = pg and pg:FindFirstChild("Hotbar")
    local slot = hotbar and hotbar:FindFirstChild(slotName)
    local border = slot and slot:FindFirstChild(borderName)
    local grad = border and border:FindFirstChildOfClass("UIGradient")
    if not grad then return nil end
    local ok, y = pcall(function() return grad.Offset.Y end)
    if ok and type(y) == "number" then return y end
    return nil
end

-- 返回 true 表示冷却中
local function parryOnCooldown()
    local y = readGradientOffset("Block", "border1")
    if y == nil then return false end
    return y < 0.5
end

local function abilityOnCooldown()
    local y = readGradientOffset("Ability", "border2")
    if y == nil then return false end
    return y < 0.5
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 球的查找 (v2.0: 只看 workspace.Balls, 用 realBall 属性判定)
-- ══════════════════════════════════════════════════════════════════
local function getBallsFolder()
    if ballsFolder and ballsFolder.Parent then return ballsFolder end
    ballsFolder = Workspace:FindFirstChild("Balls") or Workspace:FindFirstChild("Ball")
    return ballsFolder
end

local function attr(inst, name)
    local ok, v = pcall(function() return inst:GetAttribute(name) end)
    if ok then return v end
    return nil
end

local function isValidBall(b)
    if not b or not b.Parent then return false end
    if not b:IsA("BasePart") then return false end
    if attr(b, "realBall") == true then return true end
    if attr(b, "target") ~= nil then return true end
    return false
end

local function getValidBalls()
    local out = {}
    local folder = getBallsFolder()
    if not folder then return out end
    for _, b in ipairs(folder:GetChildren()) do
        if isValidBall(b) then out[#out + 1] = b end
    end
    return out
end

local function findBestBall()
    local root = getRoot()
    if not root then return nil, math.huge end
    local myPos = root.Position
    local best, bestDist = nil, math.huge
    for _, b in ipairs(getValidBalls()) do
        local d = (b.Position - myPos).Magnitude
        if d < bestDist then
            bestDist = d
            best = b
        end
    end
    return best, bestDist
end

-- 这颗球是不是在瞄我
local function isBallTargetingMe(ball)
    if not ball then return false end
    local tgt = attr(ball, "target")
    if tgt ~= nil then
        if typeof(tgt) == "Instance" then
            if tgt == LocalPlayer or tgt == LocalPlayer.Character then return true end
        elseif type(tgt) == "string" then
            if tgt == LocalPlayer.Name or tgt == LocalPlayer.DisplayName then return true end
        end
    end
    -- 回退: 公开源码用 "Really red" 表示正在瞄你
    local ok, bc = pcall(function() return ball.BrickColor end)
    if ok and bc and tostring(bc) == "Really red" then return true end
    return false
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 格挡 / 技能触发
-- ══════════════════════════════════════════════════════════════════
local function pressKeyFallback(keyCode)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    end)
    task.delay(0.01, function()
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end)
    end)
end

local function fireParry()
    local now = tick()
    if now - lastParry < 0.03 then return false end
    lastParry = now

    if SETTINGS.BB_CheckCooldown and parryOnCooldown() then
        return false
    end

    local ok = false
    if parryRemote then
        ok = pcall(function() parryRemote:FireServer() end)
        if not ok then
            -- 万一它是 BindableEvent
            ok = pcall(function() parryRemote:Fire() end)
        end
    end
    if SETTINGS.BB_KeyFallback then
        pressKeyFallback(Enum.KeyCode.F)
    end
    parryCount = parryCount + 1
    return ok
end

local function fireAbility()
    local now = tick()
    if now - lastAbility < (SETTINGS.BB_AbilityInterval or 0.6) then return false end
    lastAbility = now

    if SETTINGS.BB_AbilityCheckCD and abilityOnCooldown() then
        return false
    end

    local ok = false
    if abilityRemote then
        ok = pcall(function() abilityRemote:FireServer() end)
        if not ok then
            ok = pcall(function() abilityRemote:Fire() end)
        end
    end
    pressKeyFallback(Enum.KeyCode.Q)
    return ok
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 主战斗循环
-- ══════════════════════════════════════════════════════════════════
local function computeTimeToImpact(ball, charPos, charVel)
    local ballPos = ball.Position
    local dist = (ballPos - charPos).Magnitude
    local parryDist = SETTINGS.BB_ParryDistance or 14

    if dist <= parryDist then return 0 end

    local delta = charPos - ballPos
    if delta.Magnitude < 0.01 then return math.huge end
    local dirToPlayer = delta.Unit

    local ballVel = ball.Velocity
    local speedToward = ballVel:Dot(dirToPlayer)
    if charVel then speedToward = speedToward - charVel:Dot(dirToPlayer) end

    if speedToward <= 0 then return math.huge end
    return (dist - parryDist) / speedToward
end

local function combatStep()
    if isDestroyed then return end

    local wantParry = SETTINGS.BB_AutoParry or SETTINGS.BB_SpamParry
    local wantAbility = SETTINGS.BB_AutoAbility
    if not (wantParry or wantAbility) then return end

    local char = LocalPlayer.Character
    local root = getRoot()
    if not char or not root then return end

    local charPos = root.Position
    local charVel = root.Velocity

    local ball = findBestBall()
    if not ball then return end

    if SETTINGS.BB_SpamParry then
        -- 无视距离持续按, 配合冷却检查使用
        fireParry()
    elseif wantParry then
        local dist = (ball.Position - charPos).Magnitude
        local threshold = SETTINGS.BB_PredictionThreshold or 0.12

        local tti = computeTimeToImpact(ball, charPos, charVel)

        -- 动态阈值: 球越快, 留给反应的时间窗口越紧
        if SETTINGS.BB_DynamicThreshold and tti < math.huge then
            local speed = ball.Velocity.Magnitude
            if speed > 60 then
                threshold = math.max(0.05, threshold * (60 / speed))
            end
        end

        local shouldParry = false
        if dist <= (SETTINGS.BB_ParryDistance or 14) then
            shouldParry = true
        elseif tti < threshold then
            shouldParry = true
        end

        if shouldParry then
            fireParry()
        end
    end

    if wantAbility and SETTINGS.BB_AutoAbility then
        -- 只有球确实在瞄自己时才开技能, 避免无意义空放
        if isBallTargetingMe(ball) then
            local dist = (ball.Position - charPos).Magnitude
            local tti = computeTimeToImpact(ball, charPos, charVel)
            if dist <= (SETTINGS.BB_ParryDistance or 14) or tti < 0.25 then
                fireAbility()
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 移动
-- ══════════════════════════════════════════════════════════════════
local function movementStep()
    if isDestroyed then return end
    local hum = getHum()
    if not hum then return end
    if SETTINGS.BB_WalkSpeedEnabled and hum.WalkSpeed ~= SETTINGS.BB_WalkSpeed then
        pcall(function() hum.WalkSpeed = SETTINGS.BB_WalkSpeed end)
    end
    if SETTINGS.BB_JumpPowerEnabled then
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = SETTINGS.BB_JumpPower
        end)
    end
end

local function toggleNoclip(enabled)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if not enabled then
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
        return
    end
    noclipConn = RunService.Stepped:Connect(function()
        if isDestroyed then return end
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
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

    local hum = getHum()
    if not enabled then
        if hum then pcall(function() hum.PlatformStand = false end) end
        return
    end

    local root = getRoot()
    if not root then return end
    if hum then pcall(function() hum.PlatformStand = true end) end

    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "BB_FlyBV"
    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = root

    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "BB_FlyBG"
    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.P = 10000
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root

    flyConn = RunService.RenderStepped:Connect(function()
        if isDestroyed or not flyBV or not flyBV.Parent then return end
        local cam = Workspace.CurrentCamera
        local r = getRoot()
        if not cam or not r then return end
        local dir = Vector3.zero
        local cf = cam.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
        flyBV.Velocity = dir * (speed or SETTINGS.BB_FlySpeed or 80)
        flyBG.CFrame = cam.CFrame
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
    ballEspObjects = {}
    hitboxBoxes = {}
end

local function ensureEspFolder()
    if espFolder and espFolder.Parent then return espFolder end
    espFolder = Instance.new("Folder")
    espFolder.Name = "BB_ESP_Folder"
    espFolder.Parent = getGuiParent()
    return espFolder
end

local function clearMarks(obj)
    pcall(function()
        for _, c in ipairs(obj:GetChildren()) do
            if c.Name == "BB_ESP_HL" or c.Name == "BB_ESP_BB" then
                c:Destroy()
            end
        end
    end)
end

local function makeHighlight(parent, color, name)
    local hl = Instance.new("Highlight")
    hl.Name = name or "BB_ESP_HL"
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0.2
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = parent
    return hl
end

local function makeLabel(parent, text, color, yOffset)
    local bb = Instance.new("BillboardGui")
    bb.Name = "BB_ESP_BB"
    bb.Size = UDim2.new(0, 220, 0, 26)
    bb.StudsOffset = Vector3.new(0, yOffset or 3, 0)
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
    bb.Parent = parent
    return bb
end

-- Tracer 用 ScreenGui + Frame 画线, 不依赖 Drawing
local function getTracerGui()
    if tracerGui and tracerGui.Parent then return tracerGui end
    tracerGui = Instance.new("ScreenGui")
    tracerGui.Name = "BB_TracerGui"
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
    if SETTINGS.BB_BallESP and SETTINGS.BB_BallTracer then
        for _, b in ipairs(getValidBalls()) do
            out[#out + 1] = { pos = b.Position, color = SETTINGS.BB_BallESPColor }
        end
    end
    if SETTINGS.BB_PlayerESP and SETTINGS.BB_PlayerTracer then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local r = p.Character:FindFirstChild("HumanoidRootPart")
                if r then
                    out[#out + 1] = { pos = r.Position, color = SETTINGS.BB_PlayerESPColor }
                end
            end
        end
    end
    return out
end

local function tracerStep()
    if isDestroyed then return end
    if not (SETTINGS.BB_BallTracer or SETTINGS.BB_PlayerTracer) then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local gui = getTracerGui()
    if not gui then return end
    tracerPool = tracerPool or {}

    local origin = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
    local targets = tracerTargets()
    local used = {}

    for i, t in ipairs(targets) do
        local sp, onScreen = cam:WorldToViewportPoint(t.pos)
        if onScreen and sp.Z > 0 then
            local frame = tracerPool[i]
            if not frame or not frame.Parent then
                frame = Instance.new("Frame")
                frame.Name = "BB_Tracer"
                frame.BorderSizePixel = 0
                frame.AnchorPoint = Vector2.new(0, 0.5)
                frame.ZIndex = 2
                frame.Parent = gui
                tracerPool[i] = frame
            end
            frame.BackgroundColor3 = t.color
            local delta = Vector2.new(sp.X, sp.Y) - origin
            frame.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), 1)
            frame.Position = UDim2.fromOffset(origin.X, origin.Y)
            frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            frame.Visible = true
            used[i] = true
        end
    end

    for k, frame in pairs(tracerPool) do
        if not used[k] and frame and frame.Parent then
            pcall(function() frame:Destroy() end)
            tracerPool[k] = nil
        end
    end
end

local function updateBallVisuals()
    ensureEspFolder()

    local root = getRoot()
    local myPos = root and root.Position

    -- 球 ESP
    local seen = {}
    for _, ball in ipairs(getValidBalls()) do
        seen[ball] = true
        clearMarks(ball)
        local targeting = isBallTargetingMe(ball)
        local color = SETTINGS.BB_BallESPColor
        if SETTINGS.BB_TargetIndicator and targeting then
            color = Color3.fromRGB(255, 40, 40)
        end

        if SETTINGS.BB_BallESP then
            pcall(function() makeHighlight(ball, color, "BB_ESP_HL") end)
        end

        if SETTINGS.BB_BallESP and (SETTINGS.BB_BallDistance or SETTINGS.BB_TargetIndicator) then
            local txt = "Ball"
            if SETTINGS.BB_BallDistance and myPos then
                txt = txt .. string.format("  [%dm]", math.floor((ball.Position - myPos).Magnitude))
            end
            if SETTINGS.BB_TargetIndicator and targeting then
                txt = txt .. "  ← 瞄你"
            end
            pcall(function() makeLabel(ball, txt, color, 3) end)
        end
    end

    -- 清理已消失的球
    for ball in pairs(ballEspObjects) do
        if not seen[ball] then ballEspObjects[ball] = nil end
    end

    -- 轨迹预测点
    if SETTINGS.BB_Trajectory then
        local ball = findBestBall()
        if ball and root then
            local tti = computeTimeToImpact(ball, root.Position, root.Velocity)
            if tti < math.huge and tti >= 0 then
                local predicted = ball.Position + ball.Velocity * tti
                if not trajPart or not trajPart.Parent then
                    trajPart = Instance.new("Part")
                    trajPart.Name = "BB_TrajMarker"
                    trajPart.Shape = Enum.PartType.Ball
                    trajPart.Size = Vector3.new(2, 2, 2)
                    trajPart.Anchored = true
                    trajPart.CanCollide = false
                    trajPart.CanQuery = false
                    trajPart.Material = Enum.Material.Neon
                    trajPart.Parent = Workspace
                end
                trajPart.Color = SETTINGS.BB_BallESPColor
                trajPart.Position = predicted
                trajPart.Transparency = 0.35
            else
                if trajPart then pcall(function() trajPart:Destroy() end) trajPart = nil end
            end
        else
            if trajPart then pcall(function() trajPart:Destroy() end) trajPart = nil end
        end
    else
        if trajPart then pcall(function() trajPart:Destroy() end) trajPart = nil end
    end

    -- 玩家 ESP
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local char = p.Character
            local hum = char:FindFirstChildOfClass("Humanoid")
            local alive = hum ~= nil and hum.Health > 0
            if SETTINGS.BB_PlayerESP and alive then
                clearMarks(char)
                pcall(function() makeHighlight(char, SETTINGS.BB_PlayerESPColor, "BB_ESP_HL") end)
                pcall(function() makeLabel(char, p.Name, SETTINGS.BB_PlayerESPColor, 4) end)
            else
                clearMarks(char)
            end
        end
    end
end

local function updateHitboxes()
    if not SETTINGS.BB_HitboxVis then
        for _, box in pairs(hitboxBoxes) do
            pcall(function() box:Destroy() end)
        end
        hitboxBoxes = {}
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                for _, part in ipairs(p.Character:GetDescendants()) do
                    if part:IsA("BasePart") and not hitboxBoxes[part] then
                        local box = Instance.new("SelectionBox")
                        box.Name = "BB_Hitbox"
                        box.Adornee = part
                        box.LineThickness = 0.05
                        box.Color3 = SETTINGS.BB_PlayerESPColor
                        box.Transparency = 0.5
                        box.Parent = CoreGui
                        hitboxBoxes[part] = box
                    end
                end
            end
        end
    end
    for part, box in pairs(hitboxBoxes) do
        if not part or not part.Parent then
            pcall(function() box:Destroy() end)
            hitboxBoxes[part] = nil
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 13. 世界 / 服务器 / 杂项
-- ══════════════════════════════════════════════════════════════════
local function toggleFullbright(enabled)
    if enabled then
        if not savedLighting.saved then
            savedLighting.brightness = Lighting.Brightness
            savedLighting.ambient = Lighting.Ambient
            savedLighting.outdoor = Lighting.OutdoorAmbient
            savedLighting.fogEnd = Lighting.FogEnd
            savedLighting.saved = true
        end
        pcall(function()
            Lighting.Brightness = 3
            Lighting.Ambient = Color3.fromRGB(200, 200, 200)
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
            Lighting.FogEnd = 100000
        end)
    else
        if not savedLighting.saved then return end
        pcall(function()
            Lighting.Brightness = savedLighting.brightness or 1
            Lighting.Ambient = savedLighting.ambient or Color3.fromRGB(128, 128, 128)
            Lighting.OutdoorAmbient = savedLighting.outdoor or Color3.fromRGB(128, 128, 128)
            Lighting.FogEnd = savedLighting.fogEnd or 100000
        end)
    end
end

local nightCache = {}
local function toggleNightMode(enabled)
    if enabled then
        nightCache = {}
        for _, v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") or v:IsA("Sky") or v:IsA("Clouds") then
                nightCache[v] = true
            end
        end
        if not savedLighting.nightSaved then
            savedLighting.clockTime = Lighting.ClockTime
            savedLighting.nightAmbient = Lighting.Ambient
            savedLighting.nightOutdoor = Lighting.OutdoorAmbient
            savedLighting.nightFog = Lighting.FogEnd
            savedLighting.nightSaved = true
        end
        pcall(function()
            Lighting.ClockTime = 0
            Lighting.FogEnd = 1000
            Lighting.Ambient = Color3.fromRGB(20, 20, 40)
            Lighting.OutdoorAmbient = Color3.fromRGB(10, 10, 25)
        end)
        for v in pairs(nightCache) do
            pcall(function() v.Enabled = false end)
        end
    else
        pcall(function()
            Lighting.ClockTime = savedLighting.clockTime or 14
            Lighting.Ambient = savedLighting.nightAmbient or Color3.fromRGB(128, 128, 128)
            Lighting.OutdoorAmbient = savedLighting.nightOutdoor or Color3.fromRGB(128, 128, 128)
            Lighting.FogEnd = savedLighting.nightFog or 100000
        end)
        for v in pairs(nightCache) do
            pcall(function() v.Enabled = true end)
        end
        nightCache = {}
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

local function serverHop()
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
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
    idledConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end

local function sayMessage(msg)
    pcall(function()
        local ev = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        ev = ev and ev:FindFirstChild("SayMessageRequest")
        if ev then ev:FireServer(msg, "All") end
    end)
end

local function getPing()
    local ok, v = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(v) == "number" then return math.floor(v) end
    return nil
end

local function teleportToPlayer(player)
    if not player or not player.Character then return false end
    local tr = player.Character:FindFirstChild("HumanoidRootPart")
    local root = getRoot()
    if not tr or not root then return false end
    local offset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
    return pcall(function() root.CFrame = CFrame.new(tr.Position + offset) end)
end

local function refreshPlayerList()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then out[#out + 1] = p.Name end
    end
    table.sort(out)
    return out
end

-- ══════════════════════════════════════════════════════════════════
-- 14. 构建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title        = "Blade Ball",
    Subtitle     = "利刃球 v2.0",
    ThemeColor   = Color3.fromRGB(255, 80, 160),
    Transparency = 0.3,
    Size         = UDim2.new(0, 660, 0, 600),
    Keybind      = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: 格挡 ─────────────────────────────────────────────────
local ParryTab = Window:AddTab({ Name = "格挡", Icon = "rbxassetid://6034287594" })

ParryTab:AddSection({ Name = "自动格挡" })

ParryTab:AddToggle({
    Name = "Auto Parry (自动格挡)", Default = false, Flag = "BB_AutoParry",
    Callback = function(s)
        SETTINGS.BB_AutoParry = s
        notify("Auto Parry", s and "已开启" or "已关闭", 2, s and "Success" or "Info")
    end,
})

ParryTab:AddToggle({
    Name = "Spam Parry (无视距离持续格挡)", Default = false, Flag = "BB_SpamParry",
    Callback = function(s)
        SETTINGS.BB_SpamParry = s
    end,
})

ParryTab:AddSlider({
    Name = "格挡距离 (进这个距离直接按)", Min = 5, Max = 30, Default = 14, Increment = 1,
    Suffix = " studs", Flag = "BB_ParryDistance",
    Callback = function(v) SETTINGS.BB_ParryDistance = v end,
})

ParryTab:AddSlider({
    Name = "预测阈值 (撞击前多久按)", Min = 0.02, Max = 0.4, Default = 0.12, Increment = 0.01,
    Suffix = "s", Flag = "BB_PredictionThreshold",
    Callback = function(v) SETTINGS.BB_PredictionThreshold = v end,
})

ParryTab:AddToggle({
    Name = "动态阈值 (球越快窗口越紧)", Default = true, Flag = "BB_DynamicThreshold",
    Callback = function(s) SETTINGS.BB_DynamicThreshold = s end,
})

ParryTab:AddToggle({
    Name = "检查格挡冷却 (冷却中不空按)", Default = true, Flag = "BB_CheckCooldown",
    Callback = function(s) SETTINGS.BB_CheckCooldown = s end,
})

ParryTab:AddToggle({
    Name = "键盘回退 (同时模拟 F 键)", Default = true, Flag = "BB_KeyFallback",
    Callback = function(s) SETTINGS.BB_KeyFallback = s end,
})

ParryTab:AddSection({ Name = "自动技能" })

ParryTab:AddToggle({
    Name = "Auto Ability (球瞄你时自动开技能)", Default = false, Flag = "BB_AutoAbility",
    Callback = function(s)
        SETTINGS.BB_AutoAbility = s
        notify("Auto Ability", s and "已开启" or "已关闭", 2, s and "Success" or "Info")
    end,
})

ParryTab:AddToggle({
    Name = "检查技能冷却", Default = true, Flag = "BB_AbilityCheckCD",
    Callback = function(s) SETTINGS.BB_AbilityCheckCD = s end,
})

ParryTab:AddSlider({
    Name = "技能间隔", Min = 0.2, Max = 3, Default = 0.6, Increment = 0.1,
    Suffix = "s", Flag = "BB_AbilityInterval",
    Callback = function(v) SETTINGS.BB_AbilityInterval = v end,
})

ParryTab:AddSection({ Name = "状态" })

local parryCountLabel = ParryTab:AddLabel({ Text = "格挡次数: 0" })
local cooldownLabel   = ParryTab:AddLabel({ Text = "冷却状态: -" })
local pingLabel       = ParryTab:AddLabel({ Text = "Ping: -" })

task.spawn(function()
    while not isDestroyed do
        pcall(function()
            if parryCountLabel then
                parryCountLabel:SetText("格挡次数: " .. tostring(parryCount))
            end
            if cooldownLabel then
                local p = parryOnCooldown()
                local a = abilityOnCooldown()
                cooldownLabel:SetText(string.format("冷却状态: 格挡%s / 技能%s",
                    p and "中" or "就绪", a and "中" or "就绪"))
            end
            if pingLabel then
                local ping = getPing()
                pingLabel:SetText("Ping: " .. (ping and (ping .. " ms") or "-"))
            end
        end)
        task.wait(0.5)
    end
end)

ParryTab:AddButton({
    Name = "立即格挡一次 (测试)",
    Callback = function()
        local ok = fireParry()
        notify("Parry", ok and "已发送格挡" or "远程不可用或冷却中", 2, ok and "Success" or "Warning")
    end,
})

ParryTab:AddButton({
    Name = "立即开技能一次 (测试)",
    Callback = function()
        local ok = fireAbility()
        notify("Ability", ok and "已发送技能" or "远程不可用或冷却中", 2, ok and "Success" or "Warning")
    end,
})

ParryTab:AddButton({
    Name = "重新探测远程路径",
    Callback = function()
        refreshRemotes()
        notify("BladeBall", string.format("Parry=%s Ability=%s",
            parryRemote and parryRemote.Name or "未找到",
            abilityRemote and abilityRemote.Name or "未找到"), 4, "Info")
    end,
})

ParryTab:AddParagraph({
    Title = "格挡判定原理",
    Content = table.concat({
        "公开源码的相对接近速度模型：",
        "  dirToPlayer  = (charPos - ballPos).Unit",
        "  speedToward  = ballVel:Dot(dirToPlayer) - charVel:Dot(dirToPlayer)",
        "  timeToImpact = (dist - 格挡距离) / speedToward",
        "",
        "speedToward <= 0 表示球在远离，直接跳过。",
        "timeToImpact < 阈值 → 按格挡。",
        "另外 dist <= 格挡距离 时无条件按（近距离兜底）。",
        "",
        "v1.0 只判断「距离 < 12」，没有速度预测，",
        "快速球根本来不及反应；而且它是把几十个远程无参乱发，",
        "既不会成功也容易触发风控。",
    }, "\n"),
})

-- ── TAB 2: 视觉 ─────────────────────────────────────────────────
local VisualTab = Window:AddTab({ Name = "视觉", Icon = "rbxassetid://6035153470" })

VisualTab:AddSection({ Name = "球 ESP" })

VisualTab:AddToggle({
    Name = "Ball ESP (球高亮)", Default = false, Flag = "BB_BallESP",
    Callback = function(s) SETTINGS.BB_BallESP = s end,
})
VisualTab:AddColorPicker({
    Name = "球颜色", Default = Color3.fromRGB(255, 80, 160), Presets = PRESET_COLORS, Flag = "BB_BallESPColor",
    Callback = function(c) SETTINGS.BB_BallESPColor = c end,
})
VisualTab:AddToggle({
    Name = "显示球距离", Default = true, Flag = "BB_BallDistance",
    Callback = function(s) SETTINGS.BB_BallDistance = s end,
})
VisualTab:AddToggle({
    Name = "目标指示 (球瞄你时变红 + 标注)", Default = true, Flag = "BB_TargetIndicator",
    Callback = function(s) SETTINGS.BB_TargetIndicator = s end,
})
VisualTab:AddToggle({
    Name = "球追踪线", Default = false, Flag = "BB_BallTracer",
    Callback = function(s) SETTINGS.BB_BallTracer = s end,
})
VisualTab:AddToggle({
    Name = "轨迹预测点 (球将要到达的位置)", Default = false, Flag = "BB_Trajectory",
    Callback = function(s)
        SETTINGS.BB_Trajectory = s
        if not s and trajPart then
            pcall(function() trajPart:Destroy() end)
            trajPart = nil
        end
    end,
})

VisualTab:AddSection({ Name = "玩家 ESP" })

VisualTab:AddToggle({
    Name = "Player ESP (玩家高亮 + 名字)", Default = false, Flag = "BB_PlayerESP",
    Callback = function(s) SETTINGS.BB_PlayerESP = s end,
})
VisualTab:AddColorPicker({
    Name = "玩家颜色", Default = Color3.fromRGB(0, 200, 255), Presets = PRESET_COLORS, Flag = "BB_PlayerESPColor",
    Callback = function(c) SETTINGS.BB_PlayerESPColor = c end,
})
VisualTab:AddToggle({
    Name = "玩家追踪线", Default = false, Flag = "BB_PlayerTracer",
    Callback = function(s) SETTINGS.BB_PlayerTracer = s end,
})
VisualTab:AddToggle({
    Name = "Hitbox 显示", Default = false, Flag = "BB_HitboxVis",
    Callback = function(s) SETTINGS.BB_HitboxVis = s end,
})
VisualTab:AddButton({
    Name = "清除所有 ESP",
    Callback = function()
        clearESP()
        clearTracers()
        if trajPart then
            pcall(function() trajPart:Destroy() end)
            trajPart = nil
        end
        notify("BladeBall", "已清除 ESP", 2, "Success")
    end,
})

VisualTab:AddSection({ Name = "世界" })

VisualTab:AddToggle({
    Name = "全亮 (Fullbright)", Default = false, Flag = "BB_FullBright",
    Callback = function(s) SETTINGS.BB_FullBright = s; toggleFullbright(s) end,
})
VisualTab:AddToggle({
    Name = "夜间模式", Default = false, Flag = "BB_NightMode",
    Callback = function(s) SETTINGS.BB_NightMode = s; toggleNightMode(s) end,
})

-- ── TAB 3: 移动 ─────────────────────────────────────────────────
local MoveTab = Window:AddTab({ Name = "移动", Icon = "rbxassetid://6034466796" })

MoveTab:AddSection({ Name = "基础移动" })

MoveTab:AddToggle({
    Name = "WalkSpeed", Default = false, Flag = "BB_WalkSpeedEnabled",
    Callback = function(s)
        SETTINGS.BB_WalkSpeedEnabled = s
        if not s then
            local hum = getHum()
            if hum then pcall(function() hum.WalkSpeed = 16 end) end
        end
    end,
})
MoveTab:AddSlider({
    Name = "WalkSpeed 值", Min = 16, Max = 300, Default = 50, Increment = 1, Flag = "BB_WalkSpeed",
    Callback = function(v) SETTINGS.BB_WalkSpeed = v end,
})

MoveTab:AddToggle({
    Name = "JumpPower", Default = false, Flag = "BB_JumpPowerEnabled",
    Callback = function(s)
        SETTINGS.BB_JumpPowerEnabled = s
        if not s then
            local hum = getHum()
            if hum then pcall(function() hum.JumpPower = 50 end) end
        end
    end,
})
MoveTab:AddSlider({
    Name = "JumpPower 值", Min = 50, Max = 300, Default = 100, Increment = 5, Flag = "BB_JumpPower",
    Callback = function(v) SETTINGS.BB_JumpPower = v end,
})

MoveTab:AddToggle({
    Name = "InfJump (无限跳)", Default = false, Flag = "BB_InfJump",
    Callback = function(s) SETTINGS.BB_InfJump = s; toggleInfJump(s) end,
})

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({
    Name = "NoClip (穿墙) [V]", Default = false, Flag = "BB_Noclip",
    Callback = function(s) SETTINGS.BB_Noclip = s; toggleNoclip(s) end,
})

MoveTab:AddToggle({
    Name = "Fly (飞行 WASD+Space/Ctrl) [U]", Default = false, Flag = "BB_Fly",
    Callback = function(s) SETTINGS.BB_Fly = s; toggleFly(s, SETTINGS.BB_FlySpeed) end,
})
MoveTab:AddSlider({
    Name = "Fly Speed", Min = 10, Max = 400, Default = 80, Increment = 5, Flag = "BB_FlySpeed",
    Callback = function(v)
        SETTINGS.BB_FlySpeed = v
        if SETTINGS.BB_Fly then toggleFly(true, v) end
    end,
})

-- ── TAB 4: 玩家 / 杂项 ──────────────────────────────────────────
local MiscTab = Window:AddTab({ Name = "杂项", Icon = "rbxassetid://6031280882" })

MiscTab:AddSection({ Name = "玩家操作" })

local playerDropdown = MiscTab:AddDropdown({
    Name = "玩家列表", Items = refreshPlayerList(), Flag = "BB_SelectedPlayer",
    Callback = function(v) selectedPlayer = v end,
})

MiscTab:AddButton({
    Name = "刷新玩家列表",
    Callback = function()
        local items = refreshPlayerList()
        if playerDropdown and playerDropdown.Refresh then
            pcall(function() playerDropdown:Refresh(items) end)
        end
        notify("BladeBall", "共 " .. #items .. " 名其他玩家", 2, "Info")
    end,
})

MiscTab:AddButton({
    Name = "传送到选中玩家",
    Callback = function()
        if not selectedPlayer then
            notify("BladeBall", "请先选择玩家", 2, "Warning")
            return
        end
        local target = Players:FindFirstChild(selectedPlayer)
        if target and teleportToPlayer(target) then
            notify("BladeBall", "已传送到 " .. selectedPlayer, 2, "Success")
        else
            notify("BladeBall", "传送失败", 2, "Error")
        end
    end,
})

MiscTab:AddButton({
    Name = "传送到球附近",
    Callback = function()
        local ball = findBestBall()
        local root = getRoot()
        if ball and root then
            pcall(function() root.CFrame = CFrame.new(ball.Position + Vector3.new(0, 3, 0)) end)
            notify("BladeBall", "已传送到球", 2, "Success")
        else
            notify("BladeBall", "当前没有有效球", 2, "Warning")
        end
    end,
})

MiscTab:AddSection({ Name = "服务器" })

MiscTab:AddButton({
    Name = "重新加入 (Rejoin)",
    Callback = function()
        notify("BladeBall", "正在重新加入...", 2, "Info")
        rejoin()
    end,
})

MiscTab:AddButton({
    Name = "服务器跳转 (Server Hop)",
    Callback = function()
        notify("BladeBall", "正在跳转服务器...", 2, "Info")
        serverHop()
    end,
})

MiscTab:AddToggle({
    Name = "Anti-AFK (防挂机踢出)", Default = false, Flag = "BB_AntiAFK",
    Callback = function(s)
        SETTINGS.BB_AntiAFK = s
        if s then setupAntiAFK() end
    end,
})

MiscTab:AddSection({ Name = "聊天" })

MiscTab:AddToggle({
    Name = "自动 GG (场上只剩你时发 gg)", Default = false, Flag = "BB_AutoGG",
    Callback = function(s)
        SETTINGS.BB_AutoGG = s
        if s then notify("BladeBall", "已开启自动 GG", 2, "Success") end
    end,
})

MiscTab:AddSection({ Name = "UI 外观" })

MiscTab:AddToggle({
    Name = "彩虹边框动画", Default = QuantumUI.RainbowEnabled, Flag = "BB_RainbowBorder",
    Callback = function(state) QuantumUI.RainbowEnabled = state end,
})

MiscTab:AddSlider({
    Name = "彩虹速度", Min = 0.1, Max = 5, Default = QuantumUI.RainbowSpeed or 1, Increment = 0.1,
    Suffix = "x", Flag = "BB_RainbowSpeed",
    Callback = function(v) QuantumUI.RainbowSpeed = v end,
})

MiscTab:AddDropdown({
    Name = "预设主题色", Items = { "Pink", "Cyan", "Purple", "Green", "Red", "Gold", "HotPink" },
    Default = "Pink", Flag = "BB_ThemePreset",
    Callback = function(sel)
        local color = THEME_PRESETS[sel]
        if color then
            Window.ThemeColor = color
            QuantumUI.ThemeColor = color
            Window:RefreshTheme()
            notify("主题", "已切换: " .. sel, 2, "Success")
        end
    end,
})

MiscTab:AddSection({ Name = "脚本" })

MiscTab:AddButton({
    Name = "卸载脚本 (清理全部改动)",
    Callback = function()
        if _G.BB_Cleanup then _G.BB_Cleanup() end
    end,
})

MiscTab:AddParagraph({
    Title = "Blade Ball v2.0",
    Content = table.concat({
        "PlaceId: 13772394625",
        "",
        "v2.0 主要修正:",
        "  • 远程改用精确路径 ParryButtonPress / AbilityButtonPress",
        "  • 球只从 workspace.Balls 取, 用 realBall 属性判定",
        "  • 格挡改用撞击时间预测, 不再是死判距离",
        "  • 新增冷却读取, 冷却中不空按",
        "",
        "v2.0 新增: 动态阈值 / 轨迹预测点 / 目标指示 /",
        "  键盘回退 / 自动技能 / Ping 与格挡计数",
        "",
        "快捷键: P=AutoParry  V=NoClip  U=Fly  RightShift=UI",
    }, "\n"),
})

-- ══════════════════════════════════════════════════════════════════
-- 15. 快捷键
-- ══════════════════════════════════════════════════════════════════
local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed or isDestroyed then return end
    local key = input.KeyCode

    if key == Enum.KeyCode.P then
        local s = not SETTINGS.BB_AutoParry
        SETTINGS.BB_AutoParry = s
        if Window and Window.Flags and Window.Flags["BB_AutoParry"] then
            pcall(function() Window.Flags["BB_AutoParry"]:Set(s) end)
        end
        notify("P", s and "Auto Parry ON" or "Auto Parry OFF", 1.5, "Info")
    elseif key == Enum.KeyCode.V then
        local s = not SETTINGS.BB_Noclip
        SETTINGS.BB_Noclip = s
        toggleNoclip(s)
        if Window and Window.Flags and Window.Flags["BB_Noclip"] then
            pcall(function() Window.Flags["BB_Noclip"]:Set(s) end)
        end
        notify("V", s and "NoClip ON" or "NoClip OFF", 1.5, "Info")
    elseif key == Enum.KeyCode.U then
        local s = not SETTINGS.BB_Fly
        SETTINGS.BB_Fly = s
        toggleFly(s, SETTINGS.BB_FlySpeed)
        notify("U", s and "Fly ON" or "Fly OFF", 1.5, "Info")
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 16. 主循环
-- ══════════════════════════════════════════════════════════════════
charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if isDestroyed then return end
    if SETTINGS.BB_Noclip then toggleNoclip(true) end
    if SETTINGS.BB_InfJump then toggleInfJump(true) end
    if SETTINGS.BB_Fly then toggleFly(true, SETTINGS.BB_FlySpeed) end
end)

-- 自动 GG: 场上只剩自己时发一句
task.spawn(function()
    while not isDestroyed do
        if SETTINGS.BB_AutoGG and not ggDebounce then
            local aliveFolder = Workspace:FindFirstChild("Alive")
            if aliveFolder and #aliveFolder:GetChildren() <= 1 then
                ggDebounce = true
                task.wait(math.random(2, 4))
                sayMessage("gg")
                task.wait(5)
                ggDebounce = false
            end
        end
        task.wait(1)
    end
end)

-- 远程探测保活: 换局后远程实例可能重建
task.spawn(function()
    while not isDestroyed do
        task.wait(5)
        if not (parryRemote and parryRemote.Parent) or not (abilityRemote and abilityRemote.Parent) then
            refreshRemotes()
        end
    end
end)

local lastVisual = 0
mainConn = RunService.RenderStepped:Connect(function()
    if isDestroyed then return end
    pcall(combatStep)
    pcall(movementStep)
    pcall(tracerStep)

    local now = tick()
    if now - lastVisual >= 0.1 then
        lastVisual = now
        pcall(updateBallVisuals)
        pcall(updateHitboxes)
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 17. 清理
-- ══════════════════════════════════════════════════════════════════
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    local conns = {
        inputConn, charAddedConn, mainConn, noclipConn,
        infJumpConn, flyConn, idledConn,
    }
    for _, c in ipairs(conns) do
        if c then pcall(function() c:Disconnect() end) end
    end

    if flyBV then pcall(function() flyBV:Destroy() end) end
    if flyBG then pcall(function() flyBG:Destroy() end) end
    if trajPart then pcall(function() trajPart:Destroy() end) end

    for _, box in pairs(hitboxBoxes) do
        pcall(function() box:Destroy() end)
    end
    hitboxBoxes = {}

    clearESP()
    clearTracers()
    toggleFullbright(false)
    toggleNightMode(false)

    local hum = getHum()
    if hum then
        pcall(function()
            hum.WalkSpeed = 16
            hum.JumpPower = 50
            hum.PlatformStand = false
        end)
    end
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                pcall(function() part.CanCollide = true end)
            end
        end
    end

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end
    _G.QuantumUI_Window = nil

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "BladeBall", Text = "脚本已卸载", Duration = 2,
        })
    end)
end

_G.BB_Cleanup = cleanup

task.wait(0.5)
notify("Blade Ball v2.0", "Blade Ball 辅助已加载\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[BladeBall] v2.0 (PlaceId: %d) 加载完成 | Drawing: %s",
    game.PlaceId, hasDrawing and "可用" or "不可用(不影响功能)"))
