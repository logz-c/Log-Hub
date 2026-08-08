--[[
    FPS 辅助脚本 v19.2 (增强版)
    功能：ESP、自瞄、扳机、概率瞄准、NPC透视（含队伍检测）
    快捷键：
        Insert     - 开关ESP
        Delete     - 彻底销毁脚本
        右Ctrl     - 隐藏/显示UI
        F2         - 标记附近所有玩家为队友（新增）
        F3         - 清除所有手动队友标记（新增）
    所有其他功能均通过UI面板操作。
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Camera = workspace.CurrentCamera
local CoreGui = game:GetService("CoreGui")
local Workspace = workspace

-- 预设颜色
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

-- ============ 设置表 ============
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
    -- [MOD] 手动队友标记半径
    ManualTeammateRadius = 50,
}

-- ============ 全局变量 ============
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
local colorPickerGui = nil
local aimLine = nil
local ui = {}

-- [MOD] 手动队友列表 (键为玩家对象，值为true表示标记为队友)
local manualTeammates = {}

-- ============ 工具函数 ============

local function getCharParts(character)
    if not character then return nil, nil end
    return character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("Humanoid")
end

-- 强化版队伍检测（玩家与玩家）
local function isTeammate(player1, player2)
    if player1 == player2 then return true end
    -- [MOD] 单向手动队友标记：只要 player2 在手动列表中就视为队友
    if manualTeammates[player2] then return true end

    if SETTINGS.ForceAllEnemy then return false end

    -- 自定义标签优先
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

    -- 自动检测
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

-- [MOD] 通用队伍比较（支持玩家和NPC），优先使用手动队友
local function isSameTeam(entity1, entity2)
    if entity1 == entity2 then return true end
    -- 如果两个都是玩家，直接使用 isTeammate（含手动标记）
    if entity1:IsA("Player") and entity2:IsA("Player") then
        return isTeammate(entity1, entity2)
    end

    if SETTINGS.ForceAllEnemy then return false end

    -- 自定义标签优先（适用于两者）
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

    -- 自动检测Team和TeamColor
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

-- 改进的NPC检测（增加名称关键词匹配）
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

-- ============ ESP 核心 ============

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

-- ============ 扳机 ============
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
    if ui.BtnTrigger then
        ui.BtnTrigger.Text = "开启"
        ui.BtnTrigger.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
    end
    StarterGui:SetCore("SendNotification", {
        Title = "扳机",
        Text = "扳机已启用，请通过UI开关",
        Duration = 3,
    })
    print("扳机功能已加载")
end

-- ============ FOV圆和瞄准线 ============
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

-- ============ 核心更新循环 ============
local function updateESP()
    if isDestroyed then return end
    local success, err = pcall(function()
        if not SETTINGS.Enabled then
            for _, obj in pairs(espObjects) do
                obj.Name.Visible = false
                obj.Health.Visible = false
                obj.Dist.Visible = false
                obj.HealthBar.Visible = false
                obj.HeadDot.Visible = false
                if obj.Highlight then obj.Highlight.Enabled = false end
                if obj.BoneLines then
                    for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                end
            end
            for _, obj in pairs(npcEspObjects) do
                obj.Name.Visible = false
                obj.Health.Visible = false
                obj.Dist.Visible = false
                obj.HealthBar.Visible = false
                obj.HeadDot.Visible = false
                if obj.Highlight then obj.Highlight.Enabled = false end
                if obj.BoneLines then
                    for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                end
            end
            for _, data in pairs(deathLabelsAll) do data.label.Visible = false end
            if statsText then
                statsText.Text = "ESP OFF"
                statsText.Color = Color3.new(1,0,0)
            end
            return
        end

        local localChar = LocalPlayer.Character
        if not localChar then return end
        local localRoot = localChar:FindFirstChild("HumanoidRootPart")
        if not localRoot then return end

        pulsePhase = (pulsePhase + 0.02) % (2 * math.pi)
        local aliveTeammates = 0
        local aliveEnemies = 0
        local manualTeamCount = 0
        for _ in pairs(manualTeammates) do manualTeamCount = manualTeamCount + 1 end

        -- ===== 处理玩家 =====
        for _, player in pairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local char = player.Character
            local obj = espObjects[player]
            if not obj then
                createESP(player)
                obj = espObjects[player]
            end
            if not char then
                if not deathLabelsAll[player] then
                    obj.Name.Visible = false
                    obj.Health.Visible = false
                    obj.Dist.Visible = false
                    obj.HealthBar.Visible = false
                    obj.HeadDot.Visible = false
                    if obj.BoneLines then
                        for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                    end
                    if obj.Highlight then obj.Highlight.Enabled = false end
                end
                continue
            end
            if obj.Highlight then
                if obj.Character ~= char then
                    obj.Highlight.Adornee = char
                    obj.Highlight.Parent = char
                    obj.Character = char
                end
                obj.Highlight.Enabled = SETTINGS.ShowHighlight
            end

            local root, humanoid = getCharParts(char)
            local head = char:FindFirstChild("Head")
            if not root or not humanoid or not head then
                obj.Name.Visible = false
                obj.Health.Visible = false
                obj.Dist.Visible = false
                obj.HealthBar.Visible = false
                obj.HeadDot.Visible = false
                if obj.BoneLines then
                    for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                end
                continue
            end

            local isDead = (humanoid.Health <= 0)
            local rootPos, rootVis = Camera:WorldToViewportPoint(root.Position)
            local headPos, headVis = Camera:WorldToViewportPoint(head.Position)

            if isDead and not obj.IsDead then
                obj.IsDead = true
                if headVis then
                    spawnDeathLabel(player, headPos, false)
                else
                    spawnDeathLabel(player, Vector2.new(rootPos.X, rootPos.Y - 3), false)
                end
            elseif not isDead then
                obj.IsDead = false
                if deathLabelsAll[player] then
                    deathLabelsAll[player].label.Visible = false
                    deathLabelsAll[player].label:Remove()
                    deathLabelsAll[player] = nil
                end
            end

            if isDead then
                obj.Name.Visible = false
                obj.Health.Visible = false
                obj.Dist.Visible = false
                obj.HealthBar.Visible = false
                obj.HeadDot.Visible = false
                if obj.BoneLines then
                    for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                end
                if obj.Highlight then obj.Highlight.Enabled = false end
                continue
            end

            if not rootVis or not headVis then
                obj.Name.Visible = false
                obj.Health.Visible = false
                obj.Dist.Visible = false
                obj.HealthBar.Visible = false
                obj.HeadDot.Visible = false
                if obj.BoneLines then
                    for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                end
                continue
            end

            local distance = (root.Position - localRoot.Position).Magnitude
            local isTeammateFlag = isTeammate(LocalPlayer, player)

            if not isDead then
                if isTeammateFlag then
                    aliveTeammates = aliveTeammates + 1
                else
                    aliveEnemies = aliveEnemies + 1
                end
            end

            local visible = false
            local targetColor = SETTINGS.EnemyColor
            if isTeammateFlag then
                targetColor = SETTINGS.TeammateColor
                visible = true
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
            elseif obj.Highlight then
                obj.Highlight.Enabled = false
            end

            local centerX = rootPos.X
            local headY = headPos.Y
            local nameY = headY - 25
            local hpY = headY + 5
            local distY = hpY

            if SETTINGS.ShowName then
                obj.Name.Position = Vector2.new(centerX, nameY)
                if isTeammateFlag then
                    obj.Name.Text = player.Name .. " (队友)"
                else
                    obj.Name.Text = player.Name
                end
                obj.Name.Color = Color3.new(1,1,1)
                obj.Name.Size = math.max(8, SETTINGS.FontSizeName * distFactor)
                obj.Name.Transparency = 1 - distFactor
                obj.Name.Visible = true
            else
                obj.Name.Visible = false
            end

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
            else
                obj.Health.Visible = false
                obj.HealthBar.Visible = false
            end

            if SETTINGS.ShowDistance then
                obj.Dist.Position = Vector2.new(centerX + 10, distY)
                obj.Dist.Text = string.format("%.0fm", distance)
                local distRatio = math.min(distance / SETTINGS.MaxRenderDistance, 1)
                obj.Dist.Color = Color3.new(1 - distRatio, distRatio, 0)
                obj.Dist.Size = math.max(8, SETTINGS.FontSizeInfo * distFactor)
                obj.Dist.Transparency = 1 - distFactor
                obj.Dist.Visible = true
            else
                obj.Dist.Visible = false
            end

            if SETTINGS.ShowHeadDot then
                obj.HeadDot.Position = Vector2.new(headPos.X, headPos.Y)
                obj.HeadDot.Color = obj.CurrentColor
                obj.HeadDot.Transparency = 0.3 + (1 - distFactor) * 0.4
                obj.HeadDot.Visible = true
            else
                obj.HeadDot.Visible = false
            end

            if SETTINGS.ShowBones then
                local joints
                if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
                    joints = {
                        {"Head", "UpperTorso"},
                        {"UpperTorso", "LowerTorso"},
                        {"UpperTorso", "LeftUpperArm"},
                        {"LeftUpperArm", "LeftLowerArm"},
                        {"LeftLowerArm", "LeftHand"},
                        {"UpperTorso", "RightUpperArm"},
                        {"RightUpperArm", "RightLowerArm"},
                        {"RightLowerArm", "RightHand"},
                        {"LowerTorso", "LeftUpperLeg"},
                        {"LeftUpperLeg", "LeftLowerLeg"},
                        {"LeftLowerLeg", "LeftFoot"},
                        {"LowerTorso", "RightUpperLeg"},
                        {"RightUpperLeg", "RightLowerLeg"},
                        {"RightLowerLeg", "RightFoot"}
                    }
                else
                    joints = {
                        {"Head", "Torso"},
                        {"Torso", "Left Arm"},
                        {"Torso", "Right Arm"},
                        {"Torso", "Left Leg"},
                        {"Torso", "Right Leg"}
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
                        else
                            line.Visible = false
                        end
                    else
                        line.Visible = false
                    end
                end
                for i = #joints + 1, #lines do
                    lines[i].Visible = false
                end
            else
                if obj.BoneLines then
                    for _, line in ipairs(obj.BoneLines) do
                        line.Visible = false
                    end
                end
            end
        end -- 玩家循环

        -- ===== 处理NPC =====
        if SETTINGS.ShowNPC then
            for _, model in ipairs(Workspace:GetDescendants()) do
                if model:IsA("Model") and isNPC(model) then
                    local obj = npcEspObjects[model]
                    if not obj then
                        createNPCESP(model)
                        obj = npcEspObjects[model]
                    end
                    local char = model
                    local root, humanoid = getCharParts(char)
                    if not root then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then
                            root = hum.RootPart
                        end
                    end
                    local head = char:FindFirstChild("Head")
                    if not head and root then
                        head = root
                    end
                    if not root or not humanoid or not head then
                        obj.Name.Visible = false
                        obj.Health.Visible = false
                        obj.Dist.Visible = false
                        obj.HealthBar.Visible = false
                        obj.HeadDot.Visible = false
                        if obj.BoneLines then
                            for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                        end
                        if obj.Highlight then obj.Highlight.Enabled = false end
                        continue
                    end

                    local isDead = (humanoid.Health <= 0)
                    local rootPos, rootVis = Camera:WorldToViewportPoint(root.Position)
                    local headPos, headVis = Camera:WorldToViewportPoint(head.Position)

                    if isDead and not obj.IsDead then
                        obj.IsDead = true
                        if headVis then
                            spawnDeathLabel(model, headPos, true)
                        else
                            spawnDeathLabel(model, Vector2.new(rootPos.X, rootPos.Y - 3), true)
                        end
                    elseif not isDead then
                        obj.IsDead = false
                        if deathLabelsAll[model] then
                            deathLabelsAll[model].label.Visible = false
                            deathLabelsAll[model].label:Remove()
                            deathLabelsAll[model] = nil
                        end
                    end

                    if isDead then
                        obj.Name.Visible = false
                        obj.Health.Visible = false
                        obj.Dist.Visible = false
                        obj.HealthBar.Visible = false
                        obj.HeadDot.Visible = false
                        if obj.BoneLines then
                            for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                        end
                        if obj.Highlight then obj.Highlight.Enabled = false end
                        continue
                    end

                    if not rootVis or not headVis then
                        obj.Name.Visible = false
                        obj.Health.Visible = false
                        obj.Dist.Visible = false
                        obj.HealthBar.Visible = false
                        obj.HeadDot.Visible = false
                        if obj.BoneLines then
                            for _, line in ipairs(obj.BoneLines) do line.Visible = false end
                        end
                        continue
                    end

                    local distance = (root.Position - localRoot.Position).Magnitude

                    local isTeammateFlag = false
                    if isSameTeam(LocalPlayer, char) then
                        isTeammateFlag = true
                    end

                    local visible = true
                    local targetColor = SETTINGS.EnemyColor
                    if isTeammateFlag then
                        targetColor = SETTINGS.TeammateColor
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
                    elseif obj.Highlight then
                        obj.Highlight.Enabled = false
                    end

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
                    else
                        obj.Name.Visible = false
                    end

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
                    else
                        obj.Health.Visible = false
                        obj.HealthBar.Visible = false
                    end

                    if SETTINGS.ShowDistance then
                        obj.Dist.Position = Vector2.new(centerX + 10, distY)
                        obj.Dist.Text = string.format("%.0fm", distance)
                        local distRatio = math.min(distance / SETTINGS.MaxRenderDistance, 1)
                        obj.Dist.Color = Color3.new(1 - distRatio, distRatio, 0)
                        obj.Dist.Size = math.max(8, SETTINGS.FontSizeInfo * distFactor)
                        obj.Dist.Transparency = 1 - distFactor
                        obj.Dist.Visible = true
                    else
                        obj.Dist.Visible = false
                    end

                    if SETTINGS.ShowHeadDot then
                        obj.HeadDot.Position = Vector2.new(headPos.X, headPos.Y)
                        obj.HeadDot.Color = obj.CurrentColor
                        obj.HeadDot.Transparency = 0.3 + (1 - distFactor) * 0.4
                        obj.HeadDot.Visible = true
                    else
                        obj.HeadDot.Visible = false
                    end

                    if SETTINGS.ShowBones then
                        local joints
                        if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
                            joints = {
                                {"Head", "UpperTorso"},
                                {"UpperTorso", "LowerTorso"},
                                {"UpperTorso", "LeftUpperArm"},
                                {"LeftUpperArm", "LeftLowerArm"},
                                {"LeftLowerArm", "LeftHand"},
                                {"UpperTorso", "RightUpperArm"},
                                {"RightUpperArm", "RightLowerArm"},
                                {"RightLowerArm", "RightHand"},
                                {"LowerTorso", "LeftUpperLeg"},
                                {"LeftUpperLeg", "LeftLowerLeg"},
                                {"LeftLowerLeg", "LeftFoot"},
                                {"LowerTorso", "RightUpperLeg"},
                                {"RightUpperLeg", "RightLowerLeg"},
                                {"RightLowerLeg", "RightFoot"}
                            }
                        else
                            joints = {
                                {"Head", "Torso"},
                                {"Torso", "Left Arm"},
                                {"Torso", "Right Arm"},
                                {"Torso", "Left Leg"},
                                {"Torso", "Right Leg"}
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
                                else
                                    line.Visible = false
                                end
                            else
                                line.Visible = false
                            end
                        end
                        for i = #joints + 1, #lines do
                            lines[i].Visible = false
                        end
                    else
                        if obj.BoneLines then
                            for _, line in ipairs(obj.BoneLines) do
                                line.Visible = false
                            end
                        end
                    end
                end -- end if isNPC
            end -- end for descendants
        end -- end if ShowNPC

        -- 更新统计信息
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

        -- 清理不存在的玩家ESP
        for player, _ in pairs(espObjects) do
            if not Players:FindFirstChild(player.Name) then
                removeESP(player, false)
            end
        end
        for model, _ in pairs(npcEspObjects) do
            if not model.Parent or not isNPC(model) then
                removeESP(model, true)
            end
        end
    end)
    if not success then
        warn("ESP Update error:", err)
    end
end

-- ============ 自瞄更新 ============
local function updateAimbot()
    if not aimbotActive or not SETTINGS.Enabled or not SETTINGS.AimbotEnabled or isDestroyed then
        return
    end
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

-- ============ 销毁 ============
local function destroyScript()
    if isDestroyed then return end
    isDestroyed = true

    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    if deathHeartbeat then
        deathHeartbeat:Disconnect()
        deathHeartbeat = nil
    end
    if aimbotConnection then
        aimbotConnection:Disconnect()
        aimbotConnection = nil
    end
    if fovConnection then
        fovConnection:Disconnect()
        fovConnection = nil
    end
    if triggerbotEvents and triggerbotEvents.move then
        triggerbotEvents.move:Disconnect()
        triggerbotEvents = nil
    end

    for player, obj in pairs(espObjects) do
        removeESP(player, false)
    end
    espObjects = {}
    for model, obj in pairs(npcEspObjects) do
        removeESP(model, true)
    end
    npcEspObjects = {}

    for _, data in pairs(deathLabelsAll) do
        if data.label then data.label:Remove() end
    end
    deathLabelsAll = {}

    if fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end
    if aimLine then
        aimLine:Remove()
        aimLine = nil
    end
    if statusText then
        statusText:Remove()
        statusText = nil
    end
    if statsText then
        statsText:Remove()
        statsText = nil
    end
    if ui.MainFrame then
        ui.MainFrame:Destroy()
        ui.MainFrame = nil
    end
    if colorPickerGui then
        colorPickerGui:Destroy()
        colorPickerGui = nil
    end
    print("脚本已彻底销毁")
end

-- ============ 颜色选择器 ============
local function showColorPicker(callback, currentColor)
    if colorPickerGui then
        colorPickerGui:Destroy()
        colorPickerGui = nil
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ColorPicker"
    gui.ResetOnSpawn = false
    gui.Parent = CoreGui

    local overlay = Instance.new("Frame")
    overlay.Parent = gui
    overlay.BackgroundColor3 = Color3.fromRGB(0,0,0)
    overlay.BackgroundTransparency = 0.4
    overlay.Size = UDim2.new(1,0,1,0)
    overlay.BorderSizePixel = 0

    local frame = Instance.new("Frame")
    frame.Parent = gui
    frame.BackgroundColor3 = Color3.fromRGB(45,45,45)
    frame.BorderSizePixel = 0
    frame.Position = UDim2.new(0.5, -150, 0.5, -80)
    frame.Size = UDim2.new(0, 300, 0, 160)
    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 8)
    frameCorner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1,0,0,30)
    title.Text = "选择颜色"
    title.TextColor3 = Color3.fromRGB(225,225,225)
    title.TextSize = 16
    title.Font = Enum.Font.GothamSemibold
    title.TextXAlignment = Enum.TextXAlignment.Center

    local colorContainer = Instance.new("Frame")
    colorContainer.Parent = frame
    colorContainer.BackgroundTransparency = 1
    colorContainer.Position = UDim2.new(0, 10, 0, 35)
    colorContainer.Size = UDim2.new(1, -20, 0, 85)

    local flow = Instance.new("UIGridLayout")
    flow.Parent = colorContainer
    flow.CellSize = UDim2.new(0, 40, 0, 35)
    flow.CellPadding = UDim2.new(0, 8, 0, 8)
    flow.SortOrder = Enum.SortOrder.LayoutOrder

    for _, color in ipairs(PRESET_COLORS) do
        local btn = Instance.new("TextButton")
        btn.Parent = colorContainer
        btn.BackgroundColor3 = color
        btn.BorderSizePixel = 0
        btn.Size = UDim2.new(0, 40, 0, 35)
        btn.Text = ""
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = btn
        btn.MouseButton1Click:Connect(function()
            callback(color)
            gui:Destroy()
            colorPickerGui = nil
        end)
    end

    local closeBtn = Instance.new("TextButton")
    closeBtn.Parent = frame
    closeBtn.BackgroundTransparency = 1
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -30, 0, 0)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(225,225,225)
    closeBtn.TextSize = 18
    closeBtn.Font = Enum.Font.GothamSemibold
    closeBtn.BorderSizePixel = 0
    closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
        colorPickerGui = nil
    end)

    overlay.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            gui:Destroy()
            colorPickerGui = nil
        end
    end)

    colorPickerGui = gui
