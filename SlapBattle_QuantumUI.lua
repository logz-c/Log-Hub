--[[
    Slap Battle 辅助脚本 (Quantum UI 版)  v1.0

    适配 PlaceId: 6403373529 (Slap Battles / 打耳光大战)
    Hub 注册的其它实例: 同作者其它小游戏地图

    ── 真实远程 (游戏内实测存在) ──────────────────────────────────────
      ReplicatedStorage.GeneralHit      ← 主拍击远程  :FireServer(part)
      ReplicatedStorage.GeneralAbility  ← 手套技能    :FireServer(...)
      ReplicatedStorage.SelfKnockback   ← 自身击退
      ReplicatedStorage.Counter         ← 反击
      ReplicatedStorage.b               ← 老版本远程 (仍保留, 作为回退)
      调用签名取自公开 SlapAura 源码:  hitRemote:FireServer(targetPart)
      (targetPart 取受害者角色里的某个 BasePart, 优先 HumanoidRootPart)

    ── 游戏内部结构 (实测) ───────────────────────────────────────────
      workspace.DEATHBARRIER            ← 掉下去即死 (地图边缘虚空)
      character 里的手套 = Tool.<手套名>, 内含 Glove 部件
      LocalPlayer.Backpack 里是当前手套 Tool

    ── 本脚本功能 ───────────────────────────────────────────────────
      战斗: Slap Aura(范围拍所有人) / Auto Slap(只拍最近) / 拍击范围 /
            拍击间隔 / 一键拍最近(E) / 拍所有人(按钮) / 手套技能(T)
      生存: Anti-Void(掉虚空自动拉回) / 防击飞(实验) / 自动重新装备手套
      玩家: ESP(头顶名牌) / 移速 / 跳跃 / 无限跳 / 穿墙 / 飞行
      杂项: 防挂机 / 主题 / 彩虹边框 / 卸载

    ── 免责 ────────────────────────────────────────────────────────
      仅本地逻辑, 不采集信息、不 loadstring 任何外部功能代码
      (UI 库除外, 那是显示层)。使用脚本违反 Roblox 服务条款, 风险自负。

    快捷键: E=拍最近  T=放技能  RightShift=UI
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD
-- ══════════════════════════════════════════════════════════════════
local CoreGui = game:GetService("CoreGui")

local function purgeOld()
    if _G.SB_Cleanup then
        pcall(_G.SB_Cleanup)
        _G.SB_Cleanup = nil
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
            if n:sub(1, 9) == "QuantumUI" or n:sub(1, 7) == "SB_ESP" then
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
    warn("[SlapBattle] 在线加载 Quantum UI 失败:", QuantumUI)
    local okLocal, localLib = pcall(function()
        if isfile and isfile("SciFi-UI-Library/source.lua") then
            return loadstring(readfile("SciFi-UI-Library/source.lua"))()
        end
        return nil
    end)
    if not okLocal or type(localLib) ~= "table" then
        warn("[SlapBattle] 无法加载 UI 库, 脚本终止")
        return
    end
    QuantumUI = localLib
end

print("[SlapBattle] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

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
local TeleportService     = game:GetService("TeleportService")
local Workspace           = workspace

local hasDrawing = (type(Drawing) == "table" and type(Drawing.new) == "function")

-- ══════════════════════════════════════════════════════════════════
-- 3. SETTINGS
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- 战斗
    SB_SlapAura      = false,
    SB_AutoSlap      = false,
    SB_SlapReach     = 30,
    SB_SlapInterval  = 0.1,
    SB_SlapOnClick   = false,

    -- 生存
    SB_AntiVoid      = false,
    SB_SafeY         = -20,
    SB_AntiKnockback = false,
    SB_AutoReGlove   = false,

    -- 玩家
    SB_ESP           = false,
    SB_ESPColor      = Color3.fromRGB(255, 80, 160),
    SB_WalkSpeedEnabled = false,
    SB_WalkSpeed     = 50,
    SB_JumpPowerEnabled = false,
    SB_JumpPower     = 100,
    SB_InfJump       = false,
    SB_Noclip        = false,
    SB_Fly           = false,
    SB_FlySpeed      = 80,

    -- 杂项
    SB_AntiAFK       = false,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. RUNTIME HANDLES
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false

local mainConn, noclipConn, infJumpConn, flyConn, idledConn,
      charAddedConn, espConn, voidConn, knockConn, inputConn
local flyBV, flyBG
local espFolder, espObjects = nil, {}
local lastSafeCFrame = nil

local hitRemote, abilityRemote = nil, nil
local lastSlap = 0
local slapCount = 0
local selectedPlayer = nil

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
-- 6. 远程获取
--    GeneralHit 是主拍击远程; 回退到老远程 b; 再回退到动态扫描
--    手套 LocalScript 常量 (14ms-alt SlapAura 的做法)。
--    签名: hitRemote:FireServer(targetPart)
-- ══════════════════════════════════════════════════════════════════
local function findHitRemoteStatic()
    local candidates = { "GeneralHit", "b", "Hit", "Slap" }
    for _, n in ipairs(candidates) do
        local r = ReplicatedStorage:FindFirstChild(n)
        if r and r:IsA("RemoteEvent") then
            return r
        end
    end
    return nil
end

-- 动态: 扫当前装备手套的 LocalScript 常量, 匹配 ReplicatedStorage 里的 RemoteEvent
local function findHitRemoteDynamic()
    local gc = getgc
    if type(gc) ~= "function" then return nil end
    local tool = nil
    local char = LocalPlayer.Character
    if char then tool = char:FindFirstChildOfClass("Tool") end
    if not tool then
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if bp then tool = bp:FindFirstChildOfClass("Tool") end
    end
    if not tool then return nil end
    local scr = tool:FindFirstChildOfClass("LocalScript")
    if not scr then return nil end

    local constants = {}
    local ok = pcall(function()
        for _, f in pairs(gc()) do
            if type(f) == "function" then
                local env = getfenv and getfenv(f)
                if env and env.script == scr then
                    local c = debug.getconstants and debug.getconstants(f)
                    if c then
                        for _, v in ipairs(c) do
                            if type(v) == "string" then
                                constants[#constants + 1] = v
                            end
                        end
                    end
                end
            end
        end
    end)
    if not ok then return nil end

    for _, name in ipairs(constants) do
        local r = ReplicatedStorage:FindFirstChild(name)
        if r and r:IsA("RemoteEvent") then
            return r
        end
    end
    return nil
end

local function refreshRemotes()
    hitRemote = findHitRemoteStatic()
    if not hitRemote then
        hitRemote = findHitRemoteDynamic()
    end
    local a = ReplicatedStorage:FindFirstChild("GeneralAbility")
    abilityRemote = (a and a:IsA("RemoteEvent")) and a or nil
end
refreshRemotes()

print(string.format("[SlapBattle] 远程: Hit=%s Ability=%s",
    hitRemote and hitRemote.Name or "未找到",
    abilityRemote and abilityRemote.Name or "未找到"))

-- ══════════════════════════════════════════════════════════════════
-- 7. 拍击逻辑
-- ══════════════════════════════════════════════════════════════════
local function getPartOf(targetChar)
    if not targetChar then return nil end
    local root = targetChar:FindFirstChild("HumanoidRootPart")
    if root then return root end
    return targetChar:FindFirstChildWhichIsA("BasePart")
end

local function fireSlap(targetChar)
    if not hitRemote or not targetChar or isDestroyed then return false end
    local part = getPartOf(targetChar)
    if not part then return false end
    -- 签名: :FireServer(part)  —— 仅一个参数, 受害者身上的 BasePart
    local ok = pcall(function() hitRemote:FireServer(part) end)
    if ok then
        slapCount = slapCount + 1
    end
    return ok
end

local function slapAllInRange()
    local root = getRoot()
    if not root then return end
    local reach = SETTINGS.SB_SlapReach or 30
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local part = getPartOf(p.Character)
            if part and root and (part.Position - root.Position).Magnitude <= reach then
                fireSlap(p.Character)
            end
        end
    end
end

local function slapNearest()
    local root = getRoot()
    if not root then return false end
    local reach = SETTINGS.SB_SlapReach or 30
    local best, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local part = getPartOf(p.Character)
            if part then
                local d = (part.Position - root.Position).Magnitude
                if d < bestDist and d <= reach then
                    bestDist = d
                    best = p.Character
                end
            end
        end
    end
    if best then
        return fireSlap(best)
    end
    return false
end

local function combatStep()
    if isDestroyed then return end
    if not (SETTINGS.SB_SlapAura or SETTINGS.SB_AutoSlap) then return end
    local now = tick()
    if now - lastSlap < (SETTINGS.SB_SlapInterval or 0.1) then return end
    lastSlap = now

    if SETTINGS.SB_SlapAura then
        slapAllInRange()
    elseif SETTINGS.SB_AutoSlap then
        slapNearest()
    end
end

local function fireAbility()
    if not abilityRemote then
        -- 回退: 有些手套技能也走 GeneralHit 同族, 这里只尝试 GeneralAbility
        return false
    end
    local ok = pcall(function() abilityRemote:FireServer() end)
    if not ok then
        ok = pcall(function() abilityRemote:Fire() end)
    end
    return ok
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 移动 (与 BladeBall 同款, 游戏无关)
-- ══════════════════════════════════════════════════════════════════
local function movementStep()
    if isDestroyed then return end
    local hum = getHum()
    if not hum then return end
    if SETTINGS.SB_WalkSpeedEnabled and hum.WalkSpeed ~= SETTINGS.SB_WalkSpeed then
        pcall(function() hum.WalkSpeed = SETTINGS.SB_WalkSpeed end)
    end
    if SETTINGS.SB_JumpPowerEnabled then
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = SETTINGS.SB_JumpPower
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
    flyBV.Name = "SB_FlyBV"
    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = root

    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "SB_FlyBG"
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
        flyBV.Velocity = dir * (speed or SETTINGS.SB_FlySpeed or 80)
        flyBG.CFrame = cam.CFrame
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 生存: Anti-Void / 防击飞 / 自动重装手套
-- ══════════════════════════════════════════════════════════════════
local function survivalStep()
    if isDestroyed then return end
    local root = getRoot()
    local hum = getHum()
    if not root then return end

    -- 记录安全位置 (站在地面/岛上时)
    if hum and hum.Health > 0 and root.Position.Y > (SETTINGS.SB_SafeY or -20) + 5 then
        lastSafeCFrame = root.CFrame
    end

    -- Anti-Void: 掉到安全线以下, 拉回最后的安全点
    if SETTINGS.SB_AntiVoid and lastSafeCFrame then
        if root.Position.Y < (SETTINGS.SB_SafeY or -20) then
            pcall(function() root.CFrame = lastSafeCFrame end)
        end
    end

    -- 自动重装手套: 角色没有 Tool 但背包有, 装备上
    if SETTINGS.SB_AutoReGlove and hum then
        local char = LocalPlayer.Character
        if char and not char:FindFirstChildOfClass("Tool") then
            local bp = LocalPlayer:FindFirstChild("Backpack")
            if bp then
                local t = bp:FindFirstChildOfClass("Tool")
                if t then
                    pcall(function() hum:EquipTool(t) end)
                end
            end
        end
    end
end

local function toggleAntiKnockback(enabled)
    if knockConn then knockConn:Disconnect() knockConn = nil end
    if not enabled then return end
    -- 被击飞时 root 速度会瞬间很大; 检测到就归零 (飞行时不生效)
    knockConn = RunService.Stepped:Connect(function()
        if isDestroyed or SETTINGS.SB_Fly then return end
        local root = getRoot()
        if not root then return end
        if root.Velocity.Magnitude > 55 then
            pcall(function() root.Velocity = Vector3.zero end)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 10. ESP (BillboardGui 头顶名牌, 无需 Drawing)
-- ══════════════════════════════════════════════════════════════════
local function ensureEspFolder()
    if espFolder and espFolder.Parent then return espFolder end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local sg = pg:FindFirstChild("SB_ESP")
    if not sg then
        sg = Instance.new("ScreenGui")
        sg.Name = "SB_ESP"
        sg.ResetOnSpawn = false
        sg.Parent = pg
    end
    espFolder = sg
    return espFolder
end

local function makeEsp(player)
    local folder = ensureEspFolder()
    if not folder then return end
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not root then return end

    local bg = Instance.new("BillboardGui")
    bg.Name = "ESP_" .. player.Name
    bg.Adornee = root
    bg.Size = UDim2.new(0, 200, 0, 50)
    bg.StudsOffset = Vector3.new(0, 3, 0)
    bg.AlwaysOnTop = true
    bg.Parent = folder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = SETTINGS.SB_ESPColor
    label.TextStrokeTransparency = 0
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = player.Name
    label.Parent = bg

    espObjects[player] = { bg = bg, label = label }
end

local function clearESP()
    for p, data in pairs(espObjects) do
        pcall(function() if data.bg then data.bg:Destroy() end end)
    end
    espObjects = {}
end

local function updateESP()
    if isDestroyed then return end
    if not SETTINGS.SB_ESP then
        if next(espObjects) then clearESP() end
        return
    end
    local root = getRoot()
    -- 新增 / 更新
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                if not espObjects[p] then
                    makeEsp(p)
                end
                local data = espObjects[p]
                if data and data.label and root then
                    local part = char:FindFirstChild("HumanoidRootPart")
                    local d = math.floor((part.Position - root.Position).Magnitude)
                    data.label.Text = string.format("%s [%dm]", p.Name, d)
                end
            end
        end
    end
    -- 移除已离开 / 无角色的
    for p, data in pairs(espObjects) do
        local char = p.Character
        if (not char) or (not char:FindFirstChild("HumanoidRootPart")) then
            pcall(function() if data.bg then data.bg:Destroy() end end)
            espObjects[p] = nil
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 杂项工具
-- ══════════════════════════════════════════════════════════════════
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

local function refreshPlayerList()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then out[#out + 1] = p.Name end
    end
    table.sort(out)
    return out
end

local THEME_PRESETS = {
    ["Pink"]    = Color3.fromRGB(255, 80, 160),
    ["Cyan"]    = Color3.fromRGB(0, 200, 255),
    ["Purple"]  = Color3.fromRGB(180, 60, 255),
    ["Green"]   = Color3.fromRGB(0, 255, 120),
    ["Red"]     = Color3.fromRGB(255, 70, 90),
    ["Gold"]    = Color3.fromRGB(255, 200, 50),
    ["HotPink"] = Color3.fromRGB(255, 105, 180),
}

-- ══════════════════════════════════════════════════════════════════
-- 12. 构建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title        = "Slap Battle",
    Subtitle     = "打耳光大战 v1.0",
    ThemeColor   = Color3.fromRGB(255, 80, 160),
    Transparency = 0.3,
    Size         = UDim2.new(0, 640, 0, 600),
    Keybind      = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: 战斗 ─────────────────────────────────────────────────
local CombatTab = Window:AddTab({ Name = "战斗", Icon = "rbxassetid://6034287594" })

CombatTab:AddSection({ Name = "拍击" })

CombatTab:AddToggle({
    Name = "Slap Aura (范围拍所有人)", Default = false, Flag = "SB_SlapAura",
    Callback = function(s)
        SETTINGS.SB_SlapAura = s
        if s then SETTINGS.SB_AutoSlap = false end
        notify("Slap Aura", s and "已开启" or "已关闭", 2, s and "Success" or "Info")
    end,
})

CombatTab:AddToggle({
    Name = "Auto Slap (只拍最近)", Default = false, Flag = "SB_AutoSlap",
    Callback = function(s)
        SETTINGS.SB_AutoSlap = s
        if s then SETTINGS.SB_SlapAura = false end
        notify("Auto Slap", s and "已开启" or "已关闭", 2, s and "Success" or "Info")
    end,
})

CombatTab:AddSlider({
    Name = "拍击范围", Min = 5, Max = 60, Default = 30, Increment = 1,
    Suffix = " studs", Flag = "SB_SlapReach",
    Callback = function(v) SETTINGS.SB_SlapReach = v end,
})

CombatTab:AddSlider({
    Name = "拍击间隔 (节流)", Min = 0.02, Max = 1, Default = 0.1, Increment = 0.01,
    Suffix = "s", Flag = "SB_SlapInterval",
    Callback = function(v) SETTINGS.SB_SlapInterval = v end,
})

CombatTab:AddSection({ Name = "手动 / 技能" })

CombatTab:AddButton({
    Name = "拍最近的人 (E)",
    Callback = function()
        local ok = slapNearest()
        notify("Slap", ok and "已拍击最近目标" or "无目标 / 远程不可用", 2, ok and "Success" or "Warning")
    end,
})

CombatTab:AddButton({
    Name = "拍范围内所有人 (一次性)",
    Callback = function()
        if not hitRemote then
            notify("Slap", "拍击远程未找到", 2, "Error")
            return
        end
        slapAllInRange()
        notify("Slap", "已对范围内所有人发送拍击", 2, "Success")
    end,
})

CombatTab:AddButton({
    Name = "放手套技能 (T)",
    Callback = function()
        local ok = fireAbility()
        notify("Ability", ok and "已释放技能" or "技能远程不可用", 2, ok and "Success" or "Warning")
    end,
})

CombatTab:AddSection({ Name = "状态" })

local slapCountLabel = CombatTab:AddLabel({ Text = "拍击次数: 0" })
local hitRemoteLabel = CombatTab:AddLabel({ Text = "拍击远程: " .. (hitRemote and hitRemote.Name or "未找到") })

task.spawn(function()
    while not isDestroyed do
        pcall(function()
            if slapCountLabel then
                slapCountLabel:SetText("拍击次数: " .. tostring(slapCount))
            end
            if hitRemoteLabel then
                hitRemoteLabel:SetText("拍击远程: " .. (hitRemote and hitRemote.Name or "未找到"))
            end
        end)
        task.wait(0.5)
    end
end)

CombatTab:AddButton({
    Name = "重新探测拍击远程",
    Callback = function()
        refreshRemotes()
        notify("SlapBattle", string.format("Hit=%s Ability=%s",
            hitRemote and hitRemote.Name or "未找到",
            abilityRemote and abilityRemote.Name or "未找到"), 3, "Info")
    end,
})

-- ── TAB 2: 生存 ─────────────────────────────────────────────────
local SurviveTab = Window:AddTab({ Name = "生存", Icon = "rbxassetid://6035153470" })

SurviveTab:AddSection({ Name = "防掉虚空" })

SurviveTab:AddToggle({
    Name = "Anti-Void (掉下去自动拉回)", Default = false, Flag = "SB_AntiVoid",
    Callback = function(s)
        SETTINGS.SB_AntiVoid = s
        notify("Anti-Void", s and "已开启" or "已关闭", 2, s and "Success" or "Info")
    end,
})

SurviveTab:AddSlider({
    Name = "安全线 Y (低于此值拉回)", Min = -100, Max = 0, Default = -20, Increment = 1,
    Suffix = " y", Flag = "SB_SafeY",
    Callback = function(v) SETTINGS.SB_SafeY = v end,
})

SurviveTab:AddSection({ Name = "抗性与手套" })

SurviveTab:AddToggle({
    Name = "防击飞 / 稳定 (实验)", Default = false, Flag = "SB_AntiKnockback",
    Callback = function(s)
        SETTINGS.SB_AntiKnockback = s
        toggleAntiKnockback(s)
        notify("Anti-Knockback", s and "已开启(实验)" or "已关闭", 2, s and "Warning" or "Info")
    end,
})

SurviveTab:AddToggle({
    Name = "自动重新装备手套", Default = false, Flag = "SB_AutoReGlove",
    Callback = function(s) SETTINGS.SB_AutoReGlove = s end,
})

-- ── TAB 3: 玩家 ─────────────────────────────────────────────────
local PlayerTab = Window:AddTab({ Name = "玩家", Icon = "rbxassetid://6034466796" })

PlayerTab:AddSection({ Name = "ESP" })

PlayerTab:AddToggle({
    Name = "ESP (头顶名牌 + 距离)", Default = false, Flag = "SB_ESP",
    Callback = function(s)
        SETTINGS.SB_ESP = s
        notify("ESP", s and "已开启" or "已关闭", 2, s and "Success" or "Info")
    end,
})

PlayerTab:AddColorPicker({
    Name = "ESP 颜色", Default = SETTINGS.SB_ESPColor, Flag = "SB_ESPColor",
    Callback = function(c)
        SETTINGS.SB_ESPColor = c
        for _, data in pairs(espObjects) do
            pcall(function() if data.label then data.label.TextColor3 = c end end)
        end
    end,
})

PlayerTab:AddSection({ Name = "基础移动" })

PlayerTab:AddToggle({
    Name = "移速开启", Default = false, Flag = "SB_WalkSpeedEnabled",
    Callback = function(s) SETTINGS.SB_WalkSpeedEnabled = s end,
})

PlayerTab:AddSlider({
    Name = "移速", Min = 16, Max = 200, Default = 50, Increment = 1,
    Suffix = "", Flag = "SB_WalkSpeed",
    Callback = function(v) SETTINGS.SB_WalkSpeed = v end,
})

PlayerTab:AddToggle({
    Name = "跳跃力开启", Default = false, Flag = "SB_JumpPowerEnabled",
    Callback = function(s) SETTINGS.SB_JumpPowerEnabled = s end,
})

PlayerTab:AddSlider({
    Name = "跳跃力", Min = 50, Max = 300, Default = 100, Increment = 1,
    Suffix = "", Flag = "SB_JumpPower",
    Callback = function(v) SETTINGS.SB_JumpPower = v end,
})

PlayerTab:AddToggle({
    Name = "无限跳", Default = false, Flag = "SB_InfJump",
    Callback = function(s)
        SETTINGS.SB_InfJump = s
        toggleInfJump(s)
    end,
})

PlayerTab:AddSection({ Name = "特殊移动" })

PlayerTab:AddToggle({
    Name = "穿墙", Default = false, Flag = "SB_Noclip",
    Callback = function(s)
        SETTINGS.SB_Noclip = s
        toggleNoclip(s)
        notify("NoClip", s and "ON" or "OFF", 1.5, "Info")
    end,
})

PlayerTab:AddToggle({
    Name = "飞行", Default = false, Flag = "SB_Fly",
    Callback = function(s)
        SETTINGS.SB_Fly = s
        toggleFly(s, SETTINGS.SB_FlySpeed)
        notify("Fly", s and "ON" or "OFF", 1.5, "Info")
    end,
})

PlayerTab:AddSlider({
    Name = "飞行速度", Min = 20, Max = 300, Default = 80, Increment = 5,
    Suffix = "", Flag = "SB_FlySpeed",
    Callback = function(v) SETTINGS.SB_FlySpeed = v end,
})

-- ── TAB 4: 杂项 ─────────────────────────────────────────────────
local MiscTab = Window:AddTab({ Name = "杂项", Icon = "rbxassetid://6031280882" })

MiscTab:AddSection({ Name = "玩家操作" })

local playerDropdown = MiscTab:AddDropdown({
    Name = "玩家列表", Items = refreshPlayerList(), Flag = "SB_SelectedPlayer",
    Callback = function(v) selectedPlayer = v end,
})

MiscTab:AddButton({
    Name = "刷新玩家列表",
    Callback = function()
        local items = refreshPlayerList()
        if playerDropdown and playerDropdown.Refresh then
            pcall(function() playerDropdown:Refresh(items) end)
        end
        notify("SlapBattle", "共 " .. #items .. " 名其他玩家", 2, "Info")
    end,
})

MiscTab:AddButton({
    Name = "传送到选中玩家",
    Callback = function()
        if not selectedPlayer then
            notify("SlapBattle", "请先选择玩家", 2, "Warning")
            return
        end
        local target = Players:FindFirstChild(selectedPlayer)
        if target and target.Character then
            local tr = target.Character:FindFirstChild("HumanoidRootPart")
            local root = getRoot()
            if tr and root then
                local off = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
                pcall(function() root.CFrame = CFrame.new(tr.Position + off) end)
                notify("SlapBattle", "已传送到 " .. selectedPlayer, 2, "Success")
                return
            end
        end
        notify("SlapBattle", "传送失败", 2, "Error")
    end,
})

MiscTab:AddSection({ Name = "服务器" })

MiscTab:AddButton({
    Name = "重新加入 (Rejoin)",
    Callback = function()
        notify("SlapBattle", "正在重新加入...", 2, "Info")
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    end,
})

MiscTab:AddToggle({
    Name = "Anti-AFK (防挂机踢出)", Default = false, Flag = "SB_AntiAFK",
    Callback = function(s)
        SETTINGS.SB_AntiAFK = s
        if s then setupAntiAFK() end
    end,
})

MiscTab:AddSection({ Name = "UI 外观" })

MiscTab:AddToggle({
    Name = "彩虹边框动画", Default = QuantumUI.RainbowEnabled, Flag = "SB_RainbowBorder",
    Callback = function(state) QuantumUI.RainbowEnabled = state end,
})

MiscTab:AddSlider({
    Name = "彩虹速度", Min = 0.1, Max = 5, Default = QuantumUI.RainbowSpeed or 1, Increment = 0.1,
    Suffix = "x", Flag = "SB_RainbowSpeed",
    Callback = function(v) QuantumUI.RainbowSpeed = v end,
})

MiscTab:AddDropdown({
    Name = "预设主题色", Items = { "Pink", "Cyan", "Purple", "Green", "Red", "Gold", "HotPink" },
    Default = "Pink", Flag = "SB_ThemePreset",
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
        if _G.SB_Cleanup then _G.SB_Cleanup() end
    end,
})

MiscTab:AddParagraph({
    Title = "Slap Battle v1.0",
    Content = table.concat({
        "PlaceId: 6403373529",
        "",
        "拍击原理:",
        "  ReplicatedStorage.GeneralHit:FireServer(part)",
        "  (part = 受害者角色里的 BasePart, 优先 HumanoidRootPart)",
        "  回退链: GeneralHit → 老远程 b → 动态扫手套脚本常量",
        "",
        "生存: 掉到安全线以下自动拉回最后的安全点;",
        "  地图边缘是虚空(DEATHBARRIER), 掉下去即死。",
        "",
        "快捷键: E=拍最近  T=放技能  RightShift=UI",
        "",
        "注意: 服务器对手套有冷却, 拍太快会被忽略;",
        "  实际 slap 频率受限于你手套自身的拍击冷却。",
    }, "\n"),
})

-- ══════════════════════════════════════════════════════════════════
-- 13. 快捷键
-- ══════════════════════════════════════════════════════════════════
inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed or isDestroyed then return end
    local key = input.KeyCode

    if key == Enum.KeyCode.E then
        local ok = slapNearest()
        notify("E", ok and "拍了最近的人" or "无目标", 1.2, "Info")
    elseif key == Enum.KeyCode.T then
        local ok = fireAbility()
        notify("T", ok and "技能已放" or "技能不可用", 1.2, "Info")
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 14. 主循环
-- ══════════════════════════════════════════════════════════════════
charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if isDestroyed then return end
    if SETTINGS.SB_Noclip then toggleNoclip(true) end
    if SETTINGS.SB_InfJump then toggleInfJump(true) end
    if SETTINGS.SB_Fly then toggleFly(true, SETTINGS.SB_FlySpeed) end
end)

-- 远程探测保活: 换局后远程实例可能重建
task.spawn(function()
    while not isDestroyed do
        task.wait(5)
        if not (hitRemote and hitRemote.Parent) then
            refreshRemotes()
        end
    end
end)

mainConn = RunService.RenderStepped:Connect(function()
    if isDestroyed then return end
    pcall(combatStep)
    pcall(movementStep)
    pcall(survivalStep)
    pcall(updateESP)
end)

-- ══════════════════════════════════════════════════════════════════
-- 15. 清理
-- ══════════════════════════════════════════════════════════════════
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    local conns = {
        inputConn, charAddedConn, mainConn, noclipConn,
        infJumpConn, flyConn, idledConn, espConn, voidConn, knockConn,
    }
    for _, c in ipairs(conns) do
        if c then pcall(function() c:Disconnect() end) end
    end

    if flyBV then pcall(function() flyBV:Destroy() end) end
    if flyBG then pcall(function() flyBG:Destroy() end) end

    clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end

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
            Title = "SlapBattle", Text = "脚本已卸载", Duration = 2,
        })
    end)
end

_G.SB_Cleanup = cleanup

task.wait(0.5)
notify("Slap Battle v1.0", "Slap Battle 辅助已加载\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[SlapBattle] v1.0 (PlaceId: %d) 加载完成 | Drawing: %s",
    game.PlaceId, hasDrawing and "可用" or "不可用(不影响功能)"))
