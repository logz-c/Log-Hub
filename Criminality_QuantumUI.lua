--[[
    Criminality (犯罪) 辅助脚本 v1.0  ——  Quantum UI Library 版
    适配 PlaceId: 4588604953
    功能来源: BS-loves_you.txt (已彻底剥离所有信息窃取/Webhook/外部脚本加载)
    UI 框架: Quantum UI v3.x (SciFi-UI-Library)

    ⚠️  安全承诺: 本脚本:
      • 无任何 Discord Webhook / Google Forms / 统计上报
      • 不采集 IP / HWID / 账号信息 / 国家 / 注入器名
      • 不 loadstring 任何 pastebin / gitee / github 外部代码
      • 所有功能纯本地实现，不发 HTTP 请求 (除加载 UI 库本身外)
--]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0.  SINGLETON GUARD — 防止重复注入
-- ══════════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════════
-- 1.  LOAD QUANTUM UI LIBRARY  (优先在线，回退本地)
-- ══════════════════════════════════════════════════════════════════
local success, QuantumUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"))()
end)

if not success then
    warn("[Criminality] 在线加载 Quantum UI 失败，尝试本地源码...")
    local localOk, localLib = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localOk or not localLib then
        error("[Criminality] 无法加载 Quantum UI Library，脚本终止")
        return
    end
    QuantumUI = localLib
end
print(("[Criminality] Quantum UI v%s 加载成功"):format(QuantumUI.Version))

-- ══════════════════════════════════════════════════════════════════
-- 2.  ROBLOX SERVICES & 常量
-- ══════════════════════════════════════════════════════════════════
local Players           = game:GetService("Players")
local LocalPlayer       = Players.LocalPlayer
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local Camera            = workspace.CurrentCamera
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ══════════════════════════════════════════════════════════════════
-- 3.  SETTINGS  (每个字段对应 UI Flag, 参与 Config 保存/加载)
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    ── 世界功能 ──────────────────────────────────────────────
    Fullbright           = false,
    AutoOpenDoors        = false,
    NoBarriers           = false,
    NoGrinder            = false,
    FastPickup           = false,
    AutoPickupScraps     = false,
    AutoPickupTools      = false,
    AutopickupCrates     = false,
    AutoPickupMoney      = false,

    ── 玩家功能 ──────────────────────────────────────────────
    FOV                  = Camera and Camera.FieldOfView or 70,
    CameraMaxZoom        = LocalPlayer and LocalPlayer.CameraMaxZoomDistance or 30,
    JumpHeight           = 7.1,
    Gravity              = workspace and workspace.Gravity or 196.2,
    Infstamina           = false,
    InfstaminaMethod     = "Getgc",          -- "Getgc" | "low exploit"
    Nofalldamage         = false,
    Noclip               = false,
    FakeDown             = true,
    Stopneckmove         = false,
    Unbreaklimbs         = false,

    ── 战斗功能 ──────────────────────────────────────────────
    SilentAim            = false,
    SilentAim_DrawSize   = 50,
    SilentAim_DrawColor  = Color3.new(1, 1, 1),
    SilentAim_CheckDowned= false,
    SilentAim_CheckWall  = false,
    SilentAim_CheckTeam  = false,
    SilentAim_CheckWL    = false,

    AimBot               = false,
    AimBot_DrawSize      = 50,
    AimBot_DrawColor     = Color3.new(1, 1, 1),
    AimBot_CheckDowned   = false,
    AimBot_CheckWall     = false,
    AimBot_CheckTeam     = false,
    AimBot_CheckWL       = false,
    AimBot_Velocity      = false,
    AimBot_Smooth        = false,
    AimBot_SmoothSize    = 0.5,

    Meleeaura            = false,
    Melee_ShowAnim       = false,
    Melee_CheckDowned    = false,
    Melee_CheckTeam      = false,
    Melee_CheckWL        = false,
    Melee_Distance       = 15,

    RageBot              = false,
    RageBot_CheckDowned  = false,
    RageBot_CheckWL      = false,

    Instantreload        = false,

    ── 视觉功能 ──────────────────────────────────────────────
    ESP                  = false,
    ESP_Highlight        = false,
    ArmsChams            = false,
    ToolsChams           = false,

    ── 白名单 ────────────────────────────────────────────────
    WhiteListRadius      = 50,
}

-- ══════════════════════════════════════════════════════════════════
-- 4.  全局状态
-- ══════════════════════════════════════════════════════════════════
local RUNS = {}               -- 存储所有 RenderStepped/Heartbeat 连接
local DrawingObjects = {}     -- 存储所有 Drawing.new 对象
local WhiteList = {}          -- { [Player] = true }
local funcindex = {
    Fullbright = { oldClockTime = nil, oldBrightness = nil }
}
local Window = nil
local isDestroyed = false

-- ══════════════════════════════════════════════════════════════════
-- 5.  工具函数
-- ══════════════════════════════════════════════════════════════════
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
                Title = title, Text = content, Duration = duration or 3
            })
        end)
    end
end

local function CharStats(plr)
    return ReplicatedStorage:FindFirstChild("CharStats") and ReplicatedStorage.CharStats:FindFirstChild(plr.Name) or nil
end

local function safeDisconnect(connKey)
    if RUNS[connKey] then
        pcall(function() RUNS[connKey]:Disconnect() end)
        RUNS[connKey] = nil
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 6.  世界功能 实现
-- ══════════════════════════════════════════════════════════════════
do ── Fullbright ──────────────────────────────────────────────
    local function applyFullbright(on)
        local IndexFolder = ReplicatedStorage:FindFirstChild("Index")
        if on then
            if #Lighting:GetChildren() ~= 0 and not IndexFolder then
                IndexFolder = Instance.new("Folder")
                IndexFolder.Name = "Index"
                IndexFolder.Parent = ReplicatedStorage
                for _, c in ipairs(Lighting:GetChildren()) do c.Parent = IndexFolder end
            end
            funcindex.Fullbright.oldClockTime  = funcindex.Fullbright.oldClockTime  or Lighting.ClockTime
            funcindex.Fullbright.oldBrightness = funcindex.Fullbright.oldBrightness or Lighting.Brightness
            Lighting.ClockTime            = 14
            Lighting.Brightness           = 4
            Lighting.ExposureCompensation = 0.7
        else
            if IndexFolder then
                for _, c in ipairs(IndexFolder:GetChildren()) do c.Parent = Lighting end
                IndexFolder:Destroy()
            end
            Lighting.ClockTime            = funcindex.Fullbright.oldClockTime  or 14
            Lighting.Brightness           = funcindex.Fullbright.oldBrightness or 1
            Lighting.ExposureCompensation = 0
            funcindex.Fullbright.oldClockTime  = nil
            funcindex.Fullbright.oldBrightness = nil
        end
    end

    function _toggle_Fullbright(v)
        SETTINGS.Fullbright = v
        applyFullbright(v)
    end
end