end

local function createColorPicker(parent, labelText, initialColor, callback)
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(1, 0, 0, 30)

    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.5, -10, 1, 0)
    label.Position = UDim2.new(0, 5, 0, 0)
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(225,225,225)
    label.TextSize = 13
    label.Font = Enum.Font.GothamSemibold
    label.TextXAlignment = Enum.TextXAlignment.Left

    local pickerBtn = Instance.new("TextButton")
    pickerBtn.Parent = frame
    pickerBtn.Size = UDim2.new(0, 100, 0, 24)
    pickerBtn.Position = UDim2.new(1, -105, 0, 3)
    pickerBtn.BackgroundColor3 = initialColor
    pickerBtn.BorderSizePixel = 0
    pickerBtn.Text = "选择"
    pickerBtn.TextColor3 = Color3.fromRGB(225,225,225)
    pickerBtn.TextSize = 11
    pickerBtn.Font = Enum.Font.GothamSemibold
    local pickerCorner = Instance.new("UICorner")
    pickerCorner.CornerRadius = UDim.new(0, 4)
    pickerCorner.Parent = pickerBtn

    local colorPreview = Instance.new("Frame")
    colorPreview.Parent = pickerBtn
    colorPreview.BackgroundColor3 = initialColor
    colorPreview.BorderSizePixel = 0
    colorPreview.Size = UDim2.new(0, 20, 1, -4)
    colorPreview.Position = UDim2.new(0, 4, 0, 2)
    local previewCorner = Instance.new("UICorner")
    previewCorner.CornerRadius = UDim.new(0, 3)
    previewCorner.Parent = colorPreview

    pickerBtn.MouseButton1Click:Connect(function()
        showColorPicker(function(newColor)
            pickerBtn.BackgroundColor3 = newColor
            colorPreview.BackgroundColor3 = newColor
            callback(newColor)
        end, pickerBtn.BackgroundColor3)
    end)

    return pickerBtn
