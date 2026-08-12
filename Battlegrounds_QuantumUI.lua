--[[
    The Strongest Battlegrounds 辅助脚本 v2.0 (Quantum UI 版)
    基于 NexamTSB (helldevelopment/RobloxScripts) 真实源码结构重写

    适配 PlaceId: 10449761463  GameId: 3808081382

    游戏真实内部结构 (源码还原):
      LocalPlayer.Character.Communicate:FireServer()  — 所有技能/操作入口
        Goal="Console Move"  + Tool/ToolName  → 使用技能 (从 Backpack 取 Tool)
        Goal="KeyPress"      + Key            → 按键 (G=终极/觉醒)
        Goal="LeftClick" / "LeftClickRelease" → M1 普攻
      LocalPlayer:GetAttribute("Ultimate")            — 终极条 (0~100)
      LocalPlayer.PlayerGui.Hotbar.Backpack.Hotbar    — 技能栏 (读取可用技能/冷却)
      v:GetAttribute("Kills")                          — 目标选择: 击杀数越少越优先

    功能:
      [战斗] Attack Aura / Auto Combo / Auto Ultimate / Auto Block
      [农场] Kill Farm / Auto Reset (低血量重置) / Auto Ultimate
      [移动] WalkSpeed / JumpPower / InfJump / NoClip / Fly / NoStun / NoRagdoll
      [视觉] 玩家ESP(高亮+血量+距离) / 全亮
      [服务器] Rejoin / Server Hop   [杂项] Anti-AFK / 坐标

    安全承诺: 不采集任何信息，不 loadstring 外部功能代码，所有逻辑本地实现。
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD
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
-- 1. LOAD LIBRARY
-- ══════════════════════════════════════════════════════════════════
local success, QuantumUI = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"))()
end)

if not success then
    warn("[TSB] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[TSB] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[TSB] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[TSB] Quantum UI v" .. tostring(QuantumUI.Version) .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. ROBLOX SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local Workspace = workspace
local Lighting = game:GetService("Lighting")

-- ══════════════════════════════════════════════════════════════════
-- 3. SETTINGS (与 NEXTAM 配置结构一致, 用于 Config 保存/加载)
-- ══════════════════════════════════════════════════════════════════
local SETTINGS = {
    -- 战斗
    TSB_AttackAura = false,
    TSB_AuraRange = 5,
    TSB_AutoCombo = false,
    TSB_AutoUltimate = false,
    TSB_AutoBlock = false,

    -- 农场
    TSB_KillFarm = false,
    TSB_AutoReset = false,
    TSB_AutoResetHP = 20,

    -- 移动
    TSB_WalkSpeed = false,
    TSB_WalkSpeedValue = 16,
    TSB_JumpPower = false,
    TSB_JumpPowerValue = 50,
    TSB_InfJump = false,
    TSB_NoClip = false,
    TSB_Fly = false,
    TSB_FlySpeed = 80,
    TSB_NoStun = false,
    TSB_NoRagdoll = false,
    TSB_NoDashCooldown = false,

    -- 视觉
    ESP_Player = false,
    ESP_PlayerColor = Color3.fromRGB(0, 200, 255),
    ESP_Health = false,
    ESP_Distance = true,
    ESP_Refresh = 0.1,
    TSB_Fullbright = false,

    -- 杂项
    TSB_AntiAFK = false,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 全局变量
-- ══════════════════════════════════════════════════════════════════
local Window = nil
local isDestroyed = false
local Humanoid = nil

local auraConn, comboConn, blockConn, walkConn, jumpConn
local infJumpConn, noclipConn, flyConn, noStunConn, noRagdollConn, noDashConn
local farmConn, espConn, aimConn, antiAFKConn
local flyBV, flyBG
local espFolder
local savedLighting = {}
local blockHeld = false

-- ══════════════════════════════════════════════════════════════════
-- 5. 通知辅助函数
-- ══════════════════════════════════════════════════════════════════
local function notify(title, content, duration, ntype)
    if Window then
        pcall(function()
            Window:Notify({
                Title    = title,
                Content  = content,
                Duration = duration or 3,
                Type     = ntype or "Info"
            })
        end)
    else
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title, Text = content, Duration = duration or 3
            })
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 6. 工具函数 (角色/状态)
-- ══════════════════════════════════════════════════════════════════
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
local function getCommunicate()
    local c = getChar()
    return c and c:FindFirstChild("Communicate")
end

-- ══════════════════════════════════════════════════════════════════
-- 7. 真实游戏操作函数 (源码还原自 NexamTSB)
--    Communicate:FireServer 是 TSB 唯一技能/操作入口
-- ══════════════════════════════════════════════════════════════════

-- 使用指定技能 (从 Backpack 找到对应 Tool)
local function UseAbility(Ability)
    local Com = getCommunicate()
    if not Com then return end
    local Tool = LocalPlayer.Backpack:FindFirstChild(Ability)
    local Arguments = {
        [1] = {
            ["Tool"] = Tool,
            ["Goal"] = "Console Move",
            ["ToolName"] = tostring(Ability)
        }
    }
    pcall(function() Com:FireServer(unpack(Arguments)) end)
end

-- 读取技能栏, 返回一个可用的技能名 (无冷却且可见)
local function RandomAbility()
    local hotbar = LocalPlayer.PlayerGui and LocalPlayer.PlayerGui:FindFirstChild("Hotbar")
    if not hotbar then return nil end
    local backpack = hotbar:FindFirstChild("Backpack")
    if not backpack then return nil end
    local hb = backpack:FindFirstChild("Hotbar")
    if not hb then return nil end
    local Abilities = {}
    local NotEmpty = false
    for _, v in ipairs(hb:GetChildren()) do
        if v.ClassName ~= "UIListLayout" and v and v.Visible then
            local base = v:FindFirstChild("Base")
            if base then
                local toolName = base:FindFirstChild("ToolName")
                local toolText = toolName and toolName.Text or ""
                if toolText ~= "N/A" then
                    if not base:FindFirstChild("Cooldown") then
                        table.insert(Abilities, toolText)
                        NotEmpty = true
                    end
                end
            end
        end
    end
    if NotEmpty then
        return Abilities[math.random(1, #Abilities)]
    end
    return nil
end

-- 数据绑定能力: 读取 hotbar 中第一个可用技能名 (用于 AutoCombo 依次释放)
local function GetAllReadyAbilities()
    local hotbar = LocalPlayer.PlayerGui and LocalPlayer.PlayerGui:FindFirstChild("Hotbar")
    if not hotbar then return {} end
    local backpack = hotbar:FindFirstChild("Backpack")
    if not backpack then return {} end
    local hb = backpack:FindFirstChild("Hotbar")
    if not hb then return {} end
    local result = {}
    for _, v in ipairs(hb:GetChildren()) do
        if v.ClassName ~= "UIListLayout" and v and v.Visible then
            local base = v:FindFirstChild("Base")
            if base then
                local toolName = base:FindFirstChild("ToolName")
                local toolText = toolName and toolName.Text or ""
                if toolText ~= "N/A" and not base:FindFirstChild("Cooldown") then
                    table.insert(result, toolText)
                end
            end
        end
    end
    return result
end

-- 触发终极/觉醒 (G 键)
local function ActivateUltimate()
    local Com = getCommunicate()
    if not Com then return end
    local Arguments = {
        [1] = {
            ["MoveDirection"] = Vector3.new(0, 0, 0),
            ["Key"] = Enum.KeyCode.G,
            ["Goal"] = "KeyPress"
        }
    }
    pcall(function() Com:FireServer(unpack(Arguments)) end)
end

-- M1 普攻 (可选 2 秒后释放左键)
local function Hit(Release)
    local Com = getCommunicate()
    if not Com then return end
    local Arguments = { [1] = { ["Goal"] = "LeftClick" } }
    pcall(function() Com:FireServer(unpack(Arguments)) end)
    if Release then
        delay(2, function()
            local Com2 = getCommunicate()
            if not Com2 then return end
            local Arguments2 = { [1] = { ["Goal"] = "LeftClickRelease" } }
            pcall(function() Com2:FireServer(unpack(Arguments2)) end)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 目标选择 (源码还原: 击杀数越少越优先)
-- ══════════════════════════════════════════════════════════════════
local function BestTarget(MaxDistance)
    local Target = nil
    MaxDistance = MaxDistance or math.huge
    local MaxKills = math.huge
    local myRoot = getRoot()
    if not myRoot then return nil end
    for _, v in ipairs(Players:GetPlayers()) do
        if v ~= LocalPlayer then
            local vChar = v.Character
            if vChar then
                local vHum = vChar:FindFirstChildOfClass("Humanoid")
                local vHRP = vChar:FindFirstChild("HumanoidRootPart")
                if vHum and vHRP and vHum.Health > 0 then
                    local myHum = getHum()
                    if myHum then
                        local Distance = (myRoot.Position - vHRP.Position).Magnitude
                        local kills = v:GetAttribute("Kills") or 0
                        if Distance < MaxDistance and kills < MaxKills then
                            MaxDistance = Distance
                            Target = v
                            MaxKills = kills
                        end
                    end
                end
            end
        end
    end
    return Target
end

local function FaceTarget(target)
    if not target or not target.Character then return end
    local tHRP = target.Character:FindFirstChild("HumanoidRootPart")
    local myRoot = getRoot()
    if not tHRP or not myRoot then return end
    local predicted = tHRP.Position + tHRP.Velocity * 0.2
    local dir = (predicted - myRoot.Position).Unit
    pcall(function()
        myRoot.CFrame = CFrame.new(myRoot.Position, myRoot.Position + dir)
    end)
end

local function TeleportToPlayer(player, offset, method)
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    local myRoot = getRoot()
    if not myRoot then return end
    if offset == nil then
        pcall(function()
            LocalPlayer.Character:SetPrimaryPartCFrame(character.HumanoidRootPart.CFrame)
        end)
    elseif offset == true then
        if method == "Behind" then
            pcall(function()
                LocalPlayer.Character:SetPrimaryPartCFrame(
                    CFrame.new(player.Character.HumanoidRootPart.Position - Vector3.new(0, 3, 0) + player.Character.Head.CFrame.lookVector * -5)
                )
            end)
        elseif method == "Above" then
            pcall(function()
                myRoot.CFrame = CFrame.new(player.Character.HumanoidRootPart.Position + Vector3.new(0, 5, 0))
            end)
        else
            pcall(function()
                LocalPlayer.Character:SetPrimaryPartCFrame(character.HumanoidRootPart.CFrame)
            end)
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 战斗功能 (源码还原)
-- ══════════════════════════════════════════════════════════════════

-- Attack Aura: 范围内自动出招 (随机技能, 无技能则 M1)
local function toggleAttackAura(enabled)
    if auraConn then auraConn:Disconnect() auraConn = nil end
    if enabled then
        auraConn = RunService.RenderStepped:Connect(function()
            if isDestroyed then return end
            local target = BestTarget(SETTINGS.TSB_AuraRange or 5)
            if target then
                FaceTarget(target)
                local ability = RandomAbility()
                if ability then
                    UseAbility(ability)
                else
                    Hit(true)
                end
            end
        end)
    end
end

-- Auto Combo: 依次释放所有可用技能 + 终极
local function toggleAutoCombo(enabled)
    if comboConn then comboConn:Disconnect() comboConn = nil end
    if enabled then
        comboConn = RunService.RenderStepped:Connect(function()
            if isDestroyed then return end
            local target = BestTarget(SETTINGS.TSB_AuraRange or 5)
            if not target then return end
            FaceTarget(target)
            if SETTINGS.TSB_AutoUltimate then
                local ult = LocalPlayer:GetAttribute("Ultimate") or 0
                if ult >= 100 then ActivateUltimate() end
            end
            local abils = GetAllReadyAbilities()
            if #abils > 0 then
                UseAbility(abils[1])
            else
                Hit(true)
            end
        end)
    end
end

-- Auto Block: 附近敌人面向自己时按住 F 格挡
local vim = game:GetService("VirtualInputManager")
local function pressBlock(hold)
    if blockHeld == hold then return end
    blockHeld = hold
    pcall(function()
        if hold then
            if keypress then keypress(Enum.KeyCode.F) return end
            if vim then vim:SendKeyEvent(true, Enum.KeyCode.F, false, game) end
        else
            if keyrelease then keyrelease(Enum.KeyCode.F) return end
            if vim then vim:SendKeyEvent(false, Enum.KeyCode.F, false, game) end
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
        local needBlock = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                local hum = player.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local dist = (myRoot.Position - hrp.Position).Magnitude
                    if dist <= 12 then
                        local dir = (myRoot.Position - hrp.Position).Unit
                        local dot = dir:Dot(hrp.CFrame.LookVector)
                        if dot > 0.7 then
                            needBlock = true
                            break
                        end
                    end
                end
            end
        end
        pressBlock(needBlock)
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 农场功能 (源码还原)
-- ══════════════════════════════════════════════════════════════════
local function toggleKillFarm(enabled)
    if farmConn then farmConn:Disconnect() farmConn = nil end
    if enabled then
        farmConn = RunService.RenderStepped:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if not hum then return end

            -- 低血量自动重置
            if SETTINGS.TSB_AutoReset and hum.Health > 0 then
                local hpPercent = (hum.Health / hum.MaxHealth) * 100
                if hpPercent <= (SETTINGS.TSB_AutoResetHP or 20) then
                    pcall(function() hum.Health = 0 end)
                    task.wait(2)
                    return
                end
            end

            -- 自动终极
            if SETTINGS.TSB_AutoUltimate then
                local ult = LocalPlayer:GetAttribute("Ultimate") or 0
                if ult >= 100 then ActivateUltimate() end
            end

            local target = BestTarget()
            if target then
                TeleportToPlayer(target)
                FaceTarget(target)
                local ability = RandomAbility()
                if ability then
                    UseAbility(ability)
                else
                    Hit(true)
                end
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 移动功能
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
    if enabled then
        infJumpConn = UserInputService.UserJumpRequest:Connect(function()
            local hum = getHum()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

local function toggleNoclip(enabled)
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if enabled then
        noclipConn = RunService.Stepped:Connect(function()
            if isDestroyed then return end
            local c = getChar()
            if not c then return end
            for _, part in ipairs(c:GetChildren()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = false end)
                end
            end
        end)
    end
end

local function toggleFly(enabled, speed)
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBV then pcall(function() flyBV:Destroy() end) flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end) flyBG = nil end
    if enabled then
        local root = getRoot()
        if not root then return end
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        flyBV.Velocity = Vector3.zero
        flyBV.Parent = root
        flyBG = Instance.new("BodyGyro")
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
end

local function toggleNoStun(enabled)
    if noStunConn then noStunConn:Disconnect() noStunConn = nil end
    if enabled then
        noStunConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if hum then
                pcall(function()
                    if hum:GetState() == Enum.HumanoidStateType.Stunned then
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                end)
            end
        end)
    end
end

local function toggleNoRagdoll(enabled)
    if noRagdollConn then noRagdollConn:Disconnect() noRagdollConn = nil end
    if enabled then
        noRagdollConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            local hum = getHum()
            if hum then
                pcall(function()
                    if hum:GetState() == Enum.HumanoidStateType.Ragdoll
                    or hum:GetState() == Enum.HumanoidStateType.FallingDown then
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                end)
            end
        end)
    end
end

local function toggleNoDashCooldown(enabled)
    if noDashConn then noDashConn:Disconnect() noDashConn = nil end
    if enabled then
        noDashConn = RunService.Heartbeat:Connect(function()
            if isDestroyed then return end
            pcall(function()
                local c = getChar()
                if c then
                    for _, v in ipairs(c:GetDescendants()) do
                        local name = string.lower(v.Name)
                        if (v:IsA("NumberValue") or v:IsA("IntValue")) and string.find(name, "dash") then
                            v.Value = 0
                        end
                        if v:IsA("BoolValue") and string.find(name, "dash") and string.find(name, "cd") then
                            v.Value = false
                        end
                    end
                end
            end)
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 12. ESP 功能
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    if espFolder then
        pcall(function() espFolder:Destroy() end)
        espFolder = nil
    end
end

local function createHighlight(parent, color)
    local hl = Instance.new("Highlight")
    hl.Name = "TSB_ESP_HL"
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0.2
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = parent
    return hl
end

local function createBillboard(parent, text, color, yOffset)
    local bb = Instance.new("BillboardGui")
    bb.Name = "TSB_ESP_BB"
    bb.Size = UDim2.new(0, 200, 0, 26)
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

local function runESPLoop()
    if not espFolder then
        espFolder = Instance.new("Folder")
        espFolder.Name = "TSB_ESP_Folder"
        espFolder.Parent = CoreGui
    end
    local myRoot = getRoot()

    local function cleanObj(obj)
        pcall(function()
            for _, c in ipairs(obj:GetChildren()) do
                if c.Name == "TSB_ESP_HL" or c.Name == "TSB_ESP_BB" then
                    c:Destroy()
                end
            end
        end)
    end

    if SETTINGS.ESP_Player or SETTINGS.ESP_Health or SETTINGS.ESP_Distance then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local char = p.Character
                local hum = char:FindFirstChildOfClass("Humanoid")
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 then
                    cleanObj(char)
                    local color = SETTINGS.ESP_PlayerColor
                    local distText = ""
                    if myRoot then
                        local dist = (myRoot.Position - hrp.Position).Magnitude
                        distText = string.format(" [%dm]", math.floor(dist))
                    end
                    local hpText = ""
                    if SETTINGS.ESP_Health then
                        hpText = string.format(" HP:%d", math.floor(hum.Health))
                    end
                    local name = p.Name .. hpText
                    if SETTINGS.ESP_Distance then name = name .. distText end
                    if SETTINGS.ESP_Player or SETTINGS.ESP_Health then
                        pcall(function()
                            createHighlight(char, color)
                            createBillboard(char, name, color, 4)
                        end)
                    end
                end
            end
        end
    end
end

local function toggleESP(enabled)
    if espConn then espConn:Disconnect() espConn = nil end
    if enabled then
        local lastRefresh = 0
        espConn = RunService.RenderStepped:Connect(function()
            if isDestroyed then return end
            local now = tick()
            if now - lastRefresh >= (SETTINGS.ESP_Refresh or 0.1) then
                lastRefresh = now
                pcall(runESPLoop)
            end
        end)
    else
        clearESP()
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 13. 视觉功能
-- ══════════════════════════════════════════════════════════════════
local function toggleFullbright(enabled)
    if enabled then
        if not savedLighting.brightness then
            savedLighting.brightness = Lighting.Brightness
            savedLighting.fogEnd = Lighting.FogEnd
            savedLighting.clockTime = Lighting.ClockTime
            savedLighting.globalShadows = Lighting.GlobalShadows
        end
        Lighting.Brightness = 4
        Lighting.FogEnd = 100000
        Lighting.ClockTime = 12
        Lighting.GlobalShadows = false
    else
        Lighting.Brightness = savedLighting.brightness or 1
        Lighting.FogEnd = savedLighting.fogEnd or 500
        Lighting.ClockTime = savedLighting.clockTime or 14
        Lighting.GlobalShadows = savedLighting.globalShadows ~= nil and savedLighting.globalShadows or true
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 14. 杂项
-- ══════════════════════════════════════════════════════════════════
local function rejoin()
    pcall(function()
        if #Players:GetPlayers() <= 1 then
            LocalPlayer:Kick("Rejoining...")
            task.wait(1)
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
    local GC = getconnections or get_signal_cons
    if GC then
        for _, v in pairs(GC(LocalPlayer.Idled)) do
            if v["Disable"] then v["Disable"](v)
            elseif v["Disconnect"] then v["Disconnect"](v) end
        end
    else
        if antiAFKConn then antiAFKConn:Disconnect() end
        antiAFKConn = LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 15. 创建 UI
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title      = "The Strongest Battlegrounds",
    Subtitle   = "最强战场 v2.0",
    ThemeColor = Color3.fromRGB(255, 80, 80),
    Transparency = 0.3,
    Size       = UDim2.new(0, 640, 0, 560),
    Keybind    = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- 确保 Humanoid 就绪
Humanoid = getHum()

-- ── TAB 1: 战斗 ──
local CombatTab = Window:AddTab({
    Name = "战斗",
    Icon = "rbxassetid://6034287594",
})

CombatTab:AddSection({ Name = "攻击" })

CombatTab:AddToggle({
    Name     = "Attack Aura (范围内自动出招)",
    Default  = false,
    Flag     = "TSB_AttackAura",
    Callback = function(s)
        SETTINGS.TSB_AttackAura = s
        toggleAttackAura(s)
        notify("TSB", s and "Attack Aura 已开启" or "Attack Aura 已关闭", 2, s and "Success" or "Info")
    end,
})

CombatTab:AddSlider({
    Name      = "Attack Aura 范围",
    Min       = 3, Max = 30, Default = 5, Increment = 1,
    Suffix    = " studs",
    Flag      = "TSB_AuraRange",
    Callback  = function(v) SETTINGS.TSB_AuraRange = v end,
})

CombatTab:AddToggle({
    Name     = "Auto Combo (自动连招+终极)",
    Default  = false,
    Flag     = "TSB_AutoCombo",
    Callback = function(s)
        SETTINGS.TSB_AutoCombo = s
        toggleAutoCombo(s)
    end,
})

CombatTab:AddToggle({
    Name     = "Auto Ultimate (终极条满自动开)",
    Default  = false,
    Flag     = "TSB_AutoUltimate",
    Callback = function(s) SETTINGS.TSB_AutoUltimate = s end,
})

CombatTab:AddSection({ Name = "防御" })

CombatTab:AddToggle({
    Name     = "Auto Block (自动格挡)",
    Default  = false,
    Flag     = "TSB_AutoBlock",
    Callback = function(s)
        SETTINGS.TSB_AutoBlock = s
        toggleAutoBlock(s)
    end,
})

-- ── TAB 2: 农场 ──
local FarmTab = Window:AddTab({
    Name = "农场",
    Icon = "rbxassetid://6031280882",
})

FarmTab:AddSection({ Name = "自动农场" })

FarmTab:AddToggle({
    Name     = "Kill Farm (传送+攻击+自动终极)",
    Default  = false,
    Flag     = "TSB_KillFarm",
    Callback = function(s)
        SETTINGS.TSB_KillFarm = s
        toggleKillFarm(s)
        notify("TSB", s and "Kill Farm 已开启" or "Kill Farm 已关闭", 2, s and "Success" or "Info")
    end,
})

FarmTab:AddSection({ Name = "自动重置" })

FarmTab:AddToggle({
    Name     = "Auto Reset (低血量自动重置)",
    Default  = false,
    Flag     = "TSB_AutoReset",
    Callback = function(s) SETTINGS.TSB_AutoReset = s end,
})

FarmTab:AddSlider({
    Name      = "重置血量阈值",
    Min       = 5, Max = 80, Default = 20, Increment = 5,
    Suffix    = "%",
    Flag      = "TSB_AutoResetHP",
    Callback  = function(v) SETTINGS.TSB_AutoResetHP = v end,
})

-- ── TAB 3: 移动 ──
local MoveTab = Window:AddTab({
    Name = "移动",
    Icon = "rbxassetid://6034466796",
})

MoveTab:AddSection({ Name = "基础移动" })

MoveTab:AddToggle({
    Name     = "WalkSpeed",
    Default  = false,
    Flag     = "TSB_WalkSpeed",
    Callback = function(s)
        SETTINGS.TSB_WalkSpeed = s
        toggleWalkSpeed(s)
    end,
})

MoveTab:AddSlider({
    Name      = "WalkSpeed 值",
    Min       = 16, Max = 200, Default = 35, Increment = 1,
    Flag      = "TSB_WalkSpeedValue",
    Callback  = function(v)
        SETTINGS.TSB_WalkSpeedValue = v
        if SETTINGS.TSB_WalkSpeed then toggleWalkSpeed(true) end
    end,
})

MoveTab:AddToggle({
    Name     = "JumpPower",
    Default  = false,
    Flag     = "TSB_JumpPower",
    Callback = function(s)
        SETTINGS.TSB_JumpPower = s
        toggleJumpPower(s)
    end,
})

MoveTab:AddSlider({
    Name      = "JumpPower 值",
    Min       = 50, Max = 200, Default = 100, Increment = 1,
    Flag      = "TSB_JumpPowerValue",
    Callback  = function(v)
        SETTINGS.TSB_JumpPowerValue = v
        if SETTINGS.TSB_JumpPower then toggleJumpPower(true) end
    end,
})

MoveTab:AddToggle({
    Name     = "InfJump (无限跳)",
    Default  = false,
    Flag     = "TSB_InfJump",
    Callback = function(s)
        SETTINGS.TSB_InfJump = s
        toggleInfJump(s)
    end,
})

MoveTab:AddSection({ Name = "特殊移动" })

MoveTab:AddToggle({
    Name     = "NoClip (穿墙)",
    Default  = false,
    Flag     = "TSB_NoClip",
    Callback = function(s)
        SETTINGS.TSB_NoClip = s
        toggleNoclip(s)
    end,
})

MoveTab:AddToggle({
    Name     = "Fly (飞行 WASD+Space/Ctrl)",
    Default  = false,
    Flag     = "TSB_Fly",
    Callback = function(s)
        SETTINGS.TSB_Fly = s
        toggleFly(s, SETTINGS.TSB_FlySpeed)
    end,
})

MoveTab:AddSlider({
    Name      = "Fly Speed",
    Min       = 10, Max = 300, Default = 80, Increment = 5,
    Flag      = "TSB_FlySpeed",
    Callback  = function(v)
        SETTINGS.TSB_FlySpeed = v
        if SETTINGS.TSB_Fly then toggleFly(true, v) end
    end,
})

MoveTab:AddSection({ Name = "状态防抗" })

MoveTab:AddToggle({
    Name     = "No Stun (防眩晕)",
    Default  = false,
    Flag     = "TSB_NoStun",
    Callback = function(s)
        SETTINGS.TSB_NoStun = s
        toggleNoStun(s)
    end,
})

MoveTab:AddToggle({
    Name     = "No Ragdoll (防布娃娃)",
    Default  = false,
    Flag     = "TSB_NoRagdoll",
    Callback = function(s)
        SETTINGS.TSB_NoRagdoll = s
        toggleNoRagdoll(s)
    end,
})

MoveTab:AddToggle({
    Name     = "No Dash Cooldown (无冲刺冷却)",
    Default  = false,
    Flag     = "TSB_NoDashCooldown",
    Callback = function(s)
        SETTINGS.TSB_NoDashCooldown = s
        toggleNoDashCooldown(s)
    end,
})

-- ── TAB 4: 视觉 ──
local VisualTab = Window:AddTab({
    Name = "视觉",
    Icon = "rbxassetid://6035153470",
})

VisualTab:AddSection({ Name = "ESP" })

VisualTab:AddToggle({
    Name     = "玩家 ESP (高亮)",
    Default  = false,
    Flag     = "TSB_ESPPlayer",
    Callback = function(s)
        SETTINGS.ESP_Player = s
        toggleESP(s or SETTINGS.ESP_Health)
    end,
})

VisualTab:AddToggle({
    Name     = "血量 ESP",
    Default  = false,
    Flag     = "TSB_ESPHealth",
    Callback = function(s)
        SETTINGS.ESP_Health = s
        toggleESP(s or SETTINGS.ESP_Player)
    end,
})

VisualTab:AddToggle({
    Name     = "显示距离",
    Default  = true,
    Flag     = "TSB_ESPDistance",
    Callback = function(s) SETTINGS.ESP_Distance = s end,
})

VisualTab:AddColorPicker({
    Name     = "ESP 颜色",
    Default  = Color3.fromRGB(0, 200, 255),
    Flag     = "TSB_PlayerColor",
    Callback  = function(c) SETTINGS.ESP_PlayerColor = c end,
})

VisualTab:AddButton({
    Name = "清除所有 ESP",
    Callback = function() clearESP() end,
})

VisualTab:AddSection({ Name = "世界" })

VisualTab:AddToggle({
    Name     = "全亮 (Fullbright)",
    Default  = false,
    Flag     = "TSB_Fullbright",
    Callback = function(s)
        SETTINGS.TSB_Fullbright = s
        toggleFullbright(s)
    end,
})

-- ── TAB 5: 服务器 ──
local ServerTab = Window:AddTab({
    Name = "服务器",
    Icon = "rbxassetid://6035032976",
})

ServerTab:AddSection({ Name = "服务器操作" })

ServerTab:AddButton({
    Name = "重新加入 (Rejoin)",
    Callback = function()
        notify("TSB", "正在重新加入...", 2, "Info")
        rejoin()
    end,
})

ServerTab:AddButton({
    Name = "服务器跳转 (Server Hop)",
    Callback = function()
        notify("TSB", "正在跳转服务器...", 2, "Info")
        serverHop()
    end,
})

-- ── TAB 6: 杂项 ──
local MiscTab = Window:AddTab({
    Name = "杂项",
    Icon = "rbxassetid://6031280882",
})

MiscTab:AddSection({ Name = "Anti-AFK" })

MiscTab:AddToggle({
    Name     = "Anti-AFK (防挂机踢出)",
    Default  = false,
    Flag     = "TSB_AntiAFK",
    Callback = function(s)
        SETTINGS.TSB_AntiAFK = s
        if s then setupAntiAFK() end
    end,
})

MiscTab:AddSection({ Name = "坐标" })

local coordsLabel = MiscTab:AddLabel({ Text = "X: 0.00  Y: 0.00  Z: 0.00" })
task.spawn(function()
    while not isDestroyed do
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root and coordsLabel then
            local p = root.Position
            coordsLabel:SetText(string.format("X: %.2f   Y: %.2f   Z: %.2f", p.X, p.Y, p.Z))
        end
        task.wait(0.1)
    end
end)

MiscTab:AddButton({
    Name = "复制当前坐标",
    Callback = function()
        local root = getRoot()
        if root then
            local p = root.Position
            local s = string.format("Vector3.new(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
            if setclipboard then
                setclipboard(s)
                notify("TSB", "已复制: " .. s, 2, "Success")
            end
        end
    end,
})

MiscTab:AddSection({ Name = "信息" })

MiscTab:AddParagraph({
    Title   = "The Strongest Battlegrounds v2.0",
    Content = table.concat({
        "基于 NexamTSB 真实源码结构重写",
        "PlaceId: 10449761463   GameId: 3808081382",
        "",
        "TSB 官方控制 (来自源码):",
        "  Communicate:FireServer 为唯一技能/操作入口",
        "  G — Ultimate (终极/觉醒)  |  F — Block (格挡)",
        "  Q — Dash (冲刺)  |  鼠标左键 — M1 (普攻)",
        "",
        "v2.0 全新战斗核心:",
        "  • Attack Aura: 用真实技能 (Console Move)",
        "    而非模拟点击, 读取技能栏可用技能随机释放",
        "  • Auto Combo: 依次释放所有可用技能 + 终极 (G)",
        "  • Auto Ultimate: 监听 GetAttribute('Ultimate')",
        "    满 100 自动按 G",
        "  • Kill Farm: 传送 + 自动终极 + 自动攻击",
        "  • 目标选择: 击杀数 (Kills) 越少越优先",
        "",
        "功能总览:",
        "  战斗: Attack Aura / Auto Combo / Auto Ultimate / Auto Block",
        "  农场: Kill Farm / Auto Reset",
        "  移动: WalkSpeed / JumpPower / InfJump / NoClip / Fly / 状态防抗",
        "  视觉: 玩家ESP + 血量 + 距离 + 全亮",
        "  服务器: Rejoin / Server Hop   杂项: Anti-AFK / 坐标",
        "",
        "脚本快捷键: T=传最近敌人  Y=NoClip  U=Fly  RightShift=UI",
    }, "\n"),
})

-- ── 快捷键 ──
local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.T then
        local target = BestTarget(200)
        if target then
            TeleportToPlayer(target, true, "Behind")
            notify("T 快捷键", "→ 传送到 " .. target.Name, 1.5, "Info")
        end
    elseif input.KeyCode == Enum.KeyCode.Y then
        local newState = not SETTINGS.TSB_NoClip
        SETTINGS.TSB_NoClip = newState
        toggleNoclip(newState)
        notify("Y 快捷键", newState and "NoClip ON" or "NoClip OFF", 1.5, "Info")
    elseif input.KeyCode == Enum.KeyCode.U then
        local newState = not SETTINGS.TSB_Fly
        SETTINGS.TSB_Fly = newState
        toggleFly(newState, SETTINGS.TSB_FlySpeed)
        notify("U 快捷键", newState and "Fly ON" or "Fly OFF", 1.5, "Info")
    end
end)

-- 角色重生时恢复设置
local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if isDestroyed then return end
    Humanoid = getHum()
    if SETTINGS.TSB_WalkSpeed then toggleWalkSpeed(true) end
    if SETTINGS.TSB_JumpPower then toggleJumpPower(true) end
    if SETTINGS.TSB_NoClip then toggleNoclip(true) end
    if SETTINGS.TSB_Fly then toggleFly(true, SETTINGS.TSB_FlySpeed) end
end)

-- ══════════════════════════════════════════════════════════════════
-- 16. 清理
-- ══════════════════════════════════════════════════════════════════
local function cleanup()
    if isDestroyed then return end
    isDestroyed = true

    if inputConn then inputConn:Disconnect() end
    if charAddedConn then charAddedConn:Disconnect() end
    if auraConn then auraConn:Disconnect() end
    if comboConn then comboConn:Disconnect() end
    if blockConn then blockConn:Disconnect() end
    if farmConn then farmConn:Disconnect() end
    if espConn then espConn:Disconnect() end
    if walkConn then walkConn:Disconnect() end
    if jumpConn then jumpConn:Disconnect() end
    if infJumpConn then infJumpConn:Disconnect() end
    if noclipConn then noclipConn:Disconnect() end
    if flyConn then flyConn:Disconnect() end
    if noStunConn then noStunConn:Disconnect() end
    if noRagdollConn then noRagdollConn:Disconnect() end
    if noDashConn then noDashConn:Disconnect() end
    if antiAFKConn then antiAFKConn:Disconnect() end

    pressBlock(false)

    if flyBV then pcall(function() flyBV:Destroy() end) end
    if flyBG then pcall(function() flyBG:Destroy() end) end

    clearESP()
    toggleFullbright(false)
    local hum = getHum()
    if hum then pcall(function() hum.WalkSpeed = 16; hum.JumpPower = 50 end) end

    if Window then
        pcall(function() Window:Destroy() end)
        Window = nil
    end

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "TSB", Text = "脚本已卸载", Duration = 2
        })
    end)
end

_G.TSB_Cleanup = cleanup

-- ── 完成通知 ──
task.wait(0.5)
notify("TSB v2.0", "The Strongest Battlegrounds 辅助已加载\n基于 NexamTSB 真实源码结构\n按 RightShift 打开 UI", 5, "Success")

print(string.format("[TSB] v2.0 (PlaceId: %d) 辅助加载完成 — 基于 NexamTSB 真实结构还原", game.PlaceId))