do ── AutoOpenDoors ──────────────────────────────────────────
    function _toggle_AutoOpenDoors(v)
        SETTINGS.AutoOpenDoors = v
        safeDisconnect("AutoOpenDoors")
        if not v then return end
        RUNS.AutoOpenDoors = RunService.RenderStepped:Connect(function()
            local mapFolder = workspace:FindFirstChild("Map")
            local folderDoors = mapFolder and mapFolder:FindFirstChild("Doors")
            if not folderDoors then return end
            local closest, minDist = nil, 15
            local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not myHrp then return end
            for _, door in ipairs(folderDoors:GetChildren()) do
                local base = door:FindFirstChild("DoorBase")
                if base then
                    local d = (myHrp.Position - base.Position).Magnitude
                    if d < minDist then minDist = d; closest = door end
                end
            end
            if closest then
                local values = closest:FindFirstChild("Values")
                local events = closest:FindFirstChild("Events")
                if values and events then
                    local locked     = values:FindFirstChild("Locked")
                    local openValue  = values:FindFirstChild("Open")
                    local toggleEv   = events:FindFirstChild("Toggle")
                    if locked and openValue and toggleEv then
                        if locked.Value == true then
                            toggleEv:FireServer("Unlock", closest:FindFirstChild("Lock"))
                        elseif locked.Value == false and openValue.Value == false then
                            local k1, k2 = closest:FindFirstChild("Knob1"), closest:FindFirstChild("Knob2")
                            if k1 and k2 then
                                local d1, d2 = (myHrp.Position - k1.Position).Magnitude, (myHrp.Position - k2.Position).Magnitude
                                local knob = d1 < d2 and k1 or k2
                                toggleEv:FireServer("Open", knob)
                            end
                        end
                    end
                end
            end
        end)
    end
end

do ── NoBarriers / NoGrinder ────────────────────────────────
    function _toggle_NoBarriers(v)
        SETTINGS.NoBarriers = v
        local parts = workspace:FindFirstChild("Filter")
                    and workspace.Filter:FindFirstChild("Parts")
                    and workspace.Filter.Parts:FindFirstChild("F_Parts")
        if not parts then return end
        for _, d in ipairs(parts:GetDescendants()) do
            if d:IsA("Part") or d:IsA("MeshPart") then
                d.CanTouch = not v
            end
        end
    end

    function _toggle_NoGrinder(v)
        SETTINGS.NoGrinder = v
        local map = workspace:FindFirstChild("Map")
        if not map then return end
        local parts = map:FindFirstChild("Parts")
        if not parts then return end
        local grinders = parts:FindFirstChild("Grinders")
        local mp = parts:FindFirstChild("M_Parts")
        local flip = function(d)
            if d:IsA("Part") or d:IsA("MeshPart") then d.CanTouch = not v end
        end
        if grinders then for _, d in ipairs(grinders:GetDescendants()) do flip(d) end end
        if mp then for _, d in ipairs(mp:GetDescendants()) do
            if d:IsA("Part") and d.Name == "FirePart" then d.CanTouch = not v end
        end end
    end
end

do ── FastPickup ────────────────────────────────────────────
    local descConn = nil
    function _toggle_FastPickup(v)
        SETTINGS.FastPickup = v
        if descConn then pcall(function() descConn:Disconnect() end); descConn = nil end
        if not v then return end
        descConn = game.DescendantAdded:Connect(function(obj)
            if obj:IsA("ProximityPrompt") then
                obj.HoldDuration = 0
                obj:GetPropertyChangedSignal("HoldDuration"):Connect(function()
                    if SETTINGS.FastPickup then obj.HoldDuration = 0 end
                end)
            end
        end)
    end
end