end

-- ============ UI 创建 ============
local function createSlider(parent, labelText, minVal, maxVal, initialVal, callback)
    local frame = Instance.new("Frame")
    frame.Parent = parent
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.new(1, 0, 0, 32)
    frame.AutomaticSize = Enum.AutomaticSize.None

    local label = Instance.new("TextLabel")
    label.Parent = frame
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.45, -5, 1, 0)
    label.Position = UDim2.new(0, 5, 0, 0)
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(210, 220, 240)
    label.TextSize = 13
    label.Font = Enum.Font.GothamSemibold
    label.TextXAlignment = Enum.TextXAlignment.Left

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Parent = frame
    valueLabel.BackgroundTransparency = 1
    valueLabel.Size = UDim2.new(0, 40, 1, 0)
    valueLabel.Position = UDim2.new(0.45, 0, 0, 0)
    valueLabel.Text = string.format("%.0f", initialVal)
    valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    valueLabel.TextSize = 12
    valueLabel.Font = Enum.Font.GothamSemibold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Center

    local track = Instance.new("Frame")
    track.Parent = frame
    track.BackgroundColor3 = Color3.fromRGB(60, 65, 80)
    track.BorderSizePixel = 0
    track.Size = UDim2.new(0, 120, 0, 6)
    track.Position = UDim2.new(1, -125, 0, 13)
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Parent = track
    fill.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new((initialVal - minVal) / (maxVal - minVal), 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local knob = Instance.new("TextButton")
    knob.Parent = track
    knob.BackgroundColor3 = Color3.fromRGB(220, 220, 240)
    knob.BorderSizePixel = 0
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    local percent = (initialVal - minVal) / (maxVal - minVal)
    knob.Position = UDim2.new(percent, 0, 0.5, 0)
    knob.Text = ""
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function updateSlider(value)
        local clamped = math.clamp(value, minVal, maxVal)
        local percent = (clamped - minVal) / (maxVal - minVal)
        fill.Size = UDim2.new(percent, 0, 1, 0)
        knob.Position = UDim2.new(percent, 0, 0.5, 0)
        valueLabel.Text = string.format("%.0f", clamped)
        callback(clamped)
    end

    local dragging = false
    local connections = {}

    local function startDrag()
        dragging = true
        local moveConn = UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
                local trackAbsPos = track.AbsolutePosition
                local trackSize = track.AbsoluteSize.X
                local mouseX = input.Position.X
                local relativeX = math.clamp((mouseX - trackAbsPos.X) / trackSize, 0, 1)
                local newVal = minVal + relativeX * (maxVal - minVal)
                updateSlider(newVal)
            end
        end)
        local endConn = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
                moveConn:Disconnect()
                endConn:Disconnect()
                connections = {}
            end
        end)
        connections = {moveConn, endConn}
    end

    knob.MouseButton1Down:Connect(startDrag)
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local trackAbsPos = track.AbsolutePosition
            local trackSize = track.AbsoluteSize.X
            local mouseX = input.Position.X
            local relativeX = math.clamp((mouseX - trackAbsPos.X) / trackSize, 0, 1)
            local newVal = minVal + relativeX * (maxVal - minVal)
            updateSlider(newVal)
            if not dragging then
                startDrag()
            end
        end
    end)

    return {
        SetValue = updateSlider,
        GetValue = function() return tonumber(valueLabel.Text) end,
        Knob = knob,
        Fill = fill,
        ValueLabel = valueLabel,
    }
