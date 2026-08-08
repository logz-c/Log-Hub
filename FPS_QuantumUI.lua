--[[
    FPS 辅助脚本 v20.0 (Quantum UI 版)
    功能：ESP、自瞄、扳机、概率瞄准、NPC透视（含队伍检测）
    快捷键：
        Insert     - 开关ESP
        Delete     - 彻底销毁脚本
        右Ctrl     - 隐藏/显示UI
        F2         - 标记附近所有玩家为队友
        F3         - 清除所有手动队友标记
    所有其他功能均通过UI面板操作。
]]

if not game:IsLoaded() then game.Loaded:Wait() end

-- ══════════════════════════════════════════════════════════════════
-- 0. SINGLETON GUARD — 防止重复注入
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
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/logz-ui-lib/refs/heads/main/Source.lua"))()
end)

if not success then
    warn("[FPS] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[FPS] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[FPS] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[FPS] Quantum UI v" .. QuantumUI.Version .. " 加载成功")

-- ══════════════════════════════════════════════════════════════════
-- 2. ROBLOX SERVICES
-- ══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Camera = workspace.CurrentCamera
local Workspace = workspace

-- ══════════════════════════════════════════════════════════════════
-- 3. 预设颜色 & SETTINGS
-- ══════════════════════════════════════════════════════════════════
local PRESET_COLORS = {
    Color3.fromRGB(255, 0, 0),
    Color3.fromRGB(0, 255, 0),
    Color3.fromRGB(0, 0, 255),
    Color3.fromRGB(255, 255, 0),
    Color3.fromRGB(128, 0, 255),
    Color3.fromRGB(0, 255, 255),
    Color3.fromRGB(255, 128, 0),
    Color3.fromRGB(255, 255, 255),
}

local SETTINGS = {
    Enabled = true,
    ShowName = true,
    ShowHealth = true,
    ShowDistance = true,
    ShowHighlight = true,
    ShowBones = true,
    ShowHeadDot = true,
    HeadDotRadius = 6,
    BoneThickness = 2,
    TeammateColor = Color3.fromRGB(0, 255, 50),
    EnemyColor = Color3.fromRGB(255, 150, 0),
    HiddenColor = Color3.fromRGB(255, 50, 50),
    HighlightFillTrans = 0.35,
    HighlightOutlineTrans = 0.6,
    FontSizeName = 14,
    FontSizeInfo = 12,
    MaxRenderDistance = 500,
    DeathRiseSpeed = 0.3,
    DeathFadeDuration = 10,
    AimbotSmoothness = 0.35,
    AimbotFOV = 78,
    ShowFOVCircle = false,
    FOVCircleColor = Color3.fromRGB(0, 255, 255),
    FOVCircleTransparency = 0.3,
    ForceAllEnemy = false,
    AimPartIndex = 0,
    AimbotCheckWall = false,
    TriggerLoaded = false,
    TriggerBot = false,
    AimbotEnabled = true,
    TriggerDelay = 0,
    SmartAimMode = false,
    EnableProbAim = false,
    HeadWeight = 50,
    TorsoWeight = 30,
    LegWeight = 20,
    ShowAimLine = true,
    ShowNPC = false,
    CustomTeamTag = "",
    ManualTeammateRadius = 50,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 全局变量
-- ══════════════════════════════════════════════════════════════════
local espObjects = {}
local npcEspObjects = {}
local heartbeatConnection = nil
local pulsePhase = 0
local statusText = nil
local statsText = nil
local deathLabelsAll = {}
local aimbotActive = false
local fovCircle = nil
local fovConnection = nil
local aimbotConnection = nil
local deathHeartbeat = nil
local isDestroyed = false
local triggerbotEvents = nil
local aimLine = nil
local manualTeammates = {}
local Window = nil

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
                Title = title,
                Text = content,
                Duration = duration or 3
            })
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 5. 工具函数 (与原 FPS.lua 完全一致)
-- ══════════════════════════════════════════════════════════════════
local function getCharParts(character)
    if not character then return nil, nil end
    return character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("Humanoid")
end

local function isTeammate(player1, player2)
    if player1 == player2 then return true end
    if manualTeammates[player2] then return true end
    if SETTINGS.ForceAllEnemy then return false end
    if SETTINGS.CustomTeamTag ~= "" then
        local function getCustomTag(char)
            if not char then return nil end
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                local attr = root:GetAttribute("TeamTag") or root:GetAttribute("Faction") or root:GetAttribute("Team")
                if attr and tostring(attr) == SETTINGS.CustomTeamTag then return true end
                for _, child in ipairs(root:GetChildren()) do
                    if child:IsA("StringValue") and child.Value == SETTINGS.CustomTeamTag then return true end
                end
            end
            local attr2 = char:GetAttribute("TeamTag") or char:GetAttribute("Faction") or char:GetAttribute("Team")
            if attr2 and tostring(attr2) == SETTINGS.CustomTeamTag then return true end
            return false
        end
        local char1 = player1.Character
        local char2 = player2.Character
        if char1 and char2 then
            local tag1 = getCustomTag(char1)
            local tag2 = getCustomTag(char2)
            if tag1 and tag2 and tag1 == tag2 then return true end
        end
    end
    if player1.Team and player2.Team and player1.Team == player2.Team then return true end
    if player1.TeamColor and player2.TeamColor and player1.TeamColor == player2.TeamColor then return true end
    local tagNames = {"TeamTag", "Faction", "TeamId", "Side", "TeamName", "FactionName"}
    for _, tag in ipairs(tagNames) do
        local p1Attr = player1:FindFirstChild(tag)
        local p2Attr = player2:FindFirstChild(tag)
        if p1Attr and p2Attr and p1Attr.Value == p2Attr.Value then return true end
    end
    local attrNames = {"Team", "Faction", "TeamId", "Side", "TeamName", "FactionName"}
    for _, tag in ipairs(attrNames) do
        local p1Val = player1:GetAttribute(tag)
        local p2Val = player2:GetAttribute(tag)
        if p1Val ~= nil and p2Val ~= nil and p1Val == p2Val then return true end
    end
    local function getCharacterTag(char)
        if not char then return nil end
        local root = char:FindFirstChild("HumanoidRootPart")
        local head = char:FindFirstChild("Head")
        for _, part in ipairs({root, head}) do
            if part then
                for _, tag in ipairs(attrNames) do
                    local val = part:GetAttribute(tag)
                    if val ~= nil then return val end
                end
                for _, tag in ipairs(tagNames) do
                    local attr = part:FindFirstChild(tag)
                    if attr then return attr.Value end
                end
            end
        end
        return nil
    end
    local char1 = player1.Character
    local char2 = player2.Character
    if char1 and char2 then
        local tag1 = getCharacterTag(char1)
        local tag2 = getCharacterTag(char2)
        if tag1 and tag2 and tag1 == tag2 then return true end
    end
    return false
end

local function isSameTeam(entity1, entity2)
    if entity1 == entity2 then return true end
    if entity1:IsA("Player") and entity2:IsA("Player") then
        return isTeammate(entity1, entity2)
    end
    if SETTINGS.ForceAllEnemy then return false end
    if SETTINGS.CustomTeamTag ~= "" then
        local function hasCustomTag(entity)
            if not entity then return false end
            local char = entity:IsA("Player") and entity.Character or entity
            if not char then return false end
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                local attr = root:GetAttribute("TeamTag") or root:GetAttribute("Faction") or root:GetAttribute("Team")
                if attr and tostring(attr) == SETTINGS.CustomTeamTag then return true end
                for _, child in ipairs(root:GetChildren()) do
                    if child:IsA("StringValue") and child.Value == SETTINGS.CustomTeamTag then return true end
                end
            end
            local attr2 = char:GetAttribute("TeamTag") or char:GetAttribute("Faction") or char:GetAttribute("Team")
            if attr2 and tostring(attr2) == SETTINGS.CustomTeamTag then return true end
            return false
        end
        if hasCustomTag(entity1) and hasCustomTag(entity2) then return true end
    end
    local function getEntityTeam(entity)
        if not entity then return nil, nil end
        if entity:IsA("Player") then
            return entity.Team, entity.TeamColor
        else
            local char = entity
            local team = char:GetAttribute("Team") or char:GetAttribute("TeamTag")
            if not team then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    team = root:GetAttribute("Team") or root:GetAttribute("TeamTag")
                    if not team then
                        for _, child in ipairs(root:GetChildren()) do
                            if child:IsA("StringValue") and (child.Name == "Team" or child.Name == "TeamTag") then
                                team = child.Value
                                break
                            end
                        end
                    end
                end
            end
            local teamColor = char:GetAttribute("TeamColor")
            if not teamColor then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    teamColor = root:GetAttribute("TeamColor")
                end
            end
            return team, teamColor
        end
    end
    local team1, color1 = getEntityTeam(entity1)
    local team2, color2 = getEntityTeam(entity2)
    if team1 and team2 and team1 == team2 then return true end
    if color1 and color2 and color1 == color2 then return true end
    return false