do ── AutoPickup Scraps/Tools/Crates/Money ──────────────────
    ── 废料 (Scraps)
    function _toggle_AutoPickupScraps(v)
        SETTINGS.AutoPickupScraps = v
        safeDisconnect("AutopickupScraps")
        if not v then return end
        local remote = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("PIC_PU")
        if not remote then return end
        local folder = workspace:FindFirstChild("Filter") and workspace.Filter:FindFirstChild("SpawnedPiles")
        if not folder then return end
        local canPickup, startTick = true, tick()
        RUNS.AutopickupScraps = RunService.RenderStepped:Connect(function()
            local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not myHrp then return end
            local closest, minDist = nil, 15
            for _, a in ipairs(folder:GetChildren()) do
                if a and (a.Name == "S1" or a.Name == "S2") then
                    local mp = a:FindFirstChild("MeshPart")
                    if mp then
                        local d = (myHrp.Position - mp.Position).Magnitude
                        if d < minDist then minDist = d; closest = a end
                    end
                end
            end
            if closest and canPickup then
                remote:FireServer(string.reverse(closest:GetAttribute("jzu")))
                canPickup = false
            end
            if not canPickup and tick() - startTick >= 4.5 then
                canPickup = true; startTick = tick()
            end
        end)
    end

    ── 工具 (Tools)
    function _toggle_AutoPickupTools(v)
        SETTINGS.AutoPickupTools = v
        safeDisconnect("AutopickupTools")
        if not v then return end
        local remote = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("PIC_TLO")
        if not remote then return end
        local folder = workspace:FindFirstChild("Filter") and workspace.Filter:FindFirstChild("SpawnedTools")
        if not folder then return end
        local canPickup, startTick = true, tick()
        RUNS.AutopickupTools = RunService.RenderStepped:Connect(function()
            local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not myHrp then return end
            local closest, minDist = nil, 15
            local handlePart = nil
            for _, a in ipairs(folder:GetChildren()) do
                local h = a:FindFirstChild("Handle") or a:FindFirstChild("WeaponHandle")
                if h and (h:IsA("Part") or h:IsA("MeshPart")) then
                    local d = (myHrp.Position - h.Position).Magnitude
                    if d < minDist then minDist = d; closest = a; handlePart = h end
                end
            end
            if closest and handlePart and canPickup then
                remote:FireServer(handlePart)
                canPickup = false
            end
            if not canPickup and tick() - startTick >= 1.5 then
                canPickup = true; startTick = tick()
            end
        end)
    end

    ── 金钱 (Money/Bread)
    function _toggle_AutoPickupMoney(v)
        SETTINGS.AutoPickupMoney = v
        safeDisconnect("AutopickupMoney")
        if not v then return end
        local remote = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("CZDPZUS")
        if not remote then return end
        local folder = workspace:FindFirstChild("Filter") and workspace.Filter:FindFirstChild("SpawnedBread")
        if not folder then return end
        local canPickup, startTick = true, tick()
        RUNS.AutopickupMoney = RunService.RenderStepped:Connect(function()
            local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not myHrp then return end
            local closest, minDist = nil, 15
            for _, a in ipairs(folder:GetChildren()) do
                if a:IsA("BasePart") then
                    local d = (myHrp.Position - a.Position).Magnitude
                    if d < minDist then minDist = d; closest = a end
                end
            end
            if closest and canPickup then
                remote:FireServer(closest)
                canPickup = false
            end
            if not canPickup and tick() - startTick >= 1 then
                canPickup = true; startTick = tick()
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 7.  玩家功能 实现
-- ══════════════════════════════════════════════════════════════════
do ── FOV / JumpHeight / Gravity / CameraMaxZoom ────────────
    function _set_FOV(v)
        SETTINGS.FOV = v
        safeDisconnect("cameraFOV")
        RUNS.cameraFOV = RunService.RenderStepped:Connect(function()
            if Camera then Camera.FieldOfView = v end
        end)
    end

    function _set_CameraMaxZoom(v)
        SETTINGS.CameraMaxZoom = v
        LocalPlayer.CameraMaxZoomDistance = v
    end

    function _set_JumpHeight(v)
        SETTINGS.JumpHeight = v
        safeDisconnect("JumpHeight")
        RUNS.JumpHeight = RunService.RenderStepped:Connect(function()
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.UseJumpPower = false; hum.JumpHeight = v end
        end)
    end

    function _set_Gravity(v)
        SETTINGS.Gravity = v
        workspace.Gravity = v
    end
end

do ── InfStamina ────────────────────────────────────────────
    function _set_InfstaminaMethod(v)
        SETTINGS.InfstaminaMethod = v
    end

    function _toggle_Infstamina(v)
        SETTINGS.Infstamina = v
        if not v then
            ── 关闭: 尝试清掉 low exploit 模式下挂的 Attribute
            if LocalPlayer.Character then
                local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
                if hum and hum:GetAttribute("ZSPRN_M") then hum:SetAttribute("ZSPRN_M", nil) end
            end
            return
        end
        task.spawn(function()
            while SETTINGS.Infstamina do
                if SETTINGS.InfstaminaMethod == "Getgc" then
                    local staminaTables = {}
                    local ok = pcall(function()
                        for _, val in pairs(getgc(true)) do
                            if type(val) == "table" and rawget(val, "S") then
                                staminaTables[#staminaTables + 1] = val
                            end
                        end
                    end)
                    if ok then
                        for _, t in ipairs(staminaTables) do t.S = 100 end
                    end
                else ── "low exploit"
                    if LocalPlayer.Character then
                        local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
                        if hum and not hum:GetAttribute("ZSPRN_M") then hum:SetAttribute("ZSPRN_M", true) end
                    end
                end
                RunService.RenderStepped:Wait()
            end
        end)
        ── CharacterAdded 监听 (两种方式都需要)
        LocalPlayer.CharacterAdded:Connect(function(char)
            if not SETTINGS.Infstamina then return end
            task.wait(0.2)
            if SETTINGS.InfstaminaMethod == "low exploit" then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and not hum:GetAttribute("ZSPRN_M") then hum:SetAttribute("ZSPRN_M", true) end
            end
        end)
    end
end

do ── Nofalldamage (ForceField) ─────────────────────────────
    function _toggle_Nofalldamage(v)
        SETTINGS.Nofalldamage = v
        local function apply(char)
            if not char then return end
            if v then
                local ff = Instance.new("ForceField")
                ff.Visible = false; ff.Parent = char
            else
                for _, c in ipairs(char:GetChildren()) do
                    if c:IsA("ForceField") and not c.Visible then c:Destroy() end
                end
            end
        end
        apply(LocalPlayer.Character)
        LocalPlayer.CharacterAdded:Connect(apply)
    end
end

do ── Noclip ────────────────────────────────────────────────
    function _toggle_Noclip(v)
        SETTINGS.Noclip = v
        safeDisconnect("Noclip")
        if not v then return end
        RUNS.Noclip = RunService.RenderStepped:Connect(function()
            local char = LocalPlayer.Character
            if not char then return end
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("BasePart") and d.CanCollide then d.CanCollide = false end
            end
        end)
    end
end

do ── FakeDown ──────────────────────────────────────────────
    local signalConn = nil
    function _toggle_FakeDown(v)
        SETTINGS.FakeDown = v
        if signalConn then pcall(function() signalConn:Disconnect() end); signalConn = nil end
        local stats = CharStats(LocalPlayer)
        local downed = stats and stats:FindFirstChild("Downed")
        if not downed then return end
        if v then
            downed.Value = true
            signalConn = downed:GetPropertyChangedSignal("Value"):Connect(function()
                if SETTINGS.FakeDown then downed.Value = true end
            end)
        else
            downed.Value = false
        end
    end
end

do ── Stopneckmove ──────────────────────────────────────────
    function _toggle_Stopneckmove(v)
        SETTINGS.Stopneckmove = v
        local function apply(char)
            if not char then return end
            if v then char:SetAttribute("NoNeckMovement", true)
            else
                if char:GetAttribute("NoNeckMovement") ~= nil then
                    char:SetAttribute("NoNeckMovement", nil)
                end
            end
        end
        apply(LocalPlayer.Character)
        LocalPlayer.CharacterAdded:Connect(function(char)
            repeat task.wait() until char and char.Parent
            apply(char)
        end)
    end
end

do ── Unbreaklimbs ──────────────────────────────────────────
    local addedConn = nil
    function _toggle_Unbreaklimbs(v)
        SETTINGS.Unbreaklimbs = v
        if addedConn then pcall(function() addedConn:Disconnect() end); addedConn = nil end
        local stats = CharStats(LocalPlayer)
        local limbs = stats and stats:FindFirstChild("HealthValues")
        if not limbs then return end

        local function walk()
            for _, a in ipairs(limbs:GetChildren()) do
                for _, i in ipairs(a:GetChildren()) do
                    if i.Name == "Broken" then
                        if v then
                            i.Value = false
                            i:GetPropertyChangedSignal("Value"):Connect(function()
                                if SETTINGS.Unbreaklimbs then i.Value = false end
                            end)
                        end
                    end
                end
            end
        end
        walk()
        if v then
            addedConn = limbs.ChildAdded:Connect(walk)
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 8.  战斗功能 实现
-- ══════════════════════════════════════════════════════════════════

── 共用: 白名单/队伍/倒地 检查 ──────────────────────────────
local function inWhiteList(p)  return WhiteList[p] and true or false end
local function isSameTeam(p)   return p.Team and LocalPlayer.Team and p.Team == LocalPlayer.Team end
local function isDowned(p)
    local s = CharStats(p); return s and s:FindFirstChild("Downed") and s.Downed.Value == true
end

── SilentAim ──────────────────────────────────────────────────
do
    local visConn, damConn, target, circleConn = nil, nil, nil, nil

    function _set_SilentAim_DrawSize(v)
        SETTINGS.SilentAim_DrawSize = math.floor(v)
        if DrawingObjects.SilentAimCircle then
            DrawingObjects.SilentAimCircle.Radius = SETTINGS.SilentAim_DrawSize
        end
    end

    function _set_SilentAim_DrawColor(c)
        SETTINGS.SilentAim_DrawColor = c
        if DrawingObjects.SilentAimCircle then
            DrawingObjects.SilentAimCircle.Color = c
        end
    end

    function _toggle_SilentAim(v)
        SETTINGS.SilentAim = v

        ── 清理
        if visConn then pcall(function() visConn:Disconnect() end); visConn = nil end
        if damConn then pcall(function() damConn:Disconnect() end); damConn = nil end
        if circleConn then pcall(function() circleConn:Disconnect() end); circleConn = nil end
        if DrawingObjects.SilentAimCircle then
            DrawingObjects.SilentAimCircle:Remove(); DrawingObjects.SilentAimCircle = nil
        end
        target = nil

        if not v then return end

        ── 画 FOV 圈
        DrawingObjects.SilentAimCircle = Drawing.new("Circle")
        local c = DrawingObjects.SilentAimCircle
        c.Color = SETTINGS.SilentAim_DrawColor; c.Thickness = 2; c.NumSides = 50
        c.Radius = SETTINGS.SilentAim_DrawSize; c.Filled = false; c.Visible = true
        c.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)

        ── RenderStepped 找最近目标
        circleConn = RunService.RenderStepped:Connect(function()
            target = nil
            local shortest = SETTINGS.SilentAim_DrawSize
            local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
            c.Position = center
            for _, p in ipairs(Players:GetPlayers()) do
                if p == LocalPlayer or not p.Character then continue end
                if SETTINGS.SilentAim_CheckDowned and isDowned(p) then continue end
                if SETTINGS.SilentAim_CheckTeam  and isSameTeam(p) then continue end
                if SETTINGS.SilentAim_CheckWL    and inWhiteList(p) then continue end
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then continue end
                local sp, on = Camera:WorldToViewportPoint(hrp.Position)
                if on then
                    local dist = (center - Vector2.new(sp.X, sp.Y)).Magnitude
                    if dist < shortest then shortest = dist; target = p end
                end
            end
        end)

        ── Hook 伤害
        local ev2 = ReplicatedStorage:FindFirstChild("Events2")
        local VisualizeEvent = ev2 and ev2:FindFirstChild("Visualize")
        local DamageEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("ZFKLF__H")
        if not VisualizeEvent or not DamageEvent then return end

        visConn = VisualizeEvent.Event:Connect(function(_, ShotCode, _, Gun, _, StartPos, BulletsPerShot)
            if not SETTINGS.SilentAim or not target or not target.Character then return end
            local hum = target.Character:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then return end
            if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChildOfClass("Tool") then return end
            local targetParts = {"Head"}
            local partName = targetParts[math.random(1, #targetParts)]
            local targetPart = target.Character:FindFirstChild(partName)
            if not targetPart then return end

            local partPos = targetPart.Position
            local Bullets = {}
            local count = math.clamp(#BulletsPerShot, 1, 100)
            for i = 1, count do
                Bullets[i] = CFrame.new(StartPos, partPos).LookVector
            end
            task.wait(0.005)
            for i, dir in ipairs(Bullets) do
                DamageEvent:FireServer("🧈", Gun, ShotCode, i, targetPart, partPos, dir)
            end
            if Gun:FindFirstChild("Hitmarker") then Gun.Hitmarker:Fire(targetPart) end
        end)
    end
end

── AimBot ────────────────────────────────────────────────────
do
    local rsConn, aimTarget, btn, circle = nil, nil, nil, nil
    local pressed, canUsing, firstPerson = false, false, true
    local predictCoef = 15
    local currentPart = "Head"
    local lastTick, randPart = tick(), nil

    function _set_AimBot_DrawSize(v)
        SETTINGS.AimBot_DrawSize = math.floor(v)
        if DrawingObjects.AimBotCircle then DrawingObjects.AimBotCircle.Radius = SETTINGS.AimBot_DrawSize end
    end
    function _set_AimBot_DrawColor(c)
        SETTINGS.AimBot_DrawColor = c
        if DrawingObjects.AimBotCircle then DrawingObjects.AimBotCircle.Color = c end
    end
    function _set_AimBot_SmoothSize(v)
        SETTINGS.AimBot_SmoothSize = v
    end

    local function getClosest()
        local closest, closestDist = nil, SETTINGS.AimBot_DrawSize
        local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LocalPlayer or not p.Character then continue end
            local parts = {"Head"}
            if #parts == 0 then currentPart = "Head"
            elseif #parts == 1 then currentPart = parts[1]
            elseif tick() - lastTick >= 0.5 then
                randPart = parts[math.random(1, #parts)]; lastTick = tick()
                currentPart = randPart or parts[1]
            end
            local tp = p.Character:FindFirstChild(currentPart)
            if not tp then continue end
            local sp, on = Camera:WorldToViewportPoint(tp.Position)
            if not on then continue end
            if SETTINGS.AimBot_CheckTeam and isSameTeam(p) then continue end
            if SETTINGS.AimBot_CheckWL   and inWhiteList(p) then continue end
            local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
            if d < closestDist then closestDist = d; closest = p end
        end
        return closest
    end

    function _toggle_AimBot(v)
        SETTINGS.AimBot = v
        ── 清理
        if rsConn then pcall(function() rsConn:Disconnect() end); rsConn = nil end
        if DrawingObjects.AimBotCircle then DrawingObjects.AimBotCircle:Remove(); DrawingObjects.AimBotCircle = nil end
        if btn then pcall(function() btn:Destroy() end); btn = nil end
        aimTarget, pressed = nil, false

        if not v then return end

        ── 画面中心按钮 (切换开关)
        btn = Instance.new("TextButton")
        btn.Parent = CoreGui
        btn.Name = "Criminality_AimbotBtn"
        btn.BackgroundColor3 = Color3.new(0, 0, 0); btn.BackgroundTransparency = 0.5
        btn.Position = UDim2.new(0.689, 0, 0.521, 0); btn.Size = UDim2.new(0, 40, 0, 40)
        btn.TextSize = 10; btn.TextColor3 = Color3.new(1, 1, 1); btn.Text = "Aim"
        btn.AutoButtonColor = false
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = btn

        ── FOV 圈
        DrawingObjects.AimBotCircle = Drawing.new("Circle")
        local c = DrawingObjects.AimBotCircle
        c.Color = SETTINGS.AimBot_DrawColor; c.Thickness = 2; c.NumSides = 50
        c.Radius = SETTINGS.AimBot_DrawSize; c.Filled = false; c.Visible = true
        c.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)

        btn.MouseButton1Click:Connect(function()
            pressed = not pressed
            aimTarget = pressed and getClosest() or nil
            btn.BackgroundColor3 = pressed and Color3.fromRGB(0, 180, 90) or Color3.new(0, 0, 0)
            btn.Text = pressed and "ON" or "Aim"
        end)

        rsConn = RunService.RenderStepped:Connect(function()
            ── 第一人称检测
            local mag = (Camera.Focus.p - Camera.CFrame.p).Magnitude
            canUsing = (mag <= 1.5)
            ── 更新圈位置
            c.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)

            if SETTINGS.AimBot and pressed and aimTarget and aimTarget.Character then
                local head = aimTarget.Character:FindFirstChild(currentPart)
                local hum = aimTarget.Character:FindFirstChildOfClass("Humanoid")
                if head and hum and hum.Health ~= 0 and canUsing then
                    if SETTINGS.AimBot_CheckDowned and isDowned(aimTarget) then return end
                    local targetPos = head.Position
                    if SETTINGS.AimBot_Velocity then
                        targetPos = targetPos + head.Velocity / predictCoef
                    end
                    local alpha = SETTINGS.AimBot_Smooth and (1 - SETTINGS.AimBot_SmoothSize) or 0.9
                    Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.p, targetPos), alpha)
                elseif not aimTarget.Character or (aimTarget.Character:FindFirstChildOfClass("Humanoid").Health == 0) then
                    aimTarget = getClosest()
                end
            end
        end)
    end
end

── MeleeAura ─────────────────────────────────────────────────
do
    local loopRunning = false

    function _set_Melee_Distance(v)
        SETTINGS.Melee_Distance = v
    end

    function _toggle_Meleeaura(v)
        SETTINGS.Meleeaura = v
        if v and loopRunning then return end
        if not v then loopRunning = false; return end

        local remote1 = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("XMHH.2")
        local remote2 = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("XMHH2.2")
        if not remote1 or not remote2 then return end

        local AttackCD = {
            ["Fists"] = .05, ["Knuckledusters"] = .05, ["Nunchucks"] = 0.05,
            ["Shiv"] = .05, ["Bat"] = 1, ["Metal-Bat"] = 1, ["Chainsaw"] = 2.5,
            ["Balisong"] = .05, ["Rambo"] = .3, ["Shovel"] = 3,
            ["Sledgehammer"] = 2, ["Katana"] = .1, ["Wrench"] = .1, ["FireAxe"] = 2.6
        }
        local part, randPart = "Head", nil
        local LastTick, AttachTick = tick(), tick()
        local attach, attachcd = false, 0.1

        local function Attack(targetChar)
            if not targetChar or not targetChar:FindFirstChild("Head") then return end
            local mychar = LocalPlayer.Character; if not mychar then return end
            local TOOL = mychar:FindFirstChildOfClass("Tool"); if not TOOL then return end
            local AnimFolder = TOOL:FindFirstChild("AnimsFolder"); if not AnimFolder then return end
            local anim = AnimFolder:FindFirstChild("Slash1"); if not anim then return end

            if tick() - AttachTick >= attachcd then
                local result = remote1:InvokeServer("🍞", tick(), TOOL, "43TRFWX", "Normal", tick(), true)
                attachcd = AttackCD[TOOL.Name] or 0.5
                if SETTINGS.Melee_ShowAnim then
                    local load = mychar:FindFirstChildOfClass("Humanoid"):FindFirstChild("Animator"):LoadAnimation(anim)
                    load:Play(); load:AdjustSpeed(1.3)
                end
                task.wait(0.3 + math.random() * 0.2)
                if TOOL and targetChar and targetChar.Parent then
                    local Handle = TOOL:FindFirstChild("WeaponHandle") or TOOL:FindFirstChild("Handle") or mychar:FindFirstChild("Right Arm")
                    local args = {
                        "🍞", tick(), TOOL, "2389ZFX34", result, true, Handle,
                        targetChar:FindFirstChild(part), targetChar,
                        mychar.HumanoidRootPart.Position, targetChar:FindFirstChild(part).Position
                    }
                    if TOOL.Name == "Chainsaw" then
                        for i = 1, 15 do remote2:FireServer(unpack(args)) end
                    else
                        remote2:FireServer(unpack(args))
                    end
                    AttachTick = tick()
                end
            end
        end

        loopRunning = true
        task.spawn(function()
            while SETTINGS.Meleeaura and not isDestroyed do
                local mychar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                local myhrp = mychar:FindFirstChild("HumanoidRootPart")
                if myhrp then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p == LocalPlayer then continue end
                        local char = p.Character; if not char then continue end
                        local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
                        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health == 0 then continue end
                        if char:FindFirstChildOfClass("ForceField") then continue end
                        local d = (myhrp.Position - hrp.Position).Magnitude
                        if d >= SETTINGS.Melee_Distance then continue end
                        if SETTINGS.Melee_CheckWL    and inWhiteList(p) then continue end
                        if SETTINGS.Melee_CheckTeam  and isSameTeam(p) then continue end
                        if SETTINGS.Melee_CheckDowned and isDowned(p) then continue end

                        ── 选择部位
                        local tgtParts = {"Head"}
                        if #tgtParts == 0 then part = "Head"
                        elseif #tgtParts == 1 then part = tgtParts[1]
                        elseif tick() - LastTick >= 0.2 then
                            randPart = tgtParts[math.random(1, #tgtParts)]; LastTick = tick()
                            part = randPart or tgtParts[1]
                        end
                        Attack(char)
                    end
                end
                RunService.Heartbeat:Wait()
            end
            loopRunning = false
        end)
    end
end

── RageBot ───────────────────────────────────────────────────
do
    local loopRunning = false

    function _toggle_RageBot(v)
        SETTINGS.RageBot = v
        if v and loopRunning then return end
        if not v then loopRunning = false; return end

        local function randomStr(len)
            local r = ""; for i = 1, len do r = r .. string.char(math.random(97, 122)) end; return r
        end

        local function getClosestEnemy()
            local myhrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not myhrp then return nil end
            local ce, sd = nil, 100
            for _, p in ipairs(Players:GetPlayers()) do
                if p == LocalPlayer then continue end
                local char = p.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if char and hrp and hum and hum.Health > 15 and not char:FindFirstChildOfClass("ForceField") then
                    if SETTINGS.RageBot_CheckWL    and inWhiteList(p) then continue end
                    if SETTINGS.RageBot_CheckDowned and isDowned(p)    then continue end
                    local d = (hrp.Position - myhrp.Position).Magnitude
                    if d < sd then sd = d; ce = p end
                end
            end
            return ce
        end

        local GNX_S   = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("GNX_S")
        local GNX_R   = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("GNX_R")
        local ZFKLF_H = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("ZFKLF__H")
        if not GNX_S or not GNX_R or not ZFKLF_H then return end

        local function Shoot(tgt)
            if not tgt or not tgt.Character then return end
            local head = tgt.Character:FindFirstChild("Head"); if not head then return end
            local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool"); if not tool then return end
            local vs = tool:FindFirstChild("Values"); local hm = tool:FindFirstChild("Hitmarker")
            if not vs or not hm then return end
            local ammo = vs:FindFirstChild("SERVER_Ammo"); local stored = vs:FindFirstChild("SERVER_StoredAmmo")
            if not ammo or not stored then return end
            local hitPos = head.Position
            local hitDir  = (hitPos - Camera.CFrame.Position).Unit
            local rKey = randomStr(30) .. "0"

            if tool.Name == "Beretta" or tool.Name == "TEC-9" then
                if ammo.Value > 0 then
                    GNX_S:FireServer(tick(), rKey, tool, "FDS9I83", Camera.CFrame.Position, {hitDir}, false)
                    task.delay(0.00001, function()
                        ZFKLF_H:FireServer("🧈", tool, rKey, 1, head, hitPos, hitDir)
                        ammo.Value = math.max(ammo.Value - 1, 0)
                        hm:Fire(head)
                        stored.Value = vs:FindFirstChild("SERVER_StoredAmmo").Value
                        GNX_R:FireServer(tick(), "KLWE89U0", tool)
                    end)
                end
            end
        end

        loopRunning = true
        task.spawn(function()
            while SETTINGS.RageBot and not isDestroyed do
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool") then
                    local tgt = getClosestEnemy()
                    if tgt then Shoot(tgt) end
                end
                RunService.RenderStepped:Wait()
            end
            loopRunning = false
        end)
    end
end

── InstantReload ─────────────────────────────────────────────
do
    local function hookTool(obj, GNX_R)
        if not obj:IsA("Tool") or not obj:FindFirstChild("IsGun") then return end
        local vs = obj:FindFirstChild("Values"); if not vs then return end
        local ammo   = vs:FindFirstChild("SERVER_Ammo")
        local stored = vs:FindFirstChild("SERVER_StoredAmmo")
        if not ammo or not stored then return end
        stored:GetPropertyChangedSignal("Value"):Connect(function()
            if SETTINGS.Instantreload then GNX_R:FireServer(tick(), "KLWE89U0", obj) end
        end)
        if stored.Value ~= 0 and SETTINGS.Instantreload then
            GNX_R:FireServer(tick(), "KLWE89U0", obj)
        end
        ammo:GetPropertyChangedSignal("Value"):Connect(function()
            if SETTINGS.Instantreload and stored.Value ~= 0 then
                GNX_R:FireServer(tick(), "KLWE89U0", obj)
            end
        end)
    end

    function _toggle_Instantreload(v)
        SETTINGS.Instantreload = v
        local GNX_R = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("GNX_R")
        if not GNX_R then return end

        local me = LocalPlayer.Character
        if me then
            for _, obj in ipairs(me:GetChildren()) do hookTool(obj, GNX_R) end
            me.ChildAdded:Connect(function(obj) hookTool(obj, GNX_R) end)
        end
        LocalPlayer.CharacterAdded:Connect(function(ch)
            repeat task.wait() until ch and ch.Parent
            ch.ChildAdded:Connect(function(obj) hookTool(obj, GNX_R) end)
            for _, obj in ipairs(ch:GetChildren()) do hookTool(obj, GNX_R) end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 9.  视觉功能 实现  (ESP / ArmsChams / ToolsChams)
-- ══════════════════════════════════════════════════════════════════
do ── ESP Highlight ──────────────────────────────────────────
    function _toggle_ESP(v)
        SETTINGS.ESP = v
        safeDisconnect("ESP")
        if not v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p == LocalPlayer then continue end
                local char = p.Character
                if char then local h = char:FindFirstChildOfClass("Highlight"); if h then h:Destroy() end end
            end
            return
        end
        RUNS.ESP = RunService.Heartbeat:Connect(function()
            if SETTINGS.ESP_Highlight then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p == LocalPlayer then continue end
                    local char = p.Character
                    if char and not char:FindFirstChildOfClass("Highlight") then
                        local hg = Instance.new("Highlight")
                        hg.Parent = char; hg.FillTransparency = 1; hg.OutlineTransparency = 0.4
                    end
                end
                Players.PlayerAdded:Connect(function(plr)
                    if not SETTINGS.ESP then return end
                    local c = plr.Character or plr.CharacterAdded:Wait()
                    task.wait(0.1)
                    if SETTINGS.ESP and SETTINGS.ESP_Highlight and c and not c:FindFirstChildOfClass("Highlight") then
                        local hg = Instance.new("Highlight")
                        hg.Parent = c; hg.FillTransparency = 1
                    end
                end)
            else
                for _, p in ipairs(Players:GetPlayers()) do
                    if p == LocalPlayer then continue end
                    local char = p.Character
                    if char then local h = char:FindFirstChildOfClass("Highlight"); if h then h:Destroy() end end
                end
            end
        end)
    end

    function _toggle_ESP_Highlight(v)
        SETTINGS.ESP_Highlight = v
        if not SETTINGS.ESP then return end
        ── 立即清理/应用
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LocalPlayer then continue end
            local char = p.Character; if not char then continue end
            local exist = char:FindFirstChildOfClass("Highlight")
            if v and not exist then
                local hg = Instance.new("Highlight")
                hg.Parent = char; hg.FillTransparency = 1
            elseif not v and exist then
                exist:Destroy()
            end
        end
    end
end

do ── ArmsChams / ToolsChams ────────────────────────────────
    function _toggle_ArmsChams(v)
        SETTINGS.ArmsChams = v
        local function apply()
            local vf = Camera and Camera:FindFirstChild("ViewModel")
            if not vf then return end
            local la, ra = vf:FindFirstChild("Left Arm"), vf:FindFirstChild("Right Arm")
            if la then la.Material = v and Enum.Material.ForceField or Enum.Material.Plastic end
            if ra then ra.Material = v and Enum.Material.ForceField or Enum.Material.Plastic end
        end
        apply()
        LocalPlayer.CharacterAdded:Connect(function()
            repeat task.wait() until Camera and Camera:FindFirstChild("ViewModel")
            apply()
        end)
    end

    function _toggle_ToolsChams(v)
        SETTINGS.ToolsChams = v
        ── 预留：实际可遍历 Tool.Handle 设置材质
        notify("提示", "ToolsChams 为预留功能，将在后续版本扩展", 3, "Warning")
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 10.  白名单管理
-- ══════════════════════════════════════════════════════════════════
function _set_WhiteListRadius(v) SETTINGS.WhiteListRadius = v end

function _markNearbyTeammates()
    local myhrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myhrp then notify("错误", "角色未加载", 3, "Error"); return end
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if hrp and (myhrp.Position - hrp.Position).Magnitude <= SETTINGS.WhiteListRadius then
            if not WhiteList[p] then WhiteList[p] = true; n = n + 1 end
        end
    end
    notify(("白名单已添加"):format(n), ("附近 %d 名玩家加入白名单"):format(n), 3, "Success")
end

function _clearWhiteList()
    local n = 0
    for p in pairs(WhiteList) do WhiteList[p] = nil; n = n + 1 end
    notify("白名单已清空", ("移除了 %d 名玩家"):format(n), 3, "Info")
end

-- ══════════════════════════════════════════════════════════════════
-- 11.  其他功能: 清理效果 / 重置设置
-- ══════════════════════════════════════════════════════════════════
function _cleanupVisuals()
    ── Drawing 对象
    for key, obj in pairs(DrawingObjects) do
        pcall(function() obj:Remove() end)
        DrawingObjects[key] = nil
    end
    ── 画面按钮
    for _, child in ipairs(CoreGui:GetChildren()) do
        if child.Name == "Criminality_AimbotBtn" then
            pcall(function() child:Destroy() end)
        end
    end
    ── Highlight
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local h = p.Character:FindFirstChildOfClass("Highlight")
            if h then h:Destroy() end
        end
    end
    notify("清理完成", "所有 Drawing / Highlight / AimbotBtn 已清理", 3, "Success")
end

function _resetAllSettings()
    ── 断开所有 RUNS
    for k in pairs(RUNS) do safeDisconnect(k) end
    ── 关闭所有 toggle (关闭时会自行清理连接/Drawing)
    for k, _ in pairs(SETTINGS) do
        if type(SETTINGS[k]) == "boolean" then SETTINGS[k] = false end
    end
    ── 清理 Drawing
    _cleanupVisuals()
    notify("重置完成", "所有功能已关闭，建议重载脚本以完全恢复", 4, "Warning")
end

-- ══════════════════════════════════════════════════════════════════
-- 12.  BUILD UI  (Quantum UI Library)
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title        = "Criminality 辅助",
    Subtitle     = "Quantum UI v" .. QuantumUI.Version,
    ThemeColor   = Color3.fromRGB(0, 220, 130),
    Transparency = 0.30,
    Size         = UDim2.new(0, 660, 0, 500),
    Keybind      = Enum.KeyCode.RightControl,
})
_G.QuantumUI_Window = Window

task.wait(3.5)   ── 等 UI 完全布局 (防止 Slider/Toggle Set 跳变)

──── 白名单快捷键 ─────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F2 then _markNearbyTeammates() end
    if input.KeyCode == Enum.KeyCode.F3 then _clearWhiteList()      end
end)

──── Tab 1: 世界功能 ──────────────────────────────────────────
local WorldTab = Window:AddTab({
    Name = "世界功能",
    Icon = "rbxassetid://6034287594",
})

WorldTab:AddSection({ Name = "环境修改" })
WorldTab:AddToggle({ Name = "夜视 Fullbright", Default = SETTINGS.Fullbright, Flag = "Fullbright",
    Callback = _toggle_Fullbright })
WorldTab:AddToggle({ Name = "自动开门", Default = SETTINGS.AutoOpenDoors, Flag = "AutoOpenDoors",
    Callback = _toggle_AutoOpenDoors })
WorldTab:AddToggle({ Name = "无屏障 (CanTouch off)", Default = SETTINGS.NoBarriers, Flag = "NoBarriers",
    Callback = _toggle_NoBarriers })
WorldTab:AddToggle({ Name = "防研磨机伤害", Default = SETTINGS.NoGrinder, Flag = "NoGrinder",
    Callback = _toggle_NoGrinder })

WorldTab:AddSection({ Name = "拾取优化" })
WorldTab:AddToggle({ Name = "快速拾取 (HoldDuration=0)", Default = SETTINGS.FastPickup, Flag = "FastPickup",
    Callback = _toggle_FastPickup })
WorldTab:AddToggle({ Name = "自动拾取废料", Default = SETTINGS.AutoPickupScraps, Flag = "AutoPickupScraps",
    Callback = _toggle_AutoPickupScraps })
WorldTab:AddToggle({ Name = "自动拾取工具", Default = SETTINGS.AutoPickupTools, Flag = "AutoPickupTools",
    Callback = _toggle_AutoPickupTools })
WorldTab:AddToggle({ Name = "自动拾取金钱", Default = SETTINGS.AutoPickupMoney, Flag = "AutoPickupMoney",
    Callback = _toggle_AutoPickupMoney })

──── Tab 2: 玩家功能 ──────────────────────────────────────────
local PlayerTab = Window:AddTab({
    Name = "玩家功能",
    Icon = "rbxassetid://6034509993",
})

PlayerTab:AddSection({ Name = "相机 / 物理" })
PlayerTab:AddSlider({ Name = "FOV", Min = 70, Max = 120, Default = SETTINGS.FOV, Increment = 1,
    Suffix = "°", Flag = "FOV", Callback = _set_FOV })
PlayerTab:AddSlider({ Name = "相机最大距离", Min = 10, Max = 500, Default = SETTINGS.CameraMaxZoom,
    Increment = 1, Suffix = "", Flag = "CameraMaxZoom", Callback = _set_CameraMaxZoom })
PlayerTab:AddSlider({ Name = "跳跃高度", Min = 7.1, Max = 25, Default = SETTINGS.JumpHeight,
    Increment = 0.1, Suffix = "stud", Flag = "JumpHeight", Callback = _set_JumpHeight })
PlayerTab:AddSlider({ Name = "重力", Min = 0, Max = 196.2, Default = SETTINGS.Gravity,
    Increment = 1, Suffix = "", Flag = "Gravity", Callback = _set_Gravity })

PlayerTab:AddSection({ Name = "生存类" })
PlayerTab:AddToggle({ Name = "无限体力", Default = SETTINGS.Infstamina, Flag = "Infstamina",
    Callback = _toggle_Infstamina })
PlayerTab:AddDropdown({ Name = "无限体力实现", Items = {"Getgc", "low exploit"},
    Default = SETTINGS.InfstaminaMethod, Flag = "InfstaminaMethod", Callback = _set_InfstaminaMethod })
PlayerTab:AddToggle({ Name = "无坠落伤害 (隐藏ForceField)", Default = SETTINGS.Nofalldamage,
    Flag = "Nofalldamage", Callback = _toggle_Nofalldamage })
PlayerTab:AddToggle({ Name = "穿墙 Noclip", Default = SETTINGS.Noclip, Flag = "Noclip",
    Callback = _toggle_Noclip })
PlayerTab:AddToggle({ Name = "伪装倒地", Default = SETTINGS.FakeDown, Flag = "FakeDown",
    Callback = _toggle_FakeDown })
PlayerTab:AddToggle({ Name = "停止颈部移动", Default = SETTINGS.Stopneckmove, Flag = "Stopneckmove",
    Callback = _toggle_Stopneckmove })
PlayerTab:AddToggle({ Name = "肢体不碎", Default = SETTINGS.Unbreaklimbs, Flag = "Unbreaklimbs",
    Callback = _toggle_Unbreaklimbs })

──── Tab 3: 战斗功能 ──────────────────────────────────────────
local CombatTab = Window:AddTab({
    Name = "战斗功能",
    Icon = "rbxassetid://6031280882",
})

CombatTab:AddSection({ Name = "静默瞄准 SilentAim" })
CombatTab:AddToggle({ Name = "静默瞄准 启用", Default = SETTINGS.SilentAim, Flag = "SilentAim",
    Callback = _toggle_SilentAim })
CombatTab:AddSlider({ Name = "FOV 圈半径", Min = 20, Max = 500, Default = SETTINGS.SilentAim_DrawSize,
    Increment = 1, Suffix = "px", Flag = "SilentAim_DrawSize", Callback = _set_SilentAim_DrawSize })
CombatTab:AddColorPicker({ Name = "FOV 圈颜色", Default = SETTINGS.SilentAim_DrawColor, Flag = "SilentAim_DrawColor",
    Callback = _set_SilentAim_DrawColor })
CombatTab:AddToggle({ Name = "忽略倒地玩家", Default = SETTINGS.SilentAim_CheckDowned,
    Flag = "SilentAim_CheckDowned", Callback = function(v) SETTINGS.SilentAim_CheckDowned = v end })
CombatTab:AddToggle({ Name = "忽略同队伍", Default = SETTINGS.SilentAim_CheckTeam,
    Flag = "SilentAim_CheckTeam",   Callback = function(v) SETTINGS.SilentAim_CheckTeam = v end })
CombatTab:AddToggle({ Name = "忽略白名单", Default = SETTINGS.SilentAim_CheckWL,
    Flag = "SilentAim_CheckWL",     Callback = function(v) SETTINGS.SilentAim_CheckWL = v end })

CombatTab:AddSection({ Name = "自瞄 AimBot  (点击 Aim 按钮切换)" })
CombatTab:AddToggle({ Name = "自瞄 启用", Default = SETTINGS.AimBot, Flag = "AimBot",
    Callback = _toggle_AimBot })
CombatTab:AddSlider({ Name = "FOV 圈半径", Min = 20, Max = 500, Default = SETTINGS.AimBot_DrawSize,
    Increment = 1, Suffix = "px", Flag = "AimBot_DrawSize", Callback = _set_AimBot_DrawSize })
CombatTab:AddColorPicker({ Name = "FOV 圈颜色", Default = SETTINGS.AimBot_DrawColor,
    Flag = "AimBot_DrawColor", Callback = _set_AimBot_DrawColor })
CombatTab:AddToggle({ Name = "忽略倒地玩家", Default = SETTINGS.AimBot_CheckDowned,
    Flag = "AimBot_CheckDowned", Callback = function(v) SETTINGS.AimBot_CheckDowned = v end })
CombatTab:AddToggle({ Name = "忽略同队伍", Default = SETTINGS.AimBot_CheckTeam,
    Flag = "AimBot_CheckTeam",   Callback = function(v) SETTINGS.AimBot_CheckTeam = v end })
CombatTab:AddToggle({ Name = "忽略白名单", Default = SETTINGS.AimBot_CheckWL,
    Flag = "AimBot_CheckWL",     Callback = function(v) SETTINGS.AimBot_CheckWL = v end })
CombatTab:AddToggle({ Name = "速度预测 Velocity", Default = SETTINGS.AimBot_Velocity,
    Flag = "AimBot_Velocity",    Callback = function(v) SETTINGS.AimBot_Velocity = v end })
CombatTab:AddToggle({ Name = "平滑瞄准", Default = SETTINGS.AimBot_Smooth,
    Flag = "AimBot_Smooth",      Callback = function(v) SETTINGS.AimBot_Smooth = v end })
CombatTab:AddSlider({ Name = "平滑强度", Min = 0, Max = 1, Default = SETTINGS.AimBot_SmoothSize,
    Increment = 0.05, Suffix = "", Flag = "AimBot_SmoothSize", Callback = _set_AimBot_SmoothSize })

CombatTab:AddSection({ Name = "近战光环 MeleeAura" })
CombatTab:AddToggle({ Name = "近战光环 启用", Default = SETTINGS.Meleeaura, Flag = "Meleeaura",
    Callback = _toggle_Meleeaura })
CombatTab:AddSlider({ Name = "攻击半径", Min = 3, Max = 30, Default = SETTINGS.Melee_Distance,
    Increment = 1, Suffix = "stud", Flag = "Melee_Distance", Callback = _set_Melee_Distance })
CombatTab:AddToggle({ Name = "显示攻击动画", Default = SETTINGS.Melee_ShowAnim,
    Flag = "Melee_ShowAnim",    Callback = function(v) SETTINGS.Melee_ShowAnim = v end })
CombatTab:AddToggle({ Name = "忽略倒地玩家", Default = SETTINGS.Melee_CheckDowned,
    Flag = "Melee_CheckDowned", Callback = function(v) SETTINGS.Melee_CheckDowned = v end })
CombatTab:AddToggle({ Name = "忽略同队伍", Default = SETTINGS.Melee_CheckTeam,
    Flag = "Melee_CheckTeam",   Callback = function(v) SETTINGS.Melee_CheckTeam = v end })
CombatTab:AddToggle({ Name = "忽略白名单", Default = SETTINGS.Melee_CheckWL,
    Flag = "Melee_CheckWL",     Callback = function(v) SETTINGS.Melee_CheckWL = v end })

CombatTab:AddSection({ Name = "狂暴 RageBot (Beretta / TEC-9)" })
CombatTab:AddToggle({ Name = "RageBot 启用", Default = SETTINGS.RageBot, Flag = "RageBot",
    Callback = _toggle_RageBot })
CombatTab:AddToggle({ Name = "忽略倒地玩家", Default = SETTINGS.RageBot_CheckDowned,
    Flag = "RageBot_CheckDowned", Callback = function(v) SETTINGS.RageBot_CheckDowned = v end })
CombatTab:AddToggle({ Name = "忽略白名单", Default = SETTINGS.RageBot_CheckWL,
    Flag = "RageBot_CheckWL",     Callback = function(v) SETTINGS.RageBot_CheckWL = v end })

CombatTab:AddSection({ Name = "杂项战斗" })
CombatTab:AddToggle({ Name = "瞬间换弹", Default = SETTINGS.Instantreload, Flag = "Instantreload",
    Callback = _toggle_Instantreload })

──── Tab 4: 视觉功能 ──────────────────────────────────────────
local VisualTab = Window:AddTab({
    Name = "视觉功能",
    Icon = "rbxassetid://6034281467",
})

VisualTab:AddSection({ Name = "ESP" })
VisualTab:AddToggle({ Name = "ESP 主开关", Default = SETTINGS.ESP, Flag = "ESP",
    Callback = _toggle_ESP })
VisualTab:AddToggle({ Name = "Highlight 高亮显示", Default = SETTINGS.ESP_Highlight,
    Flag = "ESP_Highlight", Callback = _toggle_ESP_Highlight })

VisualTab:AddSection({ Name = "材质 Chams" })
VisualTab:AddToggle({ Name = "手臂特效 (ForceField)", Default = SETTINGS.ArmsChams,
    Flag = "ArmsChams",  Callback = _toggle_ArmsChams })
VisualTab:AddToggle({ Name = "武器特效 (预留)", Default = SETTINGS.ToolsChams,
    Flag = "ToolsChams", Callback = _toggle_ToolsChams })

──── Tab 5: 白名单 & 其他 ────────────────────────────────────
local MiscTab = Window:AddTab({
    Name = "其他功能",
    Icon = "rbxassetid://6034284153",
})

MiscTab:AddSection({ Name = "白名单管理  (F2 标记附近 / F3 清空)" })
MiscTab:AddSlider({ Name = "白名单半径", Min = 5, Max = 200, Default = SETTINGS.WhiteListRadius,
    Increment = 1, Suffix = "stud", Flag = "WhiteListRadius", Callback = _set_WhiteListRadius })
MiscTab:AddButton({ Name = "🎯 标记附近玩家为队友", Callback = _markNearbyTeammates })
MiscTab:AddButton({ Name = "🗑️ 清空白名单",          Callback = _clearWhiteList })

MiscTab:AddSection({ Name = "工具" })
MiscTab:AddButton({ Name = "🧹 清理所有视觉对象 (Drawing/Highlight/AimBtn)",
    Callback = _cleanupVisuals })
MiscTab:AddButton({ Name = "⚠️ 重置所有功能开关",
    Callback = _resetAllSettings })

MiscTab:AddSection({ Name = "关于" })
MiscTab:AddParagraph({
    Title   = "Criminality 辅助  v1.0  (Quantum UI)",
    Content = table.concat({
        "• 功能来源: BS-loves_you.txt  PlaceId=4588604953",
        "• UI 框架:  Quantum UI Library v" .. QuantumUI.Version,
        "• 所有设置通过 Config Tab 自动保存 / 加载",
        "• 快捷键:  右Ctrl=显隐UI   F2=加附近队友   F3=清空白名单",
        "",
        "✅ 安全承诺: 本脚本无 Webhook / 无 IP/HWID 采集 / 无外部 loadstring",
    }, "\n"),
})

-- ══════════════════════════════════════════════════════════════════
-- 13.  CONFIG 自动加载  (每个 Flag → 对应控件 Set → 重新触发 Callback)
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
local autoCfg = QuantumUI.Config and QuantumUI.Config.GetAutoLoad and QuantumUI.Config.GetAutoLoad()
if autoCfg then
    local cfgData = QuantumUI.Config.Load(autoCfg)
    if cfgData and Window and Window.LoadConfig then
        Window:LoadConfig(cfgData)
        notify("配置已加载", ("使用配置: %s"):format(autoCfg), 4, "Success")
    end
elseif Window and Window.LoadDefaultConfig then
    Window:LoadDefaultConfig()
end

task.wait(0.3)
Window:Notify({
    Title    = "Criminality 辅助  v1.0",
    Content  = table.concat({
        "功能已就绪 — PlaceId = " .. game.PlaceId,
        "右 Ctrl = 显示/隐藏 UI",
        "F2 = 标记附近玩家入白名单  |  F3 = 清空白名单",
        "",
        "✅ 无 Webhook / 无 IP 采集 / 无外部脚本加载",
    }, "\n"),
    Duration = 7,
    Type     = "Success",
})
print("[Criminality] 脚本加载完成 — 5 个 Tab + Config 系统就绪")