end

local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FPS_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = CoreGui

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Parent = screenGui
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    mainFrame.BackgroundTransparency = 0.15
    mainFrame.BorderSizePixel = 0
    mainFrame.Position = UDim2.new(0.02, 0, 0.1, 0)
    mainFrame.Size = UDim2.new(0, 340, 0, 720)
    mainFrame.ClipsDescendants = true
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = mainFrame

    local shadow = Instance.new("Frame")
    shadow.Parent = mainFrame
    shadow.BackgroundColor3 = Color3.fromRGB(0,0,0)
    shadow.BackgroundTransparency = 0.5
    shadow.BorderSizePixel = 0
    shadow.Size = UDim2.new(1, 0, 1, 0)
    shadow.Position = UDim2.new(0, 0, 0, 0)
    shadow.ZIndex = 0
    local shadowCorner = Instance.new("UICorner")
    shadowCorner.CornerRadius = UDim.new(0, 12)
    shadowCorner.Parent = shadow

    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Parent = mainFrame
    titleBar.BackgroundColor3 = Color3.fromRGB(60, 70, 90)
    titleBar.BorderSizePixel = 0
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 12)
    titleCorner.Parent = titleBar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Parent = titleBar
    titleLabel.BackgroundTransparency = 1
    titleLabel.Size = UDim2.new(1, -30, 1, 0)
    titleLabel.Position = UDim2.new(0, 10, 0, 0)
    titleLabel.Text = "FPS 辅助 v19.2 (增强版)"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 16
    titleLabel.Font = Enum.Font.GothamSemibold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left

    local closeBtn = Instance.new("TextButton")
    closeBtn.Parent = titleBar
    closeBtn.BackgroundTransparency = 1
    closeBtn.Size = UDim2.new(0, 30, 1, 0)
    closeBtn.Position = UDim2.new(1, -30, 0, 0)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 18
    closeBtn.Font = Enum.Font.GothamSemibold
    closeBtn.BorderSizePixel = 0
    closeBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
        local status = mainFrame.Visible and "显示" or "隐藏"
        StarterGui:SetCore("SendNotification", { Title = "UI", Text = "界面已" .. status, Duration = 2 })
    end)

    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Parent = mainFrame
    scrollFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    scrollFrame.BackgroundTransparency = 0.2
    scrollFrame.BorderSizePixel = 0
    scrollFrame.Position = UDim2.new(0, 0, 0, 30)
    scrollFrame.Size = UDim2.new(1, 0, 1, -30)
    scrollFrame.ScrollBarThickness = 6
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 120, 150)
    scrollFrame.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 12)
    scrollCorner.Parent = scrollFrame

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Parent = scrollFrame
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, -10, 0, 0)
    content.Position = UDim2.new(0, 5, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y

    local layout = Instance.new("UIListLayout")
    layout.Parent = content
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 12)

    local function createSection(title)
        local section = Instance.new("Frame")
        section.Parent = content
        section.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
        section.BackgroundTransparency = 0.3
        section.BorderSizePixel = 0
        section.Size = UDim2.new(1, 0, 0, 0)
        section.AutomaticSize = Enum.AutomaticSize.Y
        local secCorner = Instance.new("UICorner")
        secCorner.CornerRadius = UDim.new(0, 8)
        secCorner.Parent = section

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Parent = section
        titleLabel.BackgroundTransparency = 1
        titleLabel.Size = UDim2.new(1, -10, 0, 24)
        titleLabel.Position = UDim2.new(0, 5, 0, 5)
        titleLabel.Text = title
        titleLabel.TextColor3 = Color3.fromRGB(220, 230, 255)
        titleLabel.TextSize = 14
        titleLabel.Font = Enum.Font.GothamSemibold
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left

        local line = Instance.new("Frame")
        line.Parent = section
        line.BackgroundColor3 = Color3.fromRGB(80, 100, 130)
        line.BackgroundTransparency = 0.5
        line.BorderSizePixel = 0
        line.Size = UDim2.new(1, -10, 0, 1)
        line.Position = UDim2.new(0, 5, 0, 34)

        local items = Instance.new("Frame")
        items.Parent = section
        items.BackgroundTransparency = 1
        items.Size = UDim2.new(1, 0, 0, 0)
        items.Position = UDim2.new(0, 0, 0, 40)
        items.AutomaticSize = Enum.AutomaticSize.Y

        local itemLayout = Instance.new("UIListLayout")
        itemLayout.Parent = items
        itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
        itemLayout.Padding = UDim.new(0, 4)

        return items
    end

    local function createToggle(parent, labelText, initialValue, callback)
        local frame = Instance.new("Frame")
        frame.Parent = parent
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.new(1, 0, 0, 28)
        frame.AutomaticSize = Enum.AutomaticSize.None

        local label = Instance.new("TextLabel")
        label.Parent = frame
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0.7, -10, 1, 0)
        label.Position = UDim2.new(0, 5, 0, 0)
        label.Text = labelText
        label.TextColor3 = Color3.fromRGB(210, 220, 240)
        label.TextSize = 13
        label.Font = Enum.Font.GothamSemibold
        label.TextXAlignment = Enum.TextXAlignment.Left

        local btn = Instance.new("TextButton")
        btn.Parent = frame
        btn.Size = UDim2.new(0, 60, 1, -4)
        btn.Position = UDim2.new(1, -65, 0, 2)
        btn.BackgroundColor3 = initialValue and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(80, 80, 90)
        btn.BorderSizePixel = 0
        btn.Text = initialValue and "开启" or "关闭"
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamSemibold
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            local newVal = not (btn.Text == "开启")
            btn.Text = newVal and "开启" or "关闭"
            btn.BackgroundColor3 = newVal and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(80, 80, 90)
            callback(newVal)
        end)

        return btn
    end

    local function createTextBox(parent, labelText, initialValue, callback)
        local frame = Instance.new("Frame")
        frame.Parent = parent
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.new(1, 0, 0, 28)

        local label = Instance.new("TextLabel")
        label.Parent = frame
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0.6, -10, 1, 0)
        label.Position = UDim2.new(0, 5, 0, 0)
        label.Text = labelText
        label.TextColor3 = Color3.fromRGB(210, 220, 240)
        label.TextSize = 13
        label.Font = Enum.Font.GothamSemibold
        label.TextXAlignment = Enum.TextXAlignment.Left

        local box = Instance.new("TextBox")
        box.Parent = frame
        box.Size = UDim2.new(0, 60, 1, -4)
        box.Position = UDim2.new(1, -65, 0, 2)
        box.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
        box.BorderSizePixel = 0
        box.Text = tostring(initialValue)
        box.TextColor3 = Color3.fromRGB(255,255,255)
        box.TextSize = 12
        box.Font = Enum.Font.GothamSemibold
        local boxCorner = Instance.new("UICorner")
        boxCorner.CornerRadius = UDim.new(0, 4)
        boxCorner.Parent = box

        box.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                local val = tonumber(box.Text)
                if val then
                    callback(val)
                else
                    box.Text = tostring(initialValue)
                end
            end
        end)

        return box
    end

    local function createCycleButton(parent, labelText, options, initialIndex, callback)
        local frame = Instance.new("Frame")
        frame.Parent = parent
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.new(1, 0, 0, 28)

        local label = Instance.new("TextLabel")
        label.Parent = frame
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0.6, -10, 1, 0)
        label.Position = UDim2.new(0, 5, 0, 0)
        label.Text = labelText
        label.TextColor3 = Color3.fromRGB(210, 220, 240)
        label.TextSize = 13
        label.Font = Enum.Font.GothamSemibold
        label.TextXAlignment = Enum.TextXAlignment.Left

        local btn = Instance.new("TextButton")
        btn.Parent = frame
        btn.Size = UDim2.new(0, 80, 1, -4)
        btn.Position = UDim2.new(1, -85, 0, 2)
        btn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
        btn.BorderSizePixel = 0
        btn.Text = options[initialIndex + 1] or options[1]
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamSemibold
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = btn

        local currentIdx = initialIndex
        btn.MouseButton1Click:Connect(function()
            currentIdx = (currentIdx + 1) % #options
            btn.Text = options[currentIdx + 1]
            callback(currentIdx)
        end)

        return btn
    end

    -- ========== 构建UI ==========
    local espSection = createSection("ESP 设置")
    ui.BtnToggleESP = createToggle(espSection, "启用 ESP (Insert)", SETTINGS.Enabled, function(val)
        SETTINGS.Enabled = val
    end)
    ui.BtnShowName = createToggle(espSection, "显示名称", SETTINGS.ShowName, function(val)
        SETTINGS.ShowName = val
    end)
    ui.BtnShowHealth = createToggle(espSection, "显示血量", SETTINGS.ShowHealth, function(val)
        SETTINGS.ShowHealth = val
    end)
    ui.BtnShowDistance = createToggle(espSection, "显示距离", SETTINGS.ShowDistance, function(val)
        SETTINGS.ShowDistance = val
    end)
    ui.BtnShowHighlight = createToggle(espSection, "高亮显示", SETTINGS.ShowHighlight, function(val)
        SETTINGS.ShowHighlight = val
    end)
    ui.BtnShowBones = createToggle(espSection, "显示骨骼", SETTINGS.ShowBones, function(val)
        SETTINGS.ShowBones = val
    end)
    ui.BtnShowHeadDot = createToggle(espSection, "显示头部标记", SETTINGS.ShowHeadDot, function(val)
        SETTINGS.ShowHeadDot = val
    end)
    ui.BtnForceEnemy = createToggle(espSection, "强制全部敌对", SETTINGS.ForceAllEnemy, function(val)
        SETTINGS.ForceAllEnemy = val
    end)
    ui.TxtMaxDist = createTextBox(espSection, "最大渲染距离", SETTINGS.MaxRenderDistance, function(val)
        SETTINGS.MaxRenderDistance = val
    end)
    ui.SliderHighlightFill = createSlider(espSection, "高亮填充透明度", 0, 1, SETTINGS.HighlightFillTrans, function(val)
        SETTINGS.HighlightFillTrans = val
    end)
    ui.SliderHighlightOutline = createSlider(espSection, "高亮轮廓透明度", 0, 1, SETTINGS.HighlightOutlineTrans, function(val)
        SETTINGS.HighlightOutlineTrans = val
    end)

    local colorSection = createSection("ESP 颜色")
    ui.ColorPreviewEnemy = createColorPicker(colorSection, "敌人颜色", SETTINGS.EnemyColor, function(c)
        SETTINGS.EnemyColor = c
    end)
    ui.ColorPreviewTeammate = createColorPicker(colorSection, "队友颜色", SETTINGS.TeammateColor, function(c)
        SETTINGS.TeammateColor = c
    end)
    ui.ColorPreviewHidden = createColorPicker(colorSection, "隐藏颜色", SETTINGS.HiddenColor, function(c)
        SETTINGS.HiddenColor = c
    end)

    local aimSection = createSection("自瞄设置")
    ui.BtnAimbotToggle = createToggle(aimSection, "启用自瞄", SETTINGS.AimbotEnabled, function(val)
        SETTINGS.AimbotEnabled = val
        local status = val and "开启" or "关闭"
        StarterGui:SetCore("SendNotification", { Title = "自瞄", Text = "自瞄已" .. status, Duration = 2 })
    end)
    ui.TxtSmoothness = createTextBox(aimSection, "平滑度 (0~1)", SETTINGS.AimbotSmoothness, function(val)
        SETTINGS.AimbotSmoothness = math.clamp(val, 0, 1)
    end)
    ui.SliderFOV = createSlider(aimSection, "自瞄 FOV", 10, 180, SETTINGS.AimbotFOV, function(val)
        SETTINGS.AimbotFOV = val
    end)
    ui.BtnAimPart = createCycleButton(aimSection, "瞄准部位", {"头部", "躯干", "腿部"}, SETTINGS.AimPartIndex, function(idx)
        SETTINGS.AimPartIndex = idx
    end)
    ui.BtnWallCheck = createToggle(aimSection, "墙体检测", SETTINGS.AimbotCheckWall, function(val)
        SETTINGS.AimbotCheckWall = val
    end)
    ui.BtnShowFOV = createToggle(aimSection, "显示 FOV 圈", SETTINGS.ShowFOVCircle, function(val)
        SETTINGS.ShowFOVCircle = val
    end)
    ui.ColorPreviewFOV = createColorPicker(aimSection, "FOV 圈颜色", SETTINGS.FOVCircleColor, function(c)
        SETTINGS.FOVCircleColor = c
    end)
    ui.BtnSmartAim = createToggle(aimSection, "智能瞄准模式", SETTINGS.SmartAimMode, function(val)
        SETTINGS.SmartAimMode = val
        local status = val and "开启" or "关闭"
        StarterGui:SetCore("SendNotification", { Title = "智能瞄准", Text = "智能瞄准已" .. status, Duration = 2 })
    end)
    ui.BtnShowAimLine = createToggle(aimSection, "显示瞄准指示线", SETTINGS.ShowAimLine, function(val)
        SETTINGS.ShowAimLine = val
        if not val and aimLine then aimLine.Visible = false end
    end)

    local probSection = createSection("概率瞄准设置")
    ui.BtnEnableProbAim = createToggle(probSection, "启用概率瞄准", SETTINGS.EnableProbAim, function(val)
        SETTINGS.EnableProbAim = val
        local status = val and "开启" or "关闭"
        StarterGui:SetCore("SendNotification", { Title = "概率瞄准", Text = "概率瞄准已" .. status, Duration = 2 })
    end)
    ui.SliderHeadWeight = createSlider(probSection, "头部权重", 0, 100, SETTINGS.HeadWeight, function(val)
        SETTINGS.HeadWeight = val
        if SETTINGS.HeadWeight == 0 and SETTINGS.TorsoWeight == 0 and SETTINGS.LegWeight == 0 then
            SETTINGS.HeadWeight = 100
            ui.SliderHeadWeight:SetValue(100)
            StarterGui:SetCore("SendNotification", { Title = "权重", Text = "权重不能全为0，已自动调整头部为100", Duration = 2 })
        end
    end)
    ui.SliderTorsoWeight = createSlider(probSection, "躯干权重", 0, 100, SETTINGS.TorsoWeight, function(val)
        SETTINGS.TorsoWeight = val
        if SETTINGS.HeadWeight == 0 and SETTINGS.TorsoWeight == 0 and SETTINGS.LegWeight == 0 then
            SETTINGS.HeadWeight = 100
            ui.SliderHeadWeight:SetValue(100)
            StarterGui:SetCore("SendNotification", { Title = "权重", Text = "权重不能全为0，已自动调整头部为100", Duration = 2 })
        end
    end)
    ui.SliderLegWeight = createSlider(probSection, "腿部权重", 0, 100, SETTINGS.LegWeight, function(val)
        SETTINGS.LegWeight = val
        if SETTINGS.HeadWeight == 0 and SETTINGS.TorsoWeight == 0 and SETTINGS.LegWeight == 0 then
            SETTINGS.HeadWeight = 100
            ui.SliderHeadWeight:SetValue(100)
            StarterGui:SetCore("SendNotification", { Title = "权重", Text = "权重不能全为0，已自动调整头部为100", Duration = 2 })
        end
    end)

    local triggerSection = createSection("扳机设置")
    ui.BtnTrigger = createToggle(triggerSection, "启用扳机", SETTINGS.TriggerBot, function(val)
        if val then
            if not SETTINGS.TriggerLoaded then
                loadTriggerbot()
            else
                SETTINGS.TriggerBot = true
            end
        else
            SETTINGS.TriggerBot = false
        end
    end)
    ui.TxtTriggerDelay = createTextBox(triggerSection, "延迟 (毫秒)", SETTINGS.TriggerDelay, function(val)
        SETTINGS.TriggerDelay = math.max(0, math.floor(val))
    end)

    local npcSection = createSection("NPC 透视")
    ui.BtnShowNPC = createToggle(npcSection, "启用 NPC 透视", SETTINGS.ShowNPC, function(val)
        SETTINGS.ShowNPC = val
        local status = val and "开启" or "关闭"
        StarterGui:SetCore("SendNotification", { Title = "NPC透视", Text = "NPC透视已" .. status, Duration = 2 })
    end)
    -- 自定义队伍标签
    local teamTagFrame = Instance.new("Frame")
    teamTagFrame.Parent = npcSection
    teamTagFrame.BackgroundTransparency = 1
    teamTagFrame.Size = UDim2.new(1, 0, 0, 28)
    local tagLabel = Instance.new("TextLabel")
    tagLabel.Parent = teamTagFrame
    tagLabel.BackgroundTransparency = 1
    tagLabel.Size = UDim2.new(0.6, -10, 1, 0)
    tagLabel.Position = UDim2.new(0, 5, 0, 0)
    tagLabel.Text = "自定义队伍标签"
    tagLabel.TextColor3 = Color3.fromRGB(210, 220, 240)
    tagLabel.TextSize = 13
    tagLabel.Font = Enum.Font.GothamSemibold
    tagLabel.TextXAlignment = Enum.TextXAlignment.Left

    local tagBox = Instance.new("TextBox")
    tagBox.Parent = teamTagFrame
    tagBox.Size = UDim2.new(0, 120, 1, -4)
    tagBox.Position = UDim2.new(1, -125, 0, 2)
    tagBox.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
    tagBox.BorderSizePixel = 0
    tagBox.Text = SETTINGS.CustomTeamTag
    tagBox.TextColor3 = Color3.fromRGB(255,255,255)
    tagBox.TextSize = 12
    tagBox.Font = Enum.Font.GothamSemibold
    local tagCorner = Instance.new("UICorner")
    tagCorner.CornerRadius = UDim.new(0, 4)
    tagCorner.Parent = tagBox
    tagBox.FocusLost:Connect(function(enter)
        if enter then
            SETTINGS.CustomTeamTag = tagBox.Text
            StarterGui:SetCore("SendNotification", { Title = "队伍标签", Text = "自定义标签已设置为: " .. SETTINGS.CustomTeamTag, Duration = 2 })
        end
    end)

    local helpText = Instance.new("TextLabel")
    helpText.Parent = npcSection
    helpText.BackgroundTransparency = 1
    helpText.Size = UDim2.new(1, -10, 0, 20)
    helpText.Position = UDim2.new(0, 5, 0, 0)
    helpText.Text = "标签将用于判断队友，留空则使用自动检测(Team/TeamColor)。"
    helpText.TextColor3 = Color3.fromRGB(150, 160, 180)
    helpText.TextSize = 11
    helpText.Font = Enum.Font.Gotham
    helpText.TextXAlignment = Enum.TextXAlignment.Left

    -- [MOD] 其他设置：手动队友半径 + 清除按钮
    local otherSection = createSection("其他设置")
    -- 半径滑块
    ui.SliderManualRadius = createSlider(otherSection, "手动标记半径", 10, 200, SETTINGS.ManualTeammateRadius, function(val)
        SETTINGS.ManualTeammateRadius = math.floor(val)
    end)

    -- 清除所有手动队友标记按钮
    local clearBtn = Instance.new("TextButton")
    clearBtn.Parent = otherSection
    clearBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 50)
    clearBtn.BorderSizePixel = 0
    clearBtn.Size = UDim2.new(1, -10, 0, 28)
    clearBtn.Position = UDim2.new(0, 5, 0, 0)
    clearBtn.Text = "清除所有手动队友"
    clearBtn.TextColor3 = Color3.fromRGB(255,255,255)
    clearBtn.TextSize = 13
    clearBtn.Font = Enum.Font.GothamSemibold
    local clearCorner = Instance.new("UICorner")
    clearCorner.CornerRadius = UDim.new(0, 4)
    clearCorner.Parent = clearBtn
    clearBtn.MouseButton1Click:Connect(function()
        for player in pairs(manualTeammates) do
            manualTeammates[player] = nil
        end
        StarterGui:SetCore("SendNotification", { Title = "手动队友", Text = "已清除所有手动队友标记", Duration = 2 })
    end)

    -- 销毁按钮放在这里
    local destroyBtn = Instance.new("TextButton")
    destroyBtn.Parent = otherSection
    destroyBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
    destroyBtn.BorderSizePixel = 0
    destroyBtn.Size = UDim2.new(1, -10, 0, 30)
    destroyBtn.Position = UDim2.new(0, 5, 0, 0)
    destroyBtn.Text = "销毁脚本 (Delete)"
    destroyBtn.TextColor3 = Color3.fromRGB(255,255,255)
    destroyBtn.TextSize = 14
    destroyBtn.Font = Enum.Font.GothamSemibold
    local destCorner = Instance.new("UICorner")
    destCorner.CornerRadius = UDim.new(0, 4)
    destCorner.Parent = destroyBtn
    destroyBtn.MouseButton1Click:Connect(destroyScript)

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Parent = content
    statusLabel.BackgroundTransparency = 1
    statusLabel.Size = UDim2.new(1, 0, 0, 20)
    statusLabel.Text = "Insert开关ESP | Delete销毁 | 右Ctrl隐藏UI | F2标记附近 | F3清除队友"
    statusLabel.TextColor3 = Color3.fromRGB(180, 190, 210)
    statusLabel.TextSize = 11
    statusLabel.Font = Enum.Font.GothamSemibold
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    ui.LblStatus = statusLabel

    content.Size = UDim2.new(1, -10, 0, 0)

    -- 窗口拖动
    local dragging = false
    local dragStart, dragOffset
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            dragOffset = mainFrame.Position
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                dragOffset.X.Scale,
                dragOffset.X.Offset + delta.X,
                dragOffset.Y.Scale,
                dragOffset.Y.Offset + delta.Y
            )
        end
    end)

    ui.MainFrame = mainFrame
    print("UI 创建完成")