end

local function isNPC(model)
    if not model or not model:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    if model:FindFirstChildOfClass("Humanoid") then return true end
    local name = model.Name:lower()
    if name:find("npc") or name:find("bot") or name:find("ai") or name:find("enemy") then
        return true
    end
    return false
end

local function isPartVisible(part, targetCharacter)
    if not part or not targetCharacter then return false end
    local origin = Camera.CFrame.Position
    local direction = (part.Position - origin).Unit
    local distance = (origin - part.Position).Magnitude
    if distance < 0.5 then return true end
    local ignoreList = {}
    local localChar = LocalPlayer.Character
    if localChar then
        for _, p in ipairs(localChar:GetDescendants()) do
            if p:IsA("BasePart") then table.insert(ignoreList, p) end
        end
    end
    if targetCharacter then
        for _, p in ipairs(targetCharacter:GetDescendants()) do
            if p:IsA("BasePart") then table.insert(ignoreList, p) end
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = ignoreList
    local result = workspace:Raycast(origin, direction * distance, params)
    return not result
end

local function getAimParts(character)
    if not character then return nil, nil, nil end
    local head = character:FindFirstChild("Head")
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    local leg = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("LowerTorso")
    return head, torso, leg
end

local function getProbAimPosition(character)
    if not character then return nil end
    local head, torso, leg = getAimParts(character)
    local parts = {head, torso, leg}
    local weights = {SETTINGS.HeadWeight, SETTINGS.TorsoWeight, SETTINGS.LegWeight}
    local available = {}
    local availWeights = {}
    if SETTINGS.SmartAimMode then
        for i, part in ipairs(parts) do
            if part and isPartVisible(part, character) then
                table.insert(available, part)
                table.insert(availWeights, weights[i])
            end
        end
    else
        for i, part in ipairs(parts) do
            if part then
                table.insert(available, part)
                table.insert(availWeights, weights[i])
            end
        end
    end
    if #available == 0 then
        local idx = SETTINGS.AimPartIndex
        local fallback = parts[idx+1]
        return fallback and fallback.Position
    end
    local totalWeight = 0
    for _, w in ipairs(availWeights) do
        totalWeight = totalWeight + w
    end
    if totalWeight <= 0 then
        for i = 1, #availWeights do availWeights[i] = 1 end
        totalWeight = #availWeights
    end
    local rand = math.random() * totalWeight
    local cumulative = 0
    for i, w in ipairs(availWeights) do
        cumulative = cumulative + w
        if rand <= cumulative then
            return available[i].Position
        end
    end
    return available[#available].Position
end

local function isTargetVisible(targetCharacter)
    local localChar = LocalPlayer.Character
    if not localChar then return false end
    local originPart = localChar:FindFirstChild("Head")
    local origin = originPart and originPart.Position or Camera.CFrame.Position
    local targetPoints = {}
    local head = targetCharacter:FindFirstChild("Head")
    if head then table.insert(targetPoints, head.Position) end
    local torso = targetCharacter:FindFirstChild("UpperTorso") or targetCharacter:FindFirstChild("Torso")
    if torso then table.insert(targetPoints, torso.Position) end
    if #targetPoints == 0 then return false end
    local ignoreList = {}
    if localChar then
        for _, part in ipairs(localChar:GetDescendants()) do
            if part:IsA("BasePart") then table.insert(ignoreList, part) end
        end
    end
    if targetCharacter then
        for _, part in ipairs(targetCharacter:GetDescendants()) do
            if part:IsA("BasePart") then table.insert(ignoreList, part) end
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = ignoreList
    for _, pos in ipairs(targetPoints) do
        local direction = (pos - origin).Unit
        local distance = (origin - pos).Magnitude
        if distance < 0.5 then
            return true
        else
            local result = workspace:Raycast(origin, direction * distance, params)
            if not result then
                return true
            end
        end
    end
    return false
end

local function lerpColor(a, b, t)
    return Color3.new(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
end

local function getTargetPosition(character)
    if not character then return nil end
    local part
    local index = SETTINGS.AimPartIndex
    if index == 0 then
        part = character:FindFirstChild("Head")
    elseif index == 1 then
        part = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    else
        part = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("LowerTorso")
    end
    return part and part.Position
end

local function getClosestEnemyOnScreen()
    local localChar = LocalPlayer.Character
    if not localChar then return nil end
    local localRoot = localChar:FindFirstChild("HumanoidRootPart")
    if not localRoot then return nil end
    local viewportSize = Camera.ViewportSize
    local center = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
    local fovRad = math.rad(SETTINGS.AimbotFOV / 2)
    local screenRadius = math.tan(fovRad) * (viewportSize.X / 2) / math.tan(math.rad(70/2))
    local maxScreenDist = screenRadius
    local closest = nil
    local closestScreenDist = math.huge
    local localPos = localRoot.Position
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if not char then continue end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then continue end
        local targetPos = getTargetPosition(char)
        if not targetPos then continue end
        if isTeammate(LocalPlayer, player) then continue end
        if SETTINGS.AimbotCheckWall then
            if not isTargetVisible(char) then
                continue
            end
        end
        local dist = (targetPos - localPos).Magnitude
        if dist > SETTINGS.MaxRenderDistance then continue end
        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
        if not onScreen then continue end
        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
        if screenDist > maxScreenDist then continue end
        if screenDist < closestScreenDist then
            closestScreenDist = screenDist
            closest = { Character = char, Player = player }
        end
    end
    return closest
end

local function getActualAimPosition(character)
    if not character then return nil end
    if SETTINGS.EnableProbAim then
        return getProbAimPosition(character)
    else
        if SETTINGS.SmartAimMode then
            local head = character:FindFirstChild("Head")
            local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
            local headVisible = head and isPartVisible(head, character)
            local torsoVisible = torso and isPartVisible(torso, character)
            if headVisible and not torsoVisible then
                return head and head.Position
            elseif torsoVisible and not headVisible then
                return torso and torso.Position
            elseif headVisible and torsoVisible then
                if math.random() < 0.5 then
                    return head and head.Position
                else
                    return torso and torso.Position
                end
            else
                return getTargetPosition(character)
            end
        else
            return getTargetPosition(character)
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 6. ESP 核心 (与原 FPS.lua 完全一致)
-- ══════════════════════════════════════════════════════════════════
local function createESPObject(target, isNPCFlag)
    local nameText = Drawing.new("Text")
    nameText.Visible = false
    nameText.Color = Color3.new(1,1,1)
    nameText.Size = SETTINGS.FontSizeName
    nameText.Center = true
    nameText.Outline = true
    nameText.OutlineColor = Color3.new(0,0,0)
    local healthText = Drawing.new("Text")
    healthText.Visible = false
    healthText.Color = Color3.new(0,1,0)
    healthText.Size = SETTINGS.FontSizeInfo
    healthText.Center = false
    healthText.Outline = true
    healthText.OutlineColor = Color3.new(0,0,0)
    local distText = Drawing.new("Text")
    distText.Visible = false
    distText.Color = Color3.new(0.8,0.8,0.8)
    distText.Size = SETTINGS.FontSizeInfo
    distText.Center = false
    distText.Outline = true
    distText.OutlineColor = Color3.new(0,0,0)
    local healthBar = Drawing.new("Quad")
    healthBar.Visible = false
    healthBar.Thickness = 1
    healthBar.Color = Color3.new(0,1,0)
    healthBar.Filled = true
    healthBar.Transparency = 0.5
    local highlight = Instance.new("Highlight")
    highlight.Adornee = target.Character or target
    highlight.FillColor = SETTINGS.EnemyColor
    highlight.OutlineColor = SETTINGS.EnemyColor
    highlight.FillTransparency = SETTINGS.HighlightFillTrans
    highlight.OutlineTransparency = SETTINGS.HighlightOutlineTrans
    highlight.Enabled = SETTINGS.ShowHighlight
    highlight.Parent = target.Character or target
    local headDot = Drawing.new("Circle")
    headDot.Visible = false
    headDot.Radius = SETTINGS.HeadDotRadius
    headDot.Filled = true
    headDot.Thickness = 1
    headDot.Color = SETTINGS.EnemyColor
    local boneLines = {}
    for i = 1, 14 do
        local line = Drawing.new("Line")
        line.Visible = false
        line.Thickness = SETTINGS.BoneThickness
        line.Color = Color3.new(1,1,1)
        line.Transparency = 0.5
        table.insert(boneLines, line)
    end
    return {
        Name = nameText,
        Health = healthText,
        Dist = distText,
        HealthBar = healthBar,
        Highlight = highlight,
        HeadDot = headDot,
        BoneLines = boneLines,
        Character = target.Character or target,
        CurrentColor = SETTINGS.EnemyColor,
        TargetColor = SETTINGS.EnemyColor,
        PulsePhase = math.random() * 2 * math.pi,
        IsDead = false,
        IsNPC = isNPCFlag or false,
    }
end

local function createESP(player)
    if espObjects[player] then return end
    local obj = createESPObject(player, false)
    espObjects[player] = obj
    local function onCharacterAdded(newChar)
        task.wait(0.1)
        local obj = espObjects[player]
        if obj and obj.Highlight then
            obj.Highlight.Adornee = newChar
            obj.Highlight.Parent = newChar
            obj.Highlight.Enabled = SETTINGS.ShowHighlight
            obj.Character = newChar
        end
    end
    player.CharacterAdded:Connect(onCharacterAdded)
end

local function createNPCESP(npcModel)
    if npcEspObjects[npcModel] then return end
    local obj = createESPObject(npcModel, true)
    npcEspObjects[npcModel] = obj
end

local function removeESP(target, isNPC)
    local tableRef = isNPC and npcEspObjects or espObjects
    local obj = tableRef[target]
    if obj then
        obj.Name:Remove()
        obj.Health:Remove()
        obj.Dist:Remove()
        obj.HealthBar:Remove()
        obj.HeadDot:Remove()
        if obj.Highlight then obj.Highlight:Destroy() end
        if obj.BoneLines then
            for _, line in ipairs(obj.BoneLines) do
                line:Remove()
            end
        end
        tableRef[target] = nil
    end
end

local function spawnDeathLabel(target, headPos, isNPC)
    if deathLabelsAll[target] then return end
    local label = Drawing.new("Text")
    label.Center = true
    label.Outline = true
    label.OutlineColor = Color3.new(0,0,0)
    label.Font = 2
    label.Color = Color3.new(1, 0, 0)
    label.Size = 20
    label.Text = "DIADB"
    label.Visible = true
    label.Transparency = 0
    deathLabelsAll[target] = {
        label = label,
        startTime = tick(),
        startPos = Vector2.new(headPos.X, headPos.Y),
        isNPC = isNPC,
    }
    if not deathHeartbeat then
        deathHeartbeat = RunService.Heartbeat:Connect(function()
            local now = tick()
            for key, data in pairs(deathLabelsAll) do
                local elapsed = now - data.startTime
                if elapsed >= SETTINGS.DeathFadeDuration then
                    data.label.Visible = false
                    data.label:Remove()
                    deathLabelsAll[key] = nil
                else
                    local rise = elapsed * SETTINGS.DeathRiseSpeed * 60
                    data.label.Position = Vector2.new(data.startPos.X, data.startPos.Y - 10 - rise)
                    data.label.Transparency = elapsed / SETTINGS.DeathFadeDuration * 0.8
                end
            end
            if next(deathLabelsAll) == nil and deathHeartbeat then
                deathHeartbeat:Disconnect()
                deathHeartbeat = nil
            end
        end)
    end
end

-- ══════════════════════════════════════════════════════════════════
-- 7. 扳机
-- ══════════════════════════════════════════════════════════════════
local function loadTriggerbot()
    if SETTINGS.TriggerLoaded then return end
    SETTINGS.TriggerLoaded = true
    local mouse = LocalPlayer:GetMouse()
    local function simulateClick()
        if mouse1click then
            mouse1click()
        elseif VirtualInputManager then
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, nil, 1)
            task.wait(0.03)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, nil, 1)
        else
            warn("无法模拟鼠标点击")
        end
    end
    local function isHoveringEnemy()
        local target = mouse.Target
        if not target then return false end
        local character = target:FindFirstAncestorOfClass("Model")
        if not character then return false end
        local player = Players:GetPlayerFromCharacter(character)
        if player then
            if player == LocalPlayer then return false end
            if isTeammate(LocalPlayer, player) then return false end
        else
            return false
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return false end
        return true
    end
    local lastClickTime = 0
    local clickDelay = 0.1
    local pendingTriggerTask = nil
    local function cancelPendingTask()
        if pendingTriggerTask then
            task.cancel(pendingTriggerTask)
            pendingTriggerTask = nil
        end
    end
    local moveConn = mouse.Move:Connect(function()
        if not SETTINGS.TriggerBot or isDestroyed then return end
        if isHoveringEnemy() then
            cancelPendingTask()
            pendingTriggerTask = task.spawn(function()
                local delayMs = SETTINGS.TriggerDelay or 0
                if delayMs > 0 then
                    task.wait(delayMs / 1000)
                end
                if SETTINGS.TriggerBot and not isDestroyed and isHoveringEnemy() then
                    local now = tick()
                    if now - lastClickTime >= clickDelay then
                        simulateClick()
                        lastClickTime = now
                    end
                end
                pendingTriggerTask = nil
            end)
        else
            cancelPendingTask()
        end
    end)
    triggerbotEvents = { move = moveConn }
    SETTINGS.TriggerBot = true
    notify("扳机", "扳机功能已加载并启用", 3, "Success")
    print("扳机功能已加载")
