--[[
    Slap Battle 辅助脚本 (Quantum UI 版)  v2.0

    适配 PlaceId: 6403373529 (Slap Battles / 打耳光大战)

    ── 源码来源 (本版功能 100% 照搬) ────────────────────────────────
       flamingrobot/slap-battle 的 "Slap GUI By Mr.Exploit" (明文 550 行)
       实机交叉确认: ReplicatedStorage.b 与 GeneralHit 都在; 地图有 DEATHBARRIER。
       所有功能直接移植自该源码, 仅把裸 GUI 换成 QuantumUI 控件。

    ── 源码里的功能 (全部实现) ──────────────────────────────────────
      [God Mode]   销毁角色上的 Ragdolled / isInArena / TSVulnerability /
                   IsInDefaultArena (需先进入岛屿), 解除布娃娃与受击判定
      [Kill Aura]  "Big auto kill box": 删掉角色里除 Animate 外的 LocalScript,
                   手套放大到 30³, 焊一个 30³ 透明 neon 部件, 靠 Touched
                   触发 b:FireServer(hit); 跳过带 Reverse 的玩家; 死亡自动关
      [Speed]      把 Humanoid 改名为 "_ _ _" 后设 WalkSpeed (绕过名称检查)
      [JumpPower]  设 JumpPower
      [Gravity]    设 workspace.Gravity
      [No TimeFreeze] 角色变化时被锚定的部件自动解除锚定 (防卡)
      [Tp Starter/Pro/Lobby] 硬编码 CFrame 瞬移 (源码原值)
      [Tp to Player] 按名字瞬移到玩家
      [Force Reset] 瞬移到 DEATHBARRIER 强制死亡重生 (清 ragdoll)
      [Delete Gui]  卸载清理

    ── 额外补充 (源码没有, 但无害实用) ──────────────────────────────
      ESP(头顶名牌) / 飞行 / 穿墙 / 无限跳 / Anti-Void(掉虚空拉回) /
      自动重装手套 / 防挂机 / 主题 / 彩虹边框

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
    -- 战斗 (源码功能)
    SB_KillAura      = false,
    SB_GodMode       = false,   -- 按钮触发, 这里仅作状态显示

    -- 移动 (源码功能)
    SB_SpeedEnabled  = false,
    SB_Speed         = 50,
    SB_JumpEnabled   = false,
    SB_Jump          = 100,
    SB_GravityEnabled = false,
    SB_Gravity       = 196,
    SB_NoTimeFreeze  = false,

    -- 生存
    SB_AntiVoid      = false,
    SB_SafeY         = -20,
    SB_AutoReGlove   = false,

    -- 玩家
    SB_ESP           = false,
    SB_ESPColor      = Color3.fromRGB(255, 80, 160),

    -- 特殊移动 (补充)
    SB_Fly           = false,
    SB_FlySpeed      = 80,
    SB_Noclip        = false,
    SB_InfJump       = false,

    -- 杂项
    SB_AntiAFK       = false,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. RUNTIME HANDLES
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false

local mainConn, noclipConn, infJumpConn, flyConn, idledConn,
      charAddedConn, espConn, voidConn, freezeConn, inputConn
local flyBV, flyBG
local espFolder, espObjects = nil, {}
local lastSafeCFrame = nil

local hitRemote, abilityRemote = nil, nil
local auraState = { parts = {}, glove = nil, originalSize = nil, active = false }
local speedRenamed = false
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

-- ══════════════════════════════════════════════════════════════════
-- 6. 远程获取 (源码用 b, 回退 GeneralHit, 再回退动态扫)
--    签名: hitRemote:FireServer(hitPart)  (hitPart = 受害者身上的 BasePart)
-- ══════════════════════════════════════════════════════════════════
local function findHitRemoteStatic()
    -- 源码明确用 ReplicatedStorage.b, 优先; 当前版本另有 GeneralHit
    local candidates = { "b", "GeneralHit", "Hit", "Slap" }
    for _, n in ipairs(candidates) do
        local r = ReplicatedStorage:FindFirstChild(n)
        if r and r:IsA("RemoteEvent") then
            return r
        end
    end
    return nil
end

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
-- 7. GOD MODE (源码原样: 删角色上的布娃娃/受击判定实例)
-- ══════════════════════════════════════════════════════════════════
local function doGodMode()
    local char = getChar()
    if not char then
        notify("God Mode", "角色不存在", 2, "Warning")
        return
    end
    local rag = char:FindFirstChild("Ragdolled")
    local isInArena = char:FindFirstChild("isInArena")
    if rag and isInArena then
        -- 源码要求: isInArena.Value == true 才能开 (必须先进入岛屿)
        local inArena = false
        pcall(function() inArena = (isInArena:IsA("BoolValue") and isInArena.Value == true) end)
        if inArena then
            pcall(function() rag:Destroy() end)
            pcall(function() isInArena:Destroy() end)
            pcall(function()
                local t = char:FindFirstChild("TSVulnerability")
                if t then t:Destroy() end
            end)
            pcall(function()
                local i = char:FindFirstChild("IsInDefaultArena")
                if i then i:Destroy() end
            end)
            notify("God Mode", "已开启 (布娃娃/受击判定已移除)", 3, "Success")
        else
            notify("God Mode", "需先进入岛屿才能开 God Mode", 3, "Warning")
        end
    else
        notify("God Mode", "未检测到 arena 标记, 请先进入岛屿", 3, "Warning")
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 8. KILL AURA (源码原样: 删 LocalScript + 放大手套 + 焊透明部件 + Touched)
-- ══════════════════════════════════════════════════════════════════
local function disableKillAura()
    for _, p in ipairs(auraState.parts) do
        pcall(function() p:Destroy() end)
    end
    auraState.parts = {}
    if auraState.glove and auraState.originalSize then
        pcall(function() auraState.glove.Size = auraState.originalSize end)
    end
    auraState.active = false
    auraState.glove = nil
    auraState.originalSize = nil
end

local function enableKillAura()
    local char = getChar()
    if not char then
        notify("Kill Aura", "角色不存在", 2, "Warning")
        return false
    end
    -- 删掉角色里除 Animate 外的所有 LocalScript (关掉手套自身冷却逻辑)
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("LocalScript") and v.Name ~= "Animate" then
            pcall(function() v:Destroy() end)
        end
    end

    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then
        notify("Kill Aura", "需要装备手套(Tool)才能开", 2, "Warning")
        return false
    end

    local glove = tool:FindFirstChild("Glove")
    if glove then
        auraState.glove = glove
        auraState.originalSize = glove.Size
        pcall(function() glove.Size = Vector3.new(30, 30, 30) end)
        pcall(function() glove.Massless = true end)
    end

    -- 焊一个 30³ 透明 neon 部件到手套, 靠 Touched 触发拍击
    local pt = Instance.new("Part")
    pt.Anchored = true
    pt.Parent = tool
    pt.Size = Vector3.new(30, 30, 30)
    if glove then pcall(function() pt.CFrame = glove.CFrame end) end
    local wd = Instance.new("WeldConstraint", pt)
    wd.Part0 = glove or tool
    wd.Part1 = pt
    pt.CanCollide = false
    pt.Transparency = 0.6
    pt.Material = Enum.Material.Neon
    pt.Anchored = false
    pt.CastShadow = false
    pt.Massless = true
    auraState.parts[#auraState.parts + 1] = pt

    local cool = false
    pt.Touched:Connect(function(hit)
        if isDestroyed or not auraState.active then return end
        if hit and hit.Parent then
            local parent = hit.Parent
            if parent:FindFirstChild("Humanoid") and parent ~= char then
                -- 跳过带 Reverse 的玩家 (互相拍会被反)
                if parent:FindFirstChild("Reverse") == nil then
                    if not cool then
                        cool = true
                        local rem = hitRemote or ReplicatedStorage:FindFirstChild("b")
                        pcall(function() rem:FireServer(hit) end)
                        cool = false
                    end
                end
            end
        end
    end)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.Died:Connect(function()
            auraState.active = false
        end)
    end

    auraState.active = true
    return true
end

local function setKillAura(enabled)
    if enabled then
        if auraState.active then return end
        local ok = enableKillAura()
        if not ok then
            -- 没装备手套, 回退开关
            SETTINGS.SB_KillAura = false
            if Window and Window.Flags and Window.Flags["SB_KillAura"] then
                pcall(function() Window.Flags["SB_KillAura"]:Set(false) end)
            end
        end
    else
        disableKillAura()
        notify("Kill Aura", "已关闭 (被删的 LocalScript 需重生才恢复)", 3, "Info")
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 移动 (源码: Speed 改名绕过 + Jump + Gravity; 补充 Fly/Noclip/InfJump)
-- ══════════════════════════════════════════════════════════════════
local function applySpeed()
    local hum = getHum()
    if not hum then return end
    if not speedRenamed then
        pcall(function() hum.Name = "_ _ _" end)
        speedRenamed = true
    end
    pcall(function() hum.WalkSpeed = SETTINGS.SB_Speed end)
end

local function movementStep()
    if isDestroyed then return end
    local hum = getHum()
    if not hum then return end

    if SETTINGS.SB_SpeedEnabled then
        applySpeed()
    else
        if speedRenamed then
            pcall(function() hum.WalkSpeed = 16 end)
        end
    end

    if SETTINGS.SB_JumpEnabled then
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = SETTINGS.SB_Jump
        end)
    end

    if SETTINGS.SB_GravityEnabled then
        pcall(function() Workspace.Gravity = SETTINGS.SB_Gravity end)
    elseif Workspace.Gravity ~= 196 then
        pcall(function() Workspace.Gravity = 196 end)
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
-- 10. NO TIME FREEZE (源码: 角色被锚定时自动解除)
-- ══════════════════════════════════════════════════════════════════
local function toggleNoTimeFreeze(enabled)
    if freezeConn then freezeConn:Disconnect() freezeConn = nil end
    if not enabled then return end
    freezeConn = LocalPlayer.CharacterAdded:Connect(function(char)
        local conn
        conn = char.Changed:Connect(function()
            if isDestroyed or not SETTINGS.SB_NoTimeFreeze then
                if conn then pcall(function() conn:Disconnect() end) end
                return
            end
            for _, v in ipairs(char:GetChildren()) do
                if v:IsA("BasePart") then
                    pcall(function() v.Anchored = false end)
                end
            end
        end)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 传送 (源码硬编码 CFrame + 按名字传送到玩家)
-- ══════════════════════════════════════════════════════════════════
local TP_STARTER = CFrame.new(122.187042, 359.984283, -0.974518955, -0.0461894758, -2.20339125e-09, -0.998932719, -1.18904417e-07, 1, 3.29225514e-09, 0.998932719, 1.18929577e-07, -0.0461894758)
local TP_PRO     = CFrame.new(53.2623177, -5.17293787, -6.4983449, 0.988194346, -4.27591935e-08, -0.153205544, 3.84768093e-08, 1, -3.09168371e-08, 0.153205544, 2.4656984e-08, 0.988194346)
local TP_LOBBY   = CFrame.new(-353.03006, 326.234283, -1.99629986, 0.293333888, 2.33903688e-08, 0.956010044, 5.62207632e-08, 1, -4.17169481e-08, -0.956010044, 6.5984608e-08, 0.293333888)

local function tpCFrame(cf)
    local char = getChar()
    if not char then return false end
    local ok = pcall(function() char:SetPrimaryPartCFrame(cf) end)
    if not ok then
        local root = getRoot()
        if root then pcall(function() root.CFrame = cf end) end
    end
    return true
end

local function tpToPlayer(name)
    if not name or name == "" then
        notify("Tp", "请先选择/输入玩家", 2, "Warning")
        return
    end
    local target = Players:FindFirstChild(name)
    if not target or not target.Character then
        notify("Tp", "找不到玩家: " .. tostring(name), 2, "Error")
        return
    end
    local tr = target.Character:FindFirstChild("HumanoidRootPart") or target.Character.PrimaryPart
    local root = getRoot()
    if tr and root then
        local off = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
        pcall(function() root.CFrame = CFrame.new(tr.Position + off) end)
        notify("Tp", "已传送到 " .. name, 2, "Success")
    else
        notify("Tp", "传送失败", 2, "Error")
    end
end

local function forceReset()
    local char = getChar()
    if not char then return end
    local db = Workspace:FindFirstChild("DEATHBARRIER")
    if db then
        pcall(function() char:MoveTo(db.Position) end)
        notify("Force Reset", "已瞬移到 DEATHBARRIER (强制重生)", 2, "Info")
    else
        pcall(function() char:BreakJoints() end)
        notify("Force Reset", "无 DEATHBARRIER, 直接解体", 2, "Info")
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 12. 生存: Anti-Void / 自动重装手套
-- ══════════════════════════════════════════════════════════════════
local function survivalStep()
    if isDestroyed then return end
    local root = getRoot()
    local hum = getHum()
    if not root then return end

    if hum and hum.Health > 0 and root.Position.Y > (SETTINGS.SB_SafeY or -20) + 5 then
        lastSafeCFrame = root.CFrame
    end

    if SETTINGS.SB_AntiVoid and lastSafeCFrame then
        if root.Position.Y < (SETTINGS.SB_SafeY or -20) then
            pcall(function() root.CFrame = lastSafeCFrame end)
        end
    end

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

-- ══════════════════════════════════════════════════════════════════
-- 13. ESP (BillboardGui 头顶名牌, 无需 Drawing)
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
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local char = p.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                if not espObjects[p] then makeEsp(p) end
                local data = espObjects[p]
                if data and data.label and root then
                    local part = char:FindFirstChild("HumanoidRootPart")
                    local d = math.floor((part.Position - root.Position).Magnitude)
                    data.label.Text = string.format("%s [%dm]", p.Name, d)
                end
            end
        end
    end
    for p, data in pairs(espObjects) do
        local char = p.Character
        if (not char) or (not char:FindFirstChild("HumanoidRootPart")) then
            pcall(function() if data.bg then data.bg:Destroy() end end)
            espObjects[p] = nil
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 14. 杂项工具
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

local function fireAbility()
    if not abilityRemote then return false end
    local ok = pcall(function() abilityRemote:FireServer() end)
    if not ok then ok = pcall(function() abilityRemote:Fire() end) end
    return ok
end

local function slapNearest()
    local root = getRoot()
    if not root then return false end
    local best, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local part = p.Character:FindFirstChild("HumanoidRootPart")
            if part then
                local d = (part.Position - root.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = part
                end
            end
        end
    end
    if best then
        local rem = hitRemote or ReplicatedStorage:FindFirstChild("b")
        local ok = pcall(function() rem:FireServer(best) end)
        if ok then slapCount = slapCount + 1 end
        return ok
    end
    return false
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
-- 15. 构建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title        = "Slap Battle",
    Subtitle     = "打耳光大战 v2.0 (源码移植)",
    ThemeColor   = Color3.fromRGB(255, 80, 160),
    Transparency = 0.3,
    Size         = UDim2.new(0, 640, 0, 620),
    Keybind      = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ── TAB 1: 战斗 (源码功能) ───────────────────────────────────────
local CombatTab = Window:AddTab({ Name = "战斗", Icon = "rbxassetid://6034287594" })

CombatTab:AddSection({ Name = "Kill Aura (源码: 放大手套+焊透明部件)" })

CombatTab:AddToggle({
    Name = "Kill Aura (大击杀盒)", Default = false, Flag = "SB_KillAura",
    Callback = function(s)
        SETTINGS.SB_KillAura = s
        setKillAura(s)
        if s then notify("Kill Aura", "已开启 (需装备手套)", 2, "Success") end
    end,
})

CombatTab:AddButton({
    Name = "God Mode (删布娃娃/受击判定)",
    Callback = function()
        doGodMode()
    end,
})

CombatTab:AddSection({ Name = "手动" })

CombatTab:AddButton({
    Name = "拍最近的人 (E)",
    Callback = function()
        local ok = slapNearest()
        notify("Slap", ok and "已拍击最近目标" or "无目标 / 远程不可用", 2, ok and "Success" or "Warning")
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

-- ── TAB 2: 移动 (源码功能) ───────────────────────────────────────
local MoveTab = Window:AddTab({ Name = "移动", Icon = "rbxassetid://6034466796" })

MoveTab:AddSection({ Name = "Speed (源码: 改名绕过)" })

MoveTab:AddToggle({
    Name = "Speed 开启", Default = false, Flag = "SB_SpeedEnabled",
    Callback = function(s) SETTINGS.SB_SpeedEnabled = s end,
})

MoveTab:AddSlider({
    Name = "Speed 数值", Min = 16, Max = 200, Default = 50, Increment = 1,
    Suffix = "", Flag = "SB_Speed",
    Callback = function(v) SETTINGS.SB_Speed = v end,
})

MoveTab:AddSection({ Name = "JumpPower" })

MoveTab:AddToggle({
    Name = "JumpPower 开启", Default = false, Flag = "SB_JumpEnabled",
    Callback = function(s) SETTINGS.SB_JumpEnabled = s end,
})

MoveTab:AddSlider({
    Name = "JumpPower 数值", Min = 50, Max = 300, Default = 100, Increment = 1,
    Suffix = "", Flag = "SB_Jump",
    Callback = function(v) SETTINGS.SB_Jump = v end,
})

MoveTab:AddSection({ Name = "Gravity" })

MoveTab:AddToggle({
    Name = "Gravity 开启", Default = false, Flag = "SB_GravityEnabled",
    Callback = function(s)
        SETTINGS.SB_GravityEnabled = s
        if not s then pcall(function() Workspace.Gravity = 196 end) end
    end,
})

MoveTab:AddSlider({
    Name = "Gravity 数值", Min = 0, Max = 500, Default = 196, Increment = 1,
    Suffix = "", Flag = "SB_Gravity",
    Callback = function(v) SETTINGS.SB_Gravity = v end,
})

MoveTab:AddToggle({
    Name = "No TimeFreeze (解除锚定)", Default = false, Flag = "SB_NoTimeFreeze",
    Callback = function(s)
        SETTINGS.SB_NoTimeFreeze = s
        toggleNoTimeFreeze(s)
        notify("No TimeFreeze", s and "已开启" or "已关闭", 2, "Info")
    end,
})

MoveTab:AddSection({ Name = "特殊移动 (补充)" })

MoveTab:AddToggle({
    Name = "穿墙", Default = false, Flag = "SB_Noclip",
    Callback = function(s)
        SETTINGS.SB_Noclip = s
        toggleNoclip(s)
        notify("NoClip", s and "ON" or "OFF", 1.5, "Info")
    end,
})

MoveTab:AddToggle({
    Name = "无限跳", Default = false, Flag = "SB_InfJump",
    Callback = function(s)
        SETTINGS.SB_InfJump = s
        toggleInfJump(s)
    end,
})

MoveTab:AddToggle({
    Name = "飞行", Default = false, Flag = "SB_Fly",
    Callback = function(s)
        SETTINGS.SB_Fly = s
        toggleFly(s, SETTINGS.SB_FlySpeed)
        notify("Fly", s and "ON" or "OFF", 1.5, "Info")
    end,
})

MoveTab:AddSlider({
    Name = "飞行速度", Min = 20, Max = 300, Default = 80, Increment = 5,
    Suffix = "", Flag = "SB_FlySpeed",
    Callback = function(v) SETTINGS.SB_FlySpeed = v end,
})

-- ── TAB 3: 传送 (源码硬编码点 + 按名传) ─────────────────────────
local TpTab = Window:AddTab({ Name = "传送", Icon = "rbxassetid://6035153470" })

TpTab:AddSection({ Name = "固定地点 (源码 CFrame)" })

TpTab:AddButton({
    Name = "传送到 Starter Island",
    Callback = function() tpCFrame(TP_STARTER) notify("Tp", "Starter Island", 2, "Success") end,
})

TpTab:AddButton({
    Name = "传送到 Pro Island",
    Callback = function() tpCFrame(TP_PRO) notify("Tp", "Pro Island", 2, "Success") end,
})

TpTab:AddButton({
    Name = "传送到 Lobby",
    Callback = function() tpCFrame(TP_LOBBY) notify("Tp", "Lobby", 2, "Success") end,
})

TpTab:AddSection({ Name = "传送到玩家" })

local playerDropdown = TpTab:AddDropdown({
    Name = "玩家列表", Items = refreshPlayerList(), Flag = "SB_SelectedPlayer",
    Callback = function(v) selectedPlayer = v end,
})

TpTab:AddButton({
    Name = "刷新玩家列表",
    Callback = function()
        local items = refreshPlayerList()
        if playerDropdown and playerDropdown.Refresh then
            pcall(function() playerDropdown:Refresh(items) end)
        end
        notify("SlapBattle", "共 " .. #items .. " 名其他玩家", 2, "Info")
    end,
})

TpTab:AddButton({
    Name = "传送到选中玩家",
    Callback = function() tpToPlayer(selectedPlayer) end,
})

TpTab:AddSection({ Name = "重置" })

TpTab:AddButton({
    Name = "Force Reset (瞬移 DEATHBARRIER 重生)",
    Callback = function() forceReset() end,
})

-- ── TAB 4: 生存 ─────────────────────────────────────────────────
local SurviveTab = Window:AddTab({ Name = "生存", Icon = "rbxassetid://6034466796" })

SurviveTab:AddToggle({
    Name = "Anti-Void (掉虚空自动拉回)", Default = false, Flag = "SB_AntiVoid",
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

SurviveTab:AddToggle({
    Name = "自动重新装备手套", Default = false, Flag = "SB_AutoReGlove",
    Callback = function(s) SETTINGS.SB_AutoReGlove = s end,
})

-- ── TAB 5: 玩家 ─────────────────────────────────────────────────
local PlayerTab = Window:AddTab({ Name = "玩家", Icon = "rbxassetid://6035153470" })

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

-- ── TAB 6: 杂项 ─────────────────────────────────────────────────
local MiscTab = Window:AddTab({ Name = "杂项", Icon = "rbxassetid://6031280882" })

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
    Title = "Slap Battle v2.0 (源码移植)",
    Content = table.concat({
        "PlaceId: 6403373529",
        "",
        "功能全部移植自 flamingrobot 的 Slap GUI",
        "(By Mr.Exploit), 仅替换显示层为 QuantumUI:",
        "  • God Mode: 删 Ragdolled/isInArena/TSVulnerability/",
        "    IsInDefaultArena (需先进岛屿)",
        "  • Kill Aura: 删角色 LocalScript(除 Animate) + 手套放大",
        "    30³ + 焊透明 neon 部件, Touched → b:FireServer(hit)",
        "  • Speed: 改 Humanoid 名为 '_ _ _' 绕过 + 设 WalkSpeed",
        "  • JumpPower / Gravity / No TimeFreeze(解除锚定)",
        "  • Tp Starter/Pro/Lobby (源码硬编码 CFrame)",
        "  • Tp to Player (按名) / Force Reset (DEATHBARRIER)",
        "",
        "补充: ESP / 飞行 / 穿墙 / 无限跳 / Anti-Void / 防挂机",
        "",
        "快捷键: E=拍最近  T=放技能  RightShift=UI",
    }, "\n"),
})

-- ══════════════════════════════════════════════════════════════════
-- 16. 快捷键
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
-- 17. 主循环
-- ══════════════════════════════════════════════════════════════════
charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if isDestroyed then return end
    speedRenamed = false
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
    pcall(movementStep)
    pcall(survivalStep)
    pcall(updateESP)
end)

-- ══════════════════════════════════════════════════════════════════
-- 18. 清理
-- ══════════════════════════════════════════════════════════════════
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    local conns = {
        inputConn, charAddedConn, mainConn, noclipConn,
        infJumpConn, flyConn, idledConn, espConn, voidConn, freezeConn,
    }
    for _, c in ipairs(conns) do
        if c then pcall(function() c:Disconnect() end) end
    end

    if flyBV then pcall(function() flyBV:Destroy() end) end
    if flyBG then pcall(function() flyBG:Destroy() end) end

    disableKillAura()

    clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end

    pcall(function() Workspace.Gravity = 196 end)

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
notify("Slap Battle v2.0", "Slap Battle 辅助已加载 (源码移植)\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[SlapBattle] v2.0 (PlaceId: %d) 加载完成 | Drawing: %s",
    game.PlaceId, hasDrawing and "可用" or "不可用(不影响功能)"))