end

-- ============ 主初始化 ============
task.wait(1)

createUI()

-- 创建FOV圆和瞄准线
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

-- 初始化玩家ESP
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

-- 视口变化时更新文本位置
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    if isDestroyed then return end
    if statusText then
        statusText.Position = Vector2.new(10, Camera.ViewportSize.Y - 30)
    end
    if statsText then
        statsText.Position = Vector2.new(10, Camera.ViewportSize.Y - 70)
    end
end)

-- ============ 快捷键绑定 ============
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or isDestroyed then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        SETTINGS.Enabled = not SETTINGS.Enabled
        if ui.BtnToggleESP then
            ui.BtnToggleESP.Text = SETTINGS.Enabled and "开启" or "关闭"
            ui.BtnToggleESP.BackgroundColor3 = SETTINGS.Enabled and Color3.fromRGB(0, 180, 80) or Color3.fromRGB(80, 80, 90)
        end
        local status = SETTINGS.Enabled and "开启" or "关闭"
        StarterGui:SetCore("SendNotification", { Title = "ESP", Text = "ESP 已" .. status, Duration = 2 })
    elseif input.KeyCode == Enum.KeyCode.Delete then
        destroyScript()
        StarterGui:SetCore("SendNotification", { Title = "销毁", Text = "脚本已彻底销毁", Duration = 2 })
    elseif input.KeyCode == Enum.KeyCode.RightControl then
        if ui.MainFrame then
            ui.MainFrame.Visible = not ui.MainFrame.Visible
            local status = ui.MainFrame.Visible and "显示" or "隐藏"
            StarterGui:SetCore("SendNotification", { Title = "UI", Text = "界面已" .. status, Duration = 2 })
        end
    -- [MOD] F2: 标记附近所有玩家为队友
    elseif input.KeyCode == Enum.KeyCode.F2 then
        local localChar = LocalPlayer.Character
        if not localChar then
            StarterGui:SetCore("SendNotification", { Title = "手动队友", Text = "你尚未生成角色", Duration = 2 })
            return
        end
        local localRoot = localChar:FindFirstChild("HumanoidRootPart")
        if not localRoot then
            StarterGui:SetCore("SendNotification", { Title = "手动队友", Text = "无法获取位置", Duration = 2 })
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
        StarterGui:SetCore("SendNotification", {
            Title = "手动队友",
            Text = string.format("已将 %d 名附近玩家标记为队友 (半径 %.0f)", count, radius),
            Duration = 3
        })
    -- [MOD] F3: 清除所有手动队友
    elseif input.KeyCode == Enum.KeyCode.F3 then
        for player in pairs(manualTeammates) do
            manualTeammates[player] = nil
        end
        StarterGui:SetCore("SendNotification", { Title = "手动队友", Text = "已清除所有手动队友标记", Duration = 2 })
    end
end)

-- ============ 自瞄右键控制 ============
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if isDestroyed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        if SETTINGS.AimbotEnabled then
            aimbotActive = true
            if not aimbotConnection then
                aimbotConnection = RunService.RenderStepped:Connect(updateAimbot)
            end
            StarterGui:SetCore("SendNotification", { Title = "自瞄", Text = "自瞄已激活（右键按住）", Duration = 1 })
        else
            StarterGui:SetCore("SendNotification", { Title = "自瞄", Text = "自瞄已禁用，请在 UI 中开启", Duration = 1 })
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
            StarterGui:SetCore("SendNotification", { Title = "自瞄", Text = "自瞄已释放", Duration = 1 })
        end
    end
end)

print("FPS 辅助 v19.2 增强版 加载完成")
print("   Insert     - 开关ESP")
print("   Delete     - 彻底销毁")
print("   右Ctrl     - 隐藏/显示UI")
print("   F2         - 标记附近所有玩家为队友 (新增)")
print("   F3         - 清除所有手动队友 (新增)")
print("   鼠标右键   - 自瞄（需在 UI 中开启）")
print("   其他功能请通过 UI 面板操作")