end

-- ══════════════════════════════════════════════════════════════════
-- 8. FOV 圈和瞄准线
-- ══════════════════════════════════════════════════════════════════
local function updateFOVCircle()
    if isDestroyed then return end
    if SETTINGS.ShowFOVCircle and fovCircle then
        local viewport = Camera.ViewportSize
        local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
        fovCircle.Position = center
        local vFov = math.rad(Camera.FieldOfView)
        local aspect = viewport.X / viewport.Y
        local hFov = 2 * math.atan(math.tan(vFov / 2) * aspect)
        local aimFovRad = math.rad(SETTINGS.AimbotFOV / 2)
        local radius = math.tan(aimFovRad) / math.tan(hFov / 2) * (viewport.X / 2)
        radius = math.max(radius, 5)
        fovCircle.Radius = radius
        fovCircle.Color = SETTINGS.FOVCircleColor
        fovCircle.Transparency = SETTINGS.FOVCircleTransparency
        fovCircle.Thickness = 2
        fovCircle.Filled = false
        fovCircle.Visible = true
    elseif fovCircle then
        fovCircle.Visible = false
    end
end

local function updateAimLine()
    if isDestroyed or not aimLine then return end
    if not SETTINGS.ShowAimLine then
        aimLine.Visible = false
        return
    end
    local targetData = getClosestEnemyOnScreen()
    if not targetData then
        aimLine.Visible = false
        return
    end
    local char = targetData.Character
    local targetPos = getActualAimPosition(char)
    if not targetPos then
        aimLine.Visible = false
        return
    end
    local viewport = Camera.ViewportSize
    local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPos)
    if not onScreen then
        aimLine.Visible = false
        return
    end
    aimLine.From = center
    aimLine.To = Vector2.new(screenPos.X, screenPos.Y)
    aimLine.Color = SETTINGS.FOVCircleColor
    aimLine.Thickness = 2
    aimLine.Transparency = 0.7
    aimLine.Visible = true
end

-- ══════════════════════════════════════════════════════════════════
-- 9. 核心更新循环 (ESP)
-- ══════════════════════════════════════════════════════════════════
local function updateESP()
    if isDestroyed then return end
    local success, err = pcall(function()
        if not SETTINGS.Enabled then
            for _, obj in pairs(espObjects) do
                obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                if obj.Highlight then obj.Highlight.Enabled = false end
                if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
            end
            for _, obj in pairs(npcEspObjects) do
                obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                if obj.Highlight then obj.Highlight.Enabled = false end
                if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
            end
            for _, data in pairs(deathLabelsAll) do data.label.Visible = false end
            if statsText then statsText.Text = "ESP OFF"; statsText.Color = Color3.new(1,0,0) end
            return
        end
        local localChar = LocalPlayer.Character
        if not localChar then return end
        local localRoot = localChar:FindFirstChild("HumanoidRootPart")
        if not localRoot then return end
        pulsePhase = (pulsePhase + 0.02) % (2 * math.pi)
        local aliveTeammates = 0; local aliveEnemies = 0; local manualTeamCount = 0
        for _ in pairs(manualTeammates) do manualTeamCount = manualTeamCount + 1 end

        -- ===== 玩家循环 =====
        for _, player in pairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local char = player.Character
            local obj = espObjects[player]
            if not obj then createESP(player); obj = espObjects[player] end
            if not char then
                if not deathLabelsAll[player] then
                    obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                    obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                    if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                    if obj.Highlight then obj.Highlight.Enabled = false end
                end
                continue
            end
            if obj.Highlight then
                if obj.Character ~= char then
                    obj.Highlight.Adornee = char; obj.Highlight.Parent = char; obj.Character = char
                end
                obj.Highlight.Enabled = SETTINGS.ShowHighlight
            end
            local root, humanoid = getCharParts(char)
            local head = char:FindFirstChild("Head")
            if not root or not humanoid or not head then
                obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                continue
            end
            local isDead = (humanoid.Health <= 0)
            local rootPos, rootVis = Camera:WorldToViewportPoint(root.Position)
            local headPos, headVis = Camera:WorldToViewportPoint(head.Position)
            if isDead and not obj.IsDead then
                obj.IsDead = true
                if headVis then spawnDeathLabel(player, headPos, false)
                else spawnDeathLabel(player, Vector2.new(rootPos.X, rootPos.Y - 3), false) end
            elseif not isDead then
                obj.IsDead = false
                if deathLabelsAll[player] then
                    deathLabelsAll[player].label.Visible = false
                    deathLabelsAll[player].label:Remove()
                    deathLabelsAll[player] = nil
                end
            end
            if isDead then
                obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                if obj.Highlight then obj.Highlight.Enabled = false end
                continue
            end
            if not rootVis or not headVis then
                obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                continue
            end
            local distance = (root.Position - localRoot.Position).Magnitude
            local isTeammateFlag = isTeammate(LocalPlayer, player)
            if not isDead then
                if isTeammateFlag then aliveTeammates = aliveTeammates + 1 else aliveEnemies = aliveEnemies + 1 end
            end
            local visible = false
            local targetColor = SETTINGS.EnemyColor
            if isTeammateFlag then
                targetColor = SETTINGS.TeammateColor; visible = true
            else
                visible = isTargetVisible(char)
                targetColor = visible and SETTINGS.EnemyColor or SETTINGS.HiddenColor
            end
            obj.TargetColor = targetColor
            obj.CurrentColor = lerpColor(obj.CurrentColor, obj.TargetColor, 0.15)
            local distFactor = math.max(0.3, 1 - (distance / SETTINGS.MaxRenderDistance))
            if obj.Highlight and SETTINGS.ShowHighlight then
                local finalColor = obj.CurrentColor
                if visible and not isTeammateFlag then
                    local pulse = 0.2 * math.sin(pulsePhase + obj.PulsePhase) + 0.8
                    finalColor = Color3.new(
                        math.min(finalColor.r * pulse, 1),
                        math.min(finalColor.g * pulse, 1),
                        math.min(finalColor.b * pulse, 1)
                    )
                end
                obj.Highlight.FillColor = finalColor
                obj.Highlight.OutlineColor = finalColor
                if visible and not isTeammateFlag then
                    obj.Highlight.FillTransparency = SETTINGS.HighlightFillTrans
                    obj.Highlight.OutlineTransparency = SETTINGS.HighlightOutlineTrans
                elseif not isTeammateFlag then
                    obj.Highlight.FillTransparency = 0.95
                    obj.Highlight.OutlineTransparency = 0.3
                else
                    obj.Highlight.FillTransparency = SETTINGS.HighlightFillTrans
                    obj.Highlight.OutlineTransparency = SETTINGS.HighlightOutlineTrans
                end
                obj.Highlight.Enabled = true
            elseif obj.Highlight then obj.Highlight.Enabled = false end
            local centerX = rootPos.X
            local headY = headPos.Y
            local nameY = headY - 25
            local hpY = headY + 5
            local distY = hpY
            if SETTINGS.ShowName then
                obj.Name.Position = Vector2.new(centerX, nameY)
                obj.Name.Text = isTeammateFlag and (player.Name .. " (队友)") or player.Name
                obj.Name.Color = Color3.new(1,1,1)
                obj.Name.Size = math.max(8, SETTINGS.FontSizeName * distFactor)
                obj.Name.Transparency = 1 - distFactor
                obj.Name.Visible = true
            else obj.Name.Visible = false end
            if SETTINGS.ShowHealth then
                local hp = humanoid.Health / humanoid.MaxHealth
                local hc = Color3.new(1 - hp, hp, 0)
                obj.Health.Position = Vector2.new(centerX - 70, hpY)
                obj.Health.Text = string.format("%.0f%%", hp * 100)
                obj.Health.Color = hc
                obj.Health.Size = math.max(8, SETTINGS.FontSizeInfo * distFactor)
                obj.Health.Transparency = 1 - distFactor
                obj.Health.Visible = true
                local barWidth = 100 * distFactor
                local barHeight = 4 * distFactor
                local barX = centerX - 70
                local barY = hpY + 14
                local fillWidth = barWidth * hp
                obj.HealthBar.PointA = Vector2.new(barX, barY)
                obj.HealthBar.PointB = Vector2.new(barX + fillWidth, barY)
                obj.HealthBar.PointC = Vector2.new(barX + fillWidth, barY + barHeight)
                obj.HealthBar.PointD = Vector2.new(barX, barY + barHeight)
                obj.HealthBar.Color = hc
                obj.HealthBar.Transparency = 0.3 + (1 - distFactor) * 0.4
                obj.HealthBar.Visible = true
            else obj.Health.Visible = false; obj.HealthBar.Visible = false end
            if SETTINGS.ShowDistance then
                obj.Dist.Position = Vector2.new(centerX + 10, distY)
                obj.Dist.Text = string.format("%.0fm", distance)
                local distRatio = math.min(distance / SETTINGS.MaxRenderDistance, 1)
                obj.Dist.Color = Color3.new(1 - distRatio, distRatio, 0)
                obj.Dist.Size = math.max(8, SETTINGS.FontSizeInfo * distFactor)
                obj.Dist.Transparency = 1 - distFactor
                obj.Dist.Visible = true
            else obj.Dist.Visible = false end
            if SETTINGS.ShowHeadDot then
                obj.HeadDot.Position = Vector2.new(headPos.X, headPos.Y)
                obj.HeadDot.Color = obj.CurrentColor
                obj.HeadDot.Transparency = 0.3 + (1 - distFactor) * 0.4
                obj.HeadDot.Visible = true
            else obj.HeadDot.Visible = false end
            if SETTINGS.ShowBones then
                local joints
                if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
                    joints = {
                        {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
                        {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
                        {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
                        {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
                        {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
                    }
                else
                    joints = {
                        {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
                        {"Torso", "Left Leg"}, {"Torso", "Right Leg"}
                    }
                end
                local lines = obj.BoneLines
                while #lines < #joints do
                    local line = Drawing.new("Line")
                    line.Visible = false
                    line.Thickness = SETTINGS.BoneThickness
                    line.Color = Color3.new(1,1,1)
                    line.Transparency = 0.5
                    table.insert(lines, line)
                end
                for i, pair in ipairs(joints) do
                    local part1 = char:FindFirstChild(pair[1])
                    local part2 = char:FindFirstChild(pair[2])
                    local line = lines[i]
                    if part1 and part2 then
                        local screenPos1, onScreen1 = Camera:WorldToViewportPoint(part1.Position)
                        local screenPos2, onScreen2 = Camera:WorldToViewportPoint(part2.Position)
                        if onScreen1 and onScreen2 then
                            line.From = Vector2.new(screenPos1.X, screenPos1.Y)
                            line.To = Vector2.new(screenPos2.X, screenPos2.Y)
                            line.Color = obj.CurrentColor
                            line.Thickness = SETTINGS.BoneThickness
                            line.Transparency = visible and 0.3 or 0.7
                            line.Visible = true
                        else line.Visible = false end
                    else line.Visible = false end
                end
                for i = #joints + 1, #lines do lines[i].Visible = false end
            else
                if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
            end
        end -- 玩家循环结束

        -- ===== NPC 循环 =====
        if SETTINGS.ShowNPC then
            for _, model in ipairs(Workspace:GetDescendants()) do
                if model:IsA("Model") and isNPC(model) then
                    local obj = npcEspObjects[model]
                    if not obj then createNPCESP(model); obj = npcEspObjects[model] end
                    local char = model
                    local root, humanoid = getCharParts(char)
                    if not root then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then root = hum.RootPart end
                    end
                    local head = char:FindFirstChild("Head")
                    if not head and root then head = root end
                    if not root or not humanoid or not head then
                        obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                        obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                        if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                        if obj.Highlight then obj.Highlight.Enabled = false end
                        continue
                    end
                    local isDead = (humanoid.Health <= 0)
                    local rootPos, rootVis = Camera:WorldToViewportPoint(root.Position)
                    local headPos, headVis = Camera:WorldToViewportPoint(head.Position)
                    if isDead and not obj.IsDead then
                        obj.IsDead = true
                        if headVis then spawnDeathLabel(model, headPos, true)
                        else spawnDeathLabel(model, Vector2.new(rootPos.X, rootPos.Y - 3), true) end
                    elseif not isDead then
                        obj.IsDead = false
                        if deathLabelsAll[model] then
                            deathLabelsAll[model].label.Visible = false
                            deathLabelsAll[model].label:Remove()
                            deathLabelsAll[model] = nil
                        end
                    end
                    if isDead then
                        obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                        obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                        if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                        if obj.Highlight then obj.Highlight.Enabled = false end
                        continue
                    end
                    if not rootVis or not headVis then
                        obj.Name.Visible = false; obj.Health.Visible = false; obj.Dist.Visible = false
                        obj.HealthBar.Visible = false; obj.HeadDot.Visible = false
                        if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                        continue
                    end
                    local distance = (root.Position - localRoot.Position).Magnitude
                    local isTeammateFlag = false
                    if isSameTeam(LocalPlayer, char) then isTeammateFlag = true end
                    local visible = true
                    local targetColor = SETTINGS.EnemyColor
                    if isTeammateFlag then targetColor = SETTINGS.TeammateColor end
                    obj.TargetColor = targetColor
                    obj.CurrentColor = lerpColor(obj.CurrentColor, obj.TargetColor, 0.15)
                    local distFactor = math.max(0.3, 1 - (distance / SETTINGS.MaxRenderDistance))
                    if obj.Highlight and SETTINGS.ShowHighlight then
                        local finalColor = obj.CurrentColor
                        if visible and not isTeammateFlag then
                            local pulse = 0.2 * math.sin(pulsePhase + obj.PulsePhase) + 0.8
                            finalColor = Color3.new(
                                math.min(finalColor.r * pulse, 1),
                                math.min(finalColor.g * pulse, 1),
                                math.min(finalColor.b * pulse, 1)
                            )
                        end
                        obj.Highlight.FillColor = finalColor
                        obj.Highlight.OutlineColor = finalColor
                        if visible and not isTeammateFlag then
                            obj.Highlight.FillTransparency = SETTINGS.HighlightFillTrans
                            obj.Highlight.OutlineTransparency = SETTINGS.HighlightOutlineTrans
                        elseif not isTeammateFlag then
                            obj.Highlight.FillTransparency = 0.95
                            obj.Highlight.OutlineTransparency = 0.3
                        else
                            obj.Highlight.FillTransparency = SETTINGS.HighlightFillTrans
                            obj.Highlight.OutlineTransparency = SETTINGS.HighlightOutlineTrans
                        end
                        obj.Highlight.Enabled = true
                    elseif obj.Highlight then obj.Highlight.Enabled = false end
                    local centerX = rootPos.X
                    local headY = headPos.Y
                    local isHeadRoot = (head == root)
                    local yOffset = isHeadRoot and -20 or -25
                    local nameY = headY + yOffset
                    local hpY = headY + (isHeadRoot and 10 or 5)
                    local distY = hpY
                    if SETTINGS.ShowName then
                        obj.Name.Position = Vector2.new(centerX, nameY)
                        obj.Name.Text = "NPC"
                        obj.Name.Color = Color3.new(1,1,1)
                        obj.Name.Size = math.max(8, SETTINGS.FontSizeName * distFactor)
                        obj.Name.Transparency = 1 - distFactor
                        obj.Name.Visible = true
                    else obj.Name.Visible = false end
                    if SETTINGS.ShowHealth then
                        local hp = humanoid.Health / humanoid.MaxHealth
                        local hc = Color3.new(1 - hp, hp, 0)
                        obj.Health.Position = Vector2.new(centerX - 70, hpY)
                        obj.Health.Text = string.format("%.0f%%", hp * 100)
                        obj.Health.Color = hc
                        obj.Health.Size = math.max(8, SETTINGS.FontSizeInfo * distFactor)
                        obj.Health.Transparency = 1 - distFactor
                        obj.Health.Visible = true
                        local barWidth = 100 * distFactor
                        local barHeight = 4 * distFactor
                        local barX = centerX - 70
                        local barY = hpY + 14
                        local fillWidth = barWidth * hp
                        obj.HealthBar.PointA = Vector2.new(barX, barY)
                        obj.HealthBar.PointB = Vector2.new(barX + fillWidth, barY)
                        obj.HealthBar.PointC = Vector2.new(barX + fillWidth, barY + barHeight)
                        obj.HealthBar.PointD = Vector2.new(barX, barY + barHeight)
                        obj.HealthBar.Color = hc
                        obj.HealthBar.Transparency = 0.3 + (1 - distFactor) * 0.4
                        obj.HealthBar.Visible = true
                    else obj.Health.Visible = false; obj.HealthBar.Visible = false end
                    if SETTINGS.ShowDistance then
                        obj.Dist.Position = Vector2.new(centerX + 10, distY)
                        obj.Dist.Text = string.format("%.0fm", distance)
                        local distRatio = math.min(distance / SETTINGS.MaxRenderDistance, 1)
                        obj.Dist.Color = Color3.new(1 - distRatio, distRatio, 0)
                        obj.Dist.Size = math.max(8, SETTINGS.FontSizeInfo * distFactor)
                        obj.Dist.Transparency = 1 - distFactor
                        obj.Dist.Visible = true
                    else obj.Dist.Visible = false end
                    if SETTINGS.ShowHeadDot then
                        obj.HeadDot.Position = Vector2.new(headPos.X, headPos.Y)
                        obj.HeadDot.Color = obj.CurrentColor
                        obj.HeadDot.Transparency = 0.3 + (1 - distFactor) * 0.4
                        obj.HeadDot.Visible = true
                    else obj.HeadDot.Visible = false end
                    if SETTINGS.ShowBones then
                        local joints
                        if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
                            joints = {
                                {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
                                {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
                                {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
                                {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
                                {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"}
                            }
                        else
                            joints = {
                                {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
                                {"Torso", "Left Leg"}, {"Torso", "Right Leg"}
                            }
                        end
                        local lines = obj.BoneLines
                        while #lines < #joints do
                            local line = Drawing.new("Line")
                            line.Visible = false
                            line.Thickness = SETTINGS.BoneThickness
                            line.Color = Color3.new(1,1,1)
                            line.Transparency = 0.5
                            table.insert(lines, line)
                        end
                        for i, pair in ipairs(joints) do
                            local part1 = char:FindFirstChild(pair[1])
                            local part2 = char:FindFirstChild(pair[2])
                            local line = lines[i]
                            if part1 and part2 then
                                local screenPos1, onScreen1 = Camera:WorldToViewportPoint(part1.Position)
                                local screenPos2, onScreen2 = Camera:WorldToViewportPoint(part2.Position)
                                if onScreen1 and onScreen2 then
                                    line.From = Vector2.new(screenPos1.X, screenPos1.Y)
                                    line.To = Vector2.new(screenPos2.X, screenPos2.Y)
                                    line.Color = obj.CurrentColor
                                    line.Thickness = SETTINGS.BoneThickness
                                    line.Transparency = visible and 0.3 or 0.7
                                    line.Visible = true
                                else line.Visible = false end
                            else line.Visible = false end
                        end
                        for i = #joints + 1, #lines do lines[i].Visible = false end
                    else
                        if obj.BoneLines then for _, line in ipairs(obj.BoneLines) do line.Visible = false end end
                    end
                end
            end
        end -- ShowNPC 结束

        -- 更新统计文本
        local aimPartNames = {"Head", "Torso", "Legs"}
        local aimName = aimPartNames[SETTINGS.AimPartIndex + 1] or "Head"
        local triggerStatus = SETTINGS.TriggerLoaded and (SETTINGS.TriggerBot and "ON" or "OFF") or "WAIT"
        local mode = SETTINGS.ForceAllEnemy and "[FORCE]" or "[NORM]"
        local wallStatus = SETTINGS.AimbotCheckWall and "ON" or "OFF"
        local status = SETTINGS.Enabled and "ON" or "OFF"
        local aimStatus = SETTINGS.AimbotEnabled and "ON" or "OFF"
        local smartStatus = SETTINGS.SmartAimMode and "ON" or "OFF"
        local probStatus = SETTINGS.EnableProbAim and "ON" or "OFF"
        local npcStatus = SETTINGS.ShowNPC and "ON" or "OFF"
        if statsText then
            statsText.Text = string.format(
                "Ally: %d  Enemy: %d  [手动队友:%d]  %s  Wall: %s  Aim: %s\nAimPart: %s  Trigger: %s  ESP: %s  Smart: %s  Prob: %s  NPC: %s",
                aliveTeammates, aliveEnemies, manualTeamCount, mode, wallStatus,
                aimStatus, aimName, triggerStatus, status, smartStatus, probStatus, npcStatus
            )
            statsText.Color = SETTINGS.Enabled and Color3.new(0,1,0) or Color3.new(1,0,0)
            statsText.Position = Vector2.new(10, Camera.ViewportSize.Y - 70)
        end
        -- 清理
        for player, _ in pairs(espObjects) do
            if not Players:FindFirstChild(player.Name) then removeESP(player, false) end
        end
        for model, _ in pairs(npcEspObjects) do
            if not model.Parent or not isNPC(model) then removeESP(model, true) end
        end
    end)
    if not success then warn("ESP Update error:", err) end
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 自瞄更新
-- ══════════════════════════════════════════════════════════════════
local function updateAimbot()
    if not aimbotActive or not SETTINGS.Enabled or not SETTINGS.AimbotEnabled or isDestroyed then return end
    local targetData = getClosestEnemyOnScreen()
    if not targetData then return end
    local targetPos = getActualAimPosition(targetData.Character)
    if not targetPos then return end
    local currentCF = Camera.CFrame
    local newCF = CFrame.new(currentCF.p, targetPos)
    local smooth = SETTINGS.AimbotSmoothness
    local lerpedCF = currentCF:Lerp(newCF, smooth)
    Camera.CFrame = lerpedCF
end

-- ══════════════════════════════════════════════════════════════════
-- 11. 销毁脚本
-- ══════════════════════════════════════════════════════════════════
local function destroyScript()
    if isDestroyed then return end
    isDestroyed = true
    if heartbeatConnection then heartbeatConnection:Disconnect(); heartbeatConnection = nil end
    if deathHeartbeat then deathHeartbeat:Disconnect(); deathHeartbeat = nil end
    if aimbotConnection then aimbotConnection:Disconnect(); aimbotConnection = nil end
    if fovConnection then fovConnection:Disconnect(); fovConnection = nil end
    if triggerbotEvents and triggerbotEvents.move then
        triggerbotEvents.move:Disconnect(); triggerbotEvents = nil
    end
    for player, obj in pairs(espObjects) do removeESP(player, false) end
    espObjects = {}
    for model, obj in pairs(npcEspObjects) do removeESP(model, true) end
    npcEspObjects = {}
    for _, data in pairs(deathLabelsAll) do
        if data.label then data.label:Remove() end
    end
    deathLabelsAll = {}
    if fovCircle then fovCircle:Remove(); fovCircle = nil end
    if aimLine then aimLine:Remove(); aimLine = nil end
    if statusText then statusText:Remove(); statusText = nil end
    if statsText then statsText:Remove(); statsText = nil end
    if Window then pcall(function() Window:Destroy() end) end
    if _G.QuantumUI_Window then _G.QuantumUI_Window = nil end
    notify("销毁", "脚本已彻底销毁", 2, "Warning")
    print("脚本已彻底销毁")
end

-- ══════════════════════════════════════════════════════════════════
-- 12. 构建 Quantum UI 界面
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title = "FPS 辅助 v20.0",
    Subtitle = "Quantum UI 版",
    ThemeColor = Color3.fromRGB(0, 200, 255),
    Transparency = 0.3,
    Size = UDim2.new(0, 640, 0, 520),
    Keybind = Enum.KeyCode.RightControl,
})

_G.QuantumUI_Window = Window

-- 等待启动动画
task.wait(3.5)

-- ========== TAB 1: ESP 设置 ==========
local ESPTab = Window:AddTab({
    Name = "ESP",
    Icon = "rbxassetid://6034509993"
})

ESPTab:AddSection({ Name = "👁️ ESP 开关" })

ESPTab:AddToggle({
    Name = "启用 ESP (Insert)",
    Default = SETTINGS.Enabled,
    Flag = "ESP_Enabled",
    Callback = function(val) SETTINGS.Enabled = val end
})

ESPTab:AddToggle({
    Name = "显示名称",
    Default = SETTINGS.ShowName,
    Flag = "ESP_ShowName",
    Callback = function(val) SETTINGS.ShowName = val end
})

ESPTab:AddToggle({
    Name = "显示血量",
    Default = SETTINGS.ShowHealth,
    Flag = "ESP_ShowHealth",
    Callback = function(val) SETTINGS.ShowHealth = val end
})

ESPTab:AddToggle({
    Name = "显示距离",
    Default = SETTINGS.ShowDistance,
    Flag = "ESP_ShowDistance",
    Callback = function(val) SETTINGS.ShowDistance = val end
})

ESPTab:AddToggle({
    Name = "高亮显示",
    Default = SETTINGS.ShowHighlight,
    Flag = "ESP_ShowHighlight",
    Callback = function(val) SETTINGS.ShowHighlight = val end
})

ESPTab:AddToggle({
    Name = "显示骨骼",
    Default = SETTINGS.ShowBones,
    Flag = "ESP_ShowBones",
    Callback = function(val) SETTINGS.ShowBones = val end
})

ESPTab:AddToggle({
    Name = "显示头部标记",
    Default = SETTINGS.ShowHeadDot,
    Flag = "ESP_ShowHeadDot",
    Callback = function(val) SETTINGS.ShowHeadDot = val end
})

ESPTab:AddToggle({
    Name = "强制全部敌对",
    Default = SETTINGS.ForceAllEnemy,
    Flag = "ESP_ForceAllEnemy",
    Callback = function(val) SETTINGS.ForceAllEnemy = val end
})

ESPTab:AddSection({ Name = "📐 ESP 参数" })

ESPTab:AddSlider({
    Name = "最大渲染距离",
    Min = 50, Max = 2000, Default = SETTINGS.MaxRenderDistance, Increment = 10,
    Suffix = " studs",
    Flag = "ESP_MaxRenderDistance",
    Callback = function(val) SETTINGS.MaxRenderDistance = val end
})

ESPTab:AddSlider({
    Name = "高亮填充透明度",
    Min = 0, Max = 1, Default = SETTINGS.HighlightFillTrans, Increment = 0.05,
    Flag = "ESP_HighlightFillTrans",
    Callback = function(val) SETTINGS.HighlightFillTrans = val end
})

ESPTab:AddSlider({
    Name = "高亮轮廓透明度",
    Min = 0, Max = 1, Default = SETTINGS.HighlightOutlineTrans, Increment = 0.05,
    Flag = "ESP_HighlightOutlineTrans",
    Callback = function(val) SETTINGS.HighlightOutlineTrans = val end
})

ESPTab:AddSlider({
    Name = "头部标记半径",
    Min = 2, Max = 20, Default = SETTINGS.HeadDotRadius, Increment = 1,
    Suffix = "px",
    Flag = "ESP_HeadDotRadius",
    Callback = function(val) SETTINGS.HeadDotRadius = val end
})

ESPTab:AddSlider({
    Name = "骨骼线条粗细",
    Min = 1, Max = 5, Default = SETTINGS.BoneThickness, Increment = 1,
    Suffix = "px",
    Flag = "ESP_BoneThickness",
    Callback = function(val) SETTINGS.BoneThickness = val end
})

ESPTab:AddSection({ Name = "🎨 ESP 颜色" })

ESPTab:AddColorPicker({
    Name = "敌人颜色",
    Default = SETTINGS.EnemyColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_EnemyColor",
    Callback = function(c) SETTINGS.EnemyColor = c end
})

ESPTab:AddColorPicker({
    Name = "队友颜色",
    Default = SETTINGS.TeammateColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_TeammateColor",
    Callback = function(c) SETTINGS.TeammateColor = c end
})

ESPTab:AddColorPicker({
    Name = "隐藏颜色",
    Default = SETTINGS.HiddenColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_HiddenColor",
    Callback = function(c) SETTINGS.HiddenColor = c end
})

-- ========== TAB 2: 自瞄设置 ==========
local AimbotTab = Window:AddTab({
    Name = "Aimbot",
    Icon = "rbxassetid://6034287594"
})

AimbotTab:AddSection({ Name = "🎯 自瞄开关" })

AimbotTab:AddToggle({
    Name = "启用自瞄",
    Default = SETTINGS.AimbotEnabled,
    Flag = "Aimbot_Enabled",
    Callback = function(val)
        SETTINGS.AimbotEnabled = val
        notify("自瞄", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AimbotTab:AddToggle({
    Name = "墙体检测",
    Default = SETTINGS.AimbotCheckWall,
    Flag = "Aimbot_CheckWall",
    Callback = function(val) SETTINGS.AimbotCheckWall = val end
})

AimbotTab:AddToggle({
    Name = "智能瞄准模式",
    Default = SETTINGS.SmartAimMode,
    Flag = "Aimbot_SmartMode",
    Callback = function(val)
        SETTINGS.SmartAimMode = val
        notify("智能瞄准", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AimbotTab:AddToggle({
    Name = "显示 FOV 圈",
    Default = SETTINGS.ShowFOVCircle,
    Flag = "Aimbot_ShowFOV",
    Callback = function(val) SETTINGS.ShowFOVCircle = val end
})

AimbotTab:AddToggle({
    Name = "显示瞄准指示线",
    Default = SETTINGS.ShowAimLine,
    Flag = "Aimbot_ShowAimLine",
    Callback = function(val)
        SETTINGS.ShowAimLine = val
        if not val and aimLine then aimLine.Visible = false end
    end
})

AimbotTab:AddSection({ Name = "⚙️ 自瞄参数" })

AimbotTab:AddSlider({
    Name = "平滑度",
    Min = 0.05, Max = 1, Default = SETTINGS.AimbotSmoothness, Increment = 0.05,
    Flag = "Aimbot_Smoothness",
    Callback = function(val) SETTINGS.AimbotSmoothness = math.clamp(val, 0, 1) end
})

AimbotTab:AddSlider({
    Name = "自瞄 FOV",
    Min = 10, Max = 180, Default = SETTINGS.AimbotFOV, Increment = 1,
    Suffix = "°",
    Flag = "Aimbot_FOV",
    Callback = function(val) SETTINGS.AimbotFOV = val end
})

AimbotTab:AddDropdown({
    Name = "瞄准部位",
    Items = {"头部", "躯干", "腿部"},
    Default = ({"头部", "躯干", "腿部"})[SETTINGS.AimPartIndex + 1],
    Flag = "Aimbot_Part",
    Callback = function(selected)
        local map = {["头部"] = 0, ["躯干"] = 1, ["腿部"] = 2}
        SETTINGS.AimPartIndex = map[selected] or 0
    end
})

AimbotTab:AddColorPicker({
    Name = "FOV 圈颜色",
    Default = SETTINGS.FOVCircleColor,
    Presets = PRESET_COLORS,
    Flag = "Aimbot_FOVColor",
    Callback = function(c) SETTINGS.FOVCircleColor = c end
})

AimbotTab:AddSection({ Name = "🎯 概率瞄准设置" })

AimbotTab:AddToggle({
    Name = "启用概率瞄准",
    Default = SETTINGS.EnableProbAim,
    Flag = "ProbAim_Enabled",
    Callback = function(val)
        SETTINGS.EnableProbAim = val
        notify("概率瞄准", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

AimbotTab:AddSlider({
    Name = "头部权重",
    Min = 0, Max = 100, Default = SETTINGS.HeadWeight, Increment = 1,
    Suffix = "%",
    Flag = "ProbAim_HeadWeight",
    Callback = function(val)
        SETTINGS.HeadWeight = val
        if SETTINGS.HeadWeight == 0 and SETTINGS.TorsoWeight == 0 and SETTINGS.LegWeight == 0 then
            SETTINGS.HeadWeight = 100
            notify("权重", "权重不能全为0，已自动调整头部为100", 2, "Warning")
        end
    end
})

AimbotTab:AddSlider({
    Name = "躯干权重",
    Min = 0, Max = 100, Default = SETTINGS.TorsoWeight, Increment = 1,
    Suffix = "%",
    Flag = "ProbAim_TorsoWeight",
    Callback = function(val)
        SETTINGS.TorsoWeight = val
        if SETTINGS.HeadWeight == 0 and SETTINGS.TorsoWeight == 0 and SETTINGS.LegWeight == 0 then
            SETTINGS.HeadWeight = 100
            notify("权重", "权重不能全为0，已自动调整头部为100", 2, "Warning")
        end
    end
})

AimbotTab:AddSlider({
    Name = "腿部权重",
    Min = 0, Max = 100, Default = SETTINGS.LegWeight, Increment = 1,
    Suffix = "%",
    Flag = "ProbAim_LegWeight",
    Callback = function(val)
        SETTINGS.LegWeight = val
        if SETTINGS.HeadWeight == 0 and SETTINGS.TorsoWeight == 0 and SETTINGS.LegWeight == 0 then
            SETTINGS.HeadWeight = 100
            notify("权重", "权重不能全为0，已自动调整头部为100", 2, "Warning")
        end
    end
})

-- ========== TAB 3: 扳机 & NPC ==========
local TriggerTab = Window:AddTab({
    Name = "Trigger",
    Icon = "rbxassetid://6034281467"
})

TriggerTab:AddSection({ Name = "🔫 扳机设置" })

TriggerTab:AddToggle({
    Name = "启用扳机",
    Default = SETTINGS.TriggerBot,
    Flag = "Trigger_Enabled",
    Callback = function(val)
        if val then
            if not SETTINGS.TriggerLoaded then
                loadTriggerbot()
            else
                SETTINGS.TriggerBot = true
            end
        else
            SETTINGS.TriggerBot = false
        end
    end
})

TriggerTab:AddSlider({
    Name = "扳机延迟",
    Min = 0, Max = 500, Default = SETTINGS.TriggerDelay, Increment = 10,
    Suffix = " ms",
    Flag = "Trigger_Delay",
    Callback = function(val) SETTINGS.TriggerDelay = math.max(0, math.floor(val)) end
})

TriggerTab:AddSection({ Name = "🤖 NPC 透视" })

TriggerTab:AddToggle({
    Name = "启用 NPC 透视",
    Default = SETTINGS.ShowNPC,
    Flag = "NPC_ShowESP",
    Callback = function(val)
        SETTINGS.ShowNPC = val
        notify("NPC透视", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

TriggerTab:AddTextbox({
    Name = "自定义队伍标签",
    Placeholder = "留空使用自动检测",
    Default = SETTINGS.CustomTeamTag,
    Flag = "NPC_CustomTeamTag",
    Callback = function(text, enterPressed)
        if enterPressed then
            SETTINGS.CustomTeamTag = text
            notify("队伍标签", "已设置为: " .. (text ~= "" and text or "(自动检测)"), 2, "Success")
        end
    end
})

TriggerTab:AddLabel({ Text = "💡 标签用于判断队友，留空则使用 Team/TeamColor 自动检测。" })

TriggerTab:AddSection({ Name = "👥 手动队友" })

TriggerTab:AddSlider({
    Name = "F2 标记半径",
    Min = 10, Max = 200, Default = SETTINGS.ManualTeammateRadius, Increment = 5,
    Suffix = " studs",
    Flag = "Manual_Radius",
    Callback = function(val) SETTINGS.ManualTeammateRadius = math.floor(val) end
})

TriggerTab:AddButton({
    Name = "🗑️ 清除所有手动队友标记",
    Callback = function()
        for player in pairs(manualTeammates) do
            manualTeammates[player] = nil
        end
        notify("手动队友", "已清除所有手动队友标记", 2, "Info")
    end
})

TriggerTab:AddButton({
    Name = "💀 销毁脚本 (Delete)",
    Callback = function()
        destroyScript()
    end
})

TriggerTab:AddSection({ Name = "⌨️ 快捷键说明" })

TriggerTab:AddParagraph({
    Title = "操作说明",
    Content = table.concat({
        "Insert     - 开关 ESP",
        "Delete     - 彻底销毁脚本",
        "右 Ctrl    - 隐藏/显示 UI",
        "F2         - 标记附近玩家为队友",
        "F3         - 清除所有手动队友",
        "鼠标右键   - 按住激活自瞄",
    }, "\n")
})

-- ========== TAB 4: 死亡 & 其他 ==========
local MiscTab = Window:AddTab({
    Name = "Misc",
    Icon = "rbxassetid://6031280882"
})

MiscTab:AddSection({ Name = "💀 死亡标签效果" })

MiscTab:AddSlider({
    Name = "死亡上升速度",
    Min = 0.05, Max = 2, Default = SETTINGS.DeathRiseSpeed, Increment = 0.05,
    Flag = "Death_RiseSpeed",
    Callback = function(val) SETTINGS.DeathRiseSpeed = val end
})

MiscTab:AddSlider({
    Name = "死亡淡出时长",
    Min = 1, Max = 30, Default = SETTINGS.DeathFadeDuration, Increment = 1,
    Suffix = " s",
    Flag = "Death_FadeDuration",
    Callback = function(val) SETTINGS.DeathFadeDuration = val end
})

MiscTab:AddSection({ Name = "🔤 字体大小" })

MiscTab:AddSlider({
    Name = "姓名字号",
    Min = 8, Max = 24, Default = SETTINGS.FontSizeName, Increment = 1,
    Suffix = "px",
    Flag = "Font_NameSize",
    Callback = function(val) SETTINGS.FontSizeName = val end
})

MiscTab:AddSlider({
    Name = "信息字号",
    Min = 8, Max = 20, Default = SETTINGS.FontSizeInfo, Increment = 1,
    Suffix = "px",
    Flag = "Font_InfoSize",
    Callback = function(val) SETTINGS.FontSizeInfo = val end
})

MiscTab:AddSection({ Name = "🌈 彩虹边框" })

MiscTab:AddToggle({
    Name = "彩虹边框动画",
    Default = QuantumUI.RainbowEnabled,
    Callback = function(state)
        QuantumUI.RainbowEnabled = state
    end
})

MiscTab:AddSlider({
    Name = "彩虹速度",
    Min = 0.1, Max = 5, Default = QuantumUI.RainbowSpeed, Increment = 0.1,
    Suffix = "x",
    Callback = function(value) QuantumUI.RainbowSpeed = value end
})

MiscTab:AddDropdown({
    Name = "预设主题色",
    Items = {"Cyan", "Purple", "Green", "Red", "Gold", "Pink"},
    Default = "Cyan",
    Callback = function(selected)
        local themes = {
            Cyan   = Color3.fromRGB(0, 200, 255),
            Purple = Color3.fromRGB(180, 60, 255),
            Green  = Color3.fromRGB(0, 255, 120),
            Red    = Color3.fromRGB(255, 70, 90),
            Gold   = Color3.fromRGB(255, 200, 50),
            Pink   = Color3.fromRGB(255, 105, 180),
        }
        local color = themes[selected]
        if color then
            Window.ThemeColor = color
            QuantumUI.ThemeColor = color
            Window:RefreshTheme()
            notify("主题", "已切换: " .. selected, 2, "Success")
        end
    end
})

-- ══════════════════════════════════════════════════════════════════
-- 13. 主初始化
-- ══════════════════════════════════════════════════════════════════
task.wait(0.5)

-- 创建 FOV 圆和瞄准线
fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 2
fovCircle.Filled = false
fovCircle.Transparency = SETTINGS.FOVCircleTransparency
fovCircle.Color = SETTINGS.FOVCircleColor
fovCircle.Visible = false
fovCircle.Radius = 10

aimLine = Drawing.new("Line")
aimLine.Thickness = 2
aimLine.Transparency = 0.7
aimLine.Visible = false

fovConnection = RunService.RenderStepped:Connect(function()
    updateFOVCircle()
    updateAimLine()
end)

-- 创建状态文本
statsText = Drawing.new("Text")
statsText.Visible = true
statsText.Position = Vector2.new(10, Camera.ViewportSize.Y - 70)
statsText.Text = "Ally: 0  Enemy: 0  [手动队友:0]  [NORM]  Wall: OFF  Aim: ON\nAimPart: Head  Trigger: WAIT  ESP: ON  Smart: OFF  Prob: OFF  NPC: OFF"
statsText.Color = Color3.new(0,1,0)
statsText.Size = 14
statsText.Center = false
statsText.Outline = true
statsText.OutlineColor = Color3.new(0,0,0)

statusText = Drawing.new("Text")
statusText.Visible = true
statusText.Position = Vector2.new(10, Camera.ViewportSize.Y - 30)
statusText.Text = "ESP: ON"
statusText.Color = Color3.new(0,1,0)
statusText.Size = 18
statusText.Center = false
statusText.Outline = true
statusText.OutlineColor = Color3.new(0,0,0)

-- 初始化玩家 ESP
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then createESP(player) end
end

-- 玩家添加/移除事件
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        if isDestroyed then return end
        task.wait(0.1)
        if espObjects[player] then
            local obj = espObjects[player]
            if obj.Highlight then
                obj.Highlight.Adornee = player.Character
                obj.Highlight.Parent = player.Character
                obj.Highlight.Enabled = SETTINGS.ShowHighlight
                obj.Character = player.Character
            end
        else
            createESP(player)
        end
    end)
end)
Players.PlayerRemoving:Connect(function(player)
    if isDestroyed then return end
    removeESP(player, false)
    if deathLabelsAll[player] then
        deathLabelsAll[player].label:Remove()
        deathLabelsAll[player] = nil
    end
    if manualTeammates[player] then
        manualTeammates[player] = nil
    end
end)

-- 主循环
heartbeatConnection = RunService.Heartbeat:Connect(updateESP)

-- 视口变化
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    if isDestroyed then return end
    if statusText then
        statusText.Position = Vector2.new(10, Camera.ViewportSize.Y - 30)
    end
    if statsText then
        statsText.Position = Vector2.new(10, Camera.ViewportSize.Y - 70)
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 14. 快捷键绑定
-- ══════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or isDestroyed then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        SETTINGS.Enabled = not SETTINGS.Enabled
        if Window and Window.Flags and Window.Flags["ESP_Enabled"] then
            pcall(function() Window.Flags["ESP_Enabled"]:Set(SETTINGS.Enabled) end)
        end
        notify("ESP", SETTINGS.Enabled and "已开启" or "已关闭", 2, SETTINGS.Enabled and "Success" or "Warning")
    elseif input.KeyCode == Enum.KeyCode.Delete then
        destroyScript()
    -- [MOD] F2: 标记附近所有玩家为队友
    elseif input.KeyCode == Enum.KeyCode.F2 then
        local localChar = LocalPlayer.Character
        if not localChar then
            notify("手动队友", "你尚未生成角色", 2, "Warning")
            return
        end
        local localRoot = localChar:FindFirstChild("HumanoidRootPart")
        if not localRoot then
            notify("手动队友", "无法获取位置", 2, "Warning")
            return
        end
        local radius = SETTINGS.ManualTeammateRadius or 50
        local count = 0
        for _, player in pairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local char = player.Character
            if not char then continue end
            local root = char:FindFirstChild("HumanoidRootPart")
            if not root then continue end
            local dist = (root.Position - localRoot.Position).Magnitude
            if dist <= radius then
                if not manualTeammates[player] then
                    manualTeammates[player] = true
                    count = count + 1
                end
            end
        end
        notify("手动队友",
            string.format("已将 %d 名附近玩家标记为队友 (半径 %.0f)", count, radius),
            3, "Success")
    -- [MOD] F3: 清除所有手动队友
    elseif input.KeyCode == Enum.KeyCode.F3 then
        for player in pairs(manualTeammates) do
            manualTeammates[player] = nil
        end
        notify("手动队友", "已清除所有手动队友标记", 2, "Info")
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 15. 自瞄右键控制
-- ══════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if isDestroyed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        if SETTINGS.AimbotEnabled then
            aimbotActive = true
            if not aimbotConnection then
                aimbotConnection = RunService.RenderStepped:Connect(updateAimbot)
            end
            notify("自瞄", "自瞄已激活（右键按住）", 1, "Info")
        else
            notify("自瞄", "自瞄已禁用，请在 UI 中开启", 1, "Warning")
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if isDestroyed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        if aimbotActive then
            aimbotActive = false
            if aimbotConnection then
                aimbotConnection:Disconnect()
                aimbotConnection = nil
            end
            notify("自瞄", "自瞄已释放", 1, "Info")
        end
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 16. 加载完成通知
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
notify("✅ FPS 辅助加载完成!",
    "Quantum UI 版本 v20.0\n" ..
    "按右 Ctrl 切换 UI 显示\n" ..
    "前往 Settings 保存你的配置!",
    6, "Success")

print("========================================")
print(" FPS 辅助 v20.0 (Quantum UI 版) 加载完成")
print("   Insert     - 开关 ESP")
print("   Delete     - 彻底销毁")
print("   右 Ctrl    - 隐藏/显示 UI")
print("   F2         - 标记附近玩家为队友")
print("   F3         - 清除所有手动队友")
print("   鼠标右键   - 自瞄（需在 UI 中开启）")
print("   Settings Tab - 保存/加载配置")
print("========================================")
