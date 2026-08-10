--[[
    Doors 辅助脚本 v1.0 (Quantum UI 版)
    功能：ESP、Entity 拦截、交互、移动、快捷键、杂项
    PlaceIds:
        6839808510 - Doors (Hotel)
        7894711641 - Doors (Floor 2)
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
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"))()
end)

if not success then
    warn("[Doors] 加载 Quantum UI 库失败:", QuantumUI)
    warn("[Doors] 尝试使用本地源码...")
    local localSuccess, localQuantumUI = pcall(function()
        local localPath = "SciFi-UI-Library/source.lua"
        if isfile and isfile(localPath) then
            return loadstring(readfile(localPath))()
        end
        return nil
    end)
    if not localSuccess or not localQuantumUI then
        warn("[Doors] 无法加载 UI 库，脚本终止")
        return
    end
    QuantumUI = localQuantumUI
end

print("[Doors] Quantum UI v" .. QuantumUI.Version .. " 加载成功")

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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")

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

local THEME_PRESETS = {
    DoorsPink = Color3.fromRGB(255, 150, 200),
    Cyan = Color3.fromRGB(0, 200, 255),
    Purple = Color3.fromRGB(180, 60, 255),
    Green = Color3.fromRGB(0, 255, 120),
    Red = Color3.fromRGB(255, 70, 90),
    Gold = Color3.fromRGB(255, 200, 50),
    Pink = Color3.fromRGB(255, 105, 180),
}

local SETTINGS = {
    DoorsESP = false,
    CabinetESP = false,
    ChestESP = false,
    EntityESP = false,
    OtherESP = false,
    DoorsESPColor = Color3.fromRGB(255, 150, 200),
    CabinetESPColor = Color3.fromRGB(19, 211, 13),
    ChestESPColor = Color3.fromRGB(131, 96, 168),
    ESPRefreshRate = 0.15,

    DisableScreech = false,
    DisableTimothy = false,
    DisableA90 = false,
    DisableSeek = false,
    DisableGlitch = false,
    DisableSnare = false,
    RemoveDeathHint = false,
    ClosetExitFix = false,
    NoBreaker = false,
    DisableEyes = false,

    InstantInteract = false,
    EnableInteractions = false,
    InteractNoclip = false,
    IncreasedDistance = false,
    DoorRange = 20,
    NoDark = false,
    WasteItems = false,

    SpeedBoost = 50,
    JumpPower = 100,
    InfJump = false,
    Noclip = false,
    Fly = false,
    FlySpeed = 80,
    NoclipNext = false,

    UIKeybind = Enum.KeyCode.RightShift,
    NoclipKeybind = Enum.KeyCode.V,
    FlyKeybind = Enum.KeyCode.F,
    ScreechSafeRoomKeybind = Enum.KeyCode.C,

    AntiAFK = false,
    RainbowBorder = false,
    RainbowSpeed = 1,
}

-- ══════════════════════════════════════════════════════════════════
-- 4. 全局变量
-- ══════════════════════════════════════════════════════════════════
local espHighlights = {}
local heartbeatConnection = nil
local noclipConnection = nil
local flyConnection = nil
local infJumpConnection = nil
local antiAFKConnection = nil
local speedConnection = nil
local isDestroyed = false
local Window = nil
local flyVelocity = Vector3.new(0, 0, 0)
local lastESPUpdate = 0

local ESP_Items = {
    ["Key"] = true,
    ["Book"] = true,
    ["Lighter"] = true,
    ["Lockpicks"] = true,
    ["Vitamins"] = true,
    ["Crucifix"] = true,
    ["SkeletonKey"] = true,
    ["Flashlight"] = true,
    ["Candle"] = true,
    ["Fuse"] = true,
    ["Shears"] = true,
    ["Battery"] = true,
    ["Paper"] = true,
    ["ElectricalKey"] = true,
    ["Shakelight"] = true,
    ["iPad"] = true,
}

local ESP_Entities = {
    ["Rush"] = true,
    ["Ambush"] = true,
    ["Figure"] = true,
    ["Seek"] = true,
    ["Screech"] = true,
    ["Eyes"] = true,
    ["Snare"] = true,
    ["A60"] = true,
    ["A120"] = true,
}

local ESP_Others = {
    ["Door"] = true,
    ["Lever"] = true,
    ["Gold"] = true,
}

-- ══════════════════════════════════════════════════════════════════
-- 5. 工具函数
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
                Title = title,
                Text = content,
                Duration = duration or 3
            })
        end)
    end
end

local function getChar()
    return LocalPlayer.Character
end

local function getRoot()
    local char = getChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = getChar()
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- ══════════════════════════════════════════════════════════════════
-- 6. ESP 核心
-- ══════════════════════════════════════════════════════════════════
local function clearESP()
    for _, hl in pairs(espHighlights) do
        pcall(function() hl:Destroy() end)
    end
    espHighlights = {}
end

local function createHighlight(part, color, name)
    if not part or not part:IsA("Instance") then return nil end
    local existing = espHighlights[part]
    if existing then
        existing.FillColor = color
        existing.OutlineColor = color
        existing.Enabled = true
        return existing
    end
    local hl = Instance.new("Highlight")
    hl.Name = "DoorsESP_" .. name
    hl.Adornee = part:IsA("Model") and part or (part.Parent and part.Parent:IsA("Model") and part.Parent or part)
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0.2
    hl.Enabled = true
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = CoreGui
    espHighlights[part] = hl
    return hl
end

local function isCabinet(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("cabinet") or name:find("wardrobe") or name:find("locker") or name:find("closet")
end

local function isChest(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("chest") or name:find("drawer") or name:find("box")
end

local function isDoor(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("door") or inst:FindFirstChild("Door") or inst:FindFirstChild("Handle")
end

local function isLever(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("lever") or name:find("switch") or name:find("valve")
end

local function isGold(inst)
    if not inst then return false end
    local name = inst.Name:lower()
    return name:find("gold") or (inst:IsA("BasePart") and inst.Color and (inst.Color.R > 0.9 and inst.Color.G > 0.7 and inst.Color.B < 0.3))
end

local function updateESP()
    if isDestroyed then return end
    local now = tick()
    if now - lastESPUpdate < SETTINGS.ESPRefreshRate then return end
    lastESPUpdate = now

    local success, err = pcall(function()
        local enabledAny = SETTINGS.DoorsESP or SETTINGS.CabinetESP or SETTINGS.ChestESP or SETTINGS.EntityESP or SETTINGS.OtherESP
        if not enabledAny then
            for part, hl in pairs(espHighlights) do
                if hl then hl.Enabled = false end
            end
            return
        end

        for _, v in pairs(Workspace:GetDescendants()) do
            if isDestroyed then return end

            if SETTINGS.DoorsESP and ESP_Items[v.Name] then
                if v:IsA("BasePart") or v:IsA("Model") then
                    createHighlight(v, SETTINGS.DoorsESPColor, v.Name)
                end
            end

            if SETTINGS.CabinetESP and isCabinet(v) then
                if v:IsA("Model") or v:IsA("BasePart") then
                    createHighlight(v, SETTINGS.CabinetESPColor, "Cabinet")
                end
            end

            if SETTINGS.ChestESP and isChest(v) then
                if v:IsA("Model") or v:IsA("BasePart") then
                    createHighlight(v, SETTINGS.ChestESPColor, "Chest")
                end
            end

            if SETTINGS.EntityESP then
                local function checkEntityName(name)
                    for ename in pairs(ESP_Entities) do
                        if name:lower():find(ename:lower()) then return true end
                    end
                    return false
                end
                if checkEntityName(v.Name) then
                    if v:IsA("Model") or v:IsA("BasePart") then
                        createHighlight(v, Color3.fromRGB(255, 0, 0), v.Name)
                    end
                end
            end

            if SETTINGS.OtherESP then
                if isDoor(v) and (v:IsA("Model") or v:IsA("BasePart")) then
                    createHighlight(v, Color3.fromRGB(255, 255, 0), "Door")
                end
                if isLever(v) and (v:IsA("Model") or v:IsA("BasePart")) then
                    createHighlight(v, Color3.fromRGB(255, 165, 0), "Lever")
                end
                if isGold(v) and v:IsA("BasePart") then
                    createHighlight(v, Color3.fromRGB(255, 215, 0), "Gold")
                end
            end
        end

        for part, hl in pairs(espHighlights) do
            if not part or not part.Parent then
                pcall(function() hl:Destroy() end)
                espHighlights[part] = nil
            end
        end
    end)
    if not success then warn("ESP Update error:", err) end
end

-- ══════════════════════════════════════════════════════════════════
-- 7. Entity 拦截
-- ══════════════════════════════════════════════════════════════════
local function setupEntityInterceptors()
    pcall(function()
        local Replicator = ReplicatedStorage:FindFirstChild("EntityInfo")
        if Replicator and Replicator:IsA("RemoteEvent") then
            local oldFireServer
            oldFireServer = hookfunction(getmetatable(Replicator).__index.FireServer, function(self, ...)
                if isDestroyed then return oldFireServer(self, ...) end
                local args = {...}
                local useModule = args[1] == "UseEnemyModule"
                if useModule then
                    local moduleName = tostring(args[2] or "")
                    local blocked = false
                    if SETTINGS.DisableScreech and moduleName:lower():find("screech") then blocked = true end
                    if SETTINGS.DisableTimothy and moduleName:lower():find("timothy") then blocked = true end
                    if SETTINGS.DisableA90 and moduleName:lower():find("a90") then blocked = true end
                    if SETTINGS.DisableSeek and moduleName:lower():find("seek") then blocked = true end
                    if SETTINGS.DisableGlitch and moduleName:lower():find("glitch") then blocked = true end
                    if SETTINGS.DisableSnare and moduleName:lower():find("snare") then blocked = true end
                    if SETTINGS.DisableEyes and moduleName:lower():find("eyes") then blocked = true end
                    if blocked then
                        return nil
                    end
                end
                return oldFireServer(self, ...)
            end)
        end
    end)

    pcall(function()
        local Events = ReplicatedStorage:FindFirstChild("Events")
        if Events then
            for _, ev in pairs(Events:GetDescendants()) do
                if ev:IsA("RemoteEvent") then
                    local oldFireClient
                    oldFireClient = hookfunction(getmetatable(ev).__index.FireClient, function(self, player, ...)
                        if isDestroyed then return oldFireClient(self, player, ...) end
                        if player ~= LocalPlayer then return oldFireClient(self, player, ...) end
                        local evName = ev.Name:lower()
                        if SETTINGS.DisableGlitch and evName:find("glitch") then return nil end
                        if SETTINGS.RemoveDeathHint and evName:find("death") then return nil end
                        return oldFireClient(self, player, ...)
                    end)
                end
            end
        end
    end)

    pcall(function()
        if SETTINGS.NoBreaker then
            local breakerGUI = Workspace:FindFirstChild("BreakerMinigame", true)
            if breakerGUI then
                for _, b in pairs(breakerGUI:GetDescendants()) do
                    if b:IsA("BoolValue") and b.Name == "IsActive" then
                        b.Value = false
                    end
                end
            end
        end
    end)

    pcall(function()
        if SETTINGS.ClosetExitFix then
            LocalPlayer.CharacterAdded:Connect(function()
                task.wait(1)
                local hum = getHumanoid()
                if hum then
                    hum.Sit = false
                end
            end)
        end
    end)

    pcall(function()
        if SETTINGS.DisableEyes then
            local eyesConn; eyesConn = Workspace.DescendantAdded:Connect(function(desc)
                if isDestroyed then eyesConn:Disconnect(); return end
                if desc.Name:lower():find("eyes") then
                    task.wait(0.1)
                    pcall(function() desc:Destroy() end)
                end
            end)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 8. 移动 & 交互逻辑
-- ══════════════════════════════════════════════════════════════════
local function updateSpeed()
    if isDestroyed then return end
    local hum = getHumanoid()
    if hum then
        hum.WalkSpeed = 17 + SETTINGS.SpeedBoost
        hum.JumpPower = SETTINGS.JumpPower
    end
end

local function setupNoclip()
    if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
    noclipConnection = RunService.Stepped:Connect(function()
        if isDestroyed then return end
        if not (SETTINGS.Noclip or (SETTINGS.InteractNoclip and SETTINGS.InstantInteract)) then return end
        local char = getChar()
        if not char then return end
        for _, v in pairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
            end
        end
    end)
end

local function setupInfJump()
    if infJumpConnection then infJumpConnection:Disconnect(); infJumpConnection = nil end
    infJumpConnection = UserInputService.InputBegan:Connect(function(input, gp)
        if gp or isDestroyed then return end
        if not SETTINGS.InfJump then return end
        if input.KeyCode == Enum.KeyCode.Space then
            local hum = getHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)
end

local function setupFly()
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    local cam = Camera
    flyConnection = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        if not SETTINGS.Fly then return end
        local root = getRoot()
        local hum = getHumanoid()
        if not root or not hum then return end

        local keys = {
            W = UserInputService:IsKeyDown(Enum.KeyCode.W),
            S = UserInputService:IsKeyDown(Enum.KeyCode.S),
            A = UserInputService:IsKeyDown(Enum.KeyCode.A),
            D = UserInputService:IsKeyDown(Enum.KeyCode.D),
            Space = UserInputService:IsKeyDown(Enum.KeyCode.Space),
            Shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift),
        }

        local speed = SETTINGS.FlySpeed
        if keys.Shift then speed = speed * 2 end

        local cf = cam.CFrame
        local direction = Vector3.new()
        if keys.W then direction = direction + cf.LookVector end
        if keys.S then direction = direction - cf.LookVector end
        if keys.A then direction = direction - cf.RightVector end
        if keys.D then direction = direction + cf.RightVector end
        if keys.Space then direction = direction + Vector3.new(0, 1, 0) end
        if direction.Magnitude > 0 then
            direction = direction.Unit * speed * 0.016
        end

        root.Velocity = direction * 60
        hum.PlatformStand = true
        hum.GravityScale = 0
    end)
end

local function stopFly()
    local hum = getHumanoid()
    if hum then
        hum.PlatformStand = false
        hum.GravityScale = 1
    end
end

local function setupSpeedConnection()
    if speedConnection then speedConnection:Disconnect(); speedConnection = nil end
    speedConnection = RunService.Heartbeat:Connect(updateSpeed)
end

local function setupAntiAFK()
    if antiAFKConnection then antiAFKConnection:Disconnect(); antiAFKConnection = nil end
    antiAFKConnection = RunService.Heartbeat:Connect(function()
        if isDestroyed then return end
        if SETTINGS.AntiAFK then
            pcall(function()
                LocalPlayer.Idled:Disconnect()
            end)
            local old = tick()
            if tick() - old > 60 then
                old = tick()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, nil)
                task.wait(0.1)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, nil)
            end
        end
    end)
end

local function setupNoDark()
    if not SETTINGS.NoDark then return end
    pcall(function()
        local lighting = game:GetService("Lighting")
        lighting.Brightness = 2
        lighting.Ambient = Color3.fromRGB(200, 200, 200)
        lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
        lighting.FogEnd = 10000
        for _, eff in pairs(lighting:GetChildren()) do
            if eff:IsA("ColorCorrectionEffect") or eff:IsA("BlurEffect") or eff:IsA("BloomEffect") then
                eff.Enabled = false
            end
        end
        if LocalPlayer.PlayerGui then
            for _, pg in pairs(LocalPlayer.PlayerGui:GetDescendants()) do
                if pg:IsA("Frame") or pg:IsA("ImageLabel") then
                    if pg.BackgroundTransparency < 0.9 and pg.Size == UDim2.new(1, 0, 1, 0) then
                        pg.BackgroundTransparency = 1
                    end
                end
            end
        end
    end)
end

local function setupInstantInteract()
    if not SETTINGS.InstantInteract then return end
    pcall(function()
        local maxDist = SETTINGS.IncreasedDistance and SETTINGS.DoorRange or 10
        local PlayerGui = LocalPlayer.PlayerGui
        if PlayerGui then
            local interactUI = PlayerGui:FindFirstChild("InteractGUI", true)
            if interactUI then
                for _, btn in pairs(interactUI:GetDescendants()) do
                    if btn:IsA("TextButton") or btn:IsA("ImageButton") then
                        btn.MouseButton1Click:Connect(function()
                            pcall(function()
                                for _, v in pairs(Workspace:GetDescendants()) do
                                    if v:IsA("ProximityPrompt") then
                                        local dist = (LocalPlayer.Character and LocalPlayer.Character.PrimaryPart and (v.Parent.Position - LocalPlayer.Character.PrimaryPart.Position).Magnitude or 999)
                                        if dist < maxDist then
                                            firesignal(v.Triggered, LocalPlayer)
                                        end
                                    end
                                end
                            end)
                        end)
                    end
                end
            end
        end
        local ppc; ppc = Workspace.DescendantAdded:Connect(function(desc)
            if isDestroyed then ppc:Disconnect(); return end
            if desc:IsA("ProximityPrompt") then
                if SETTINGS.IncreasedDistance then
                    pcall(function() desc.MaxActivationDistance = SETTINGS.DoorRange end)
                    pcall(function() desc.HoldDuration = 0 end)
                end
            end
        end)
        for _, pp in pairs(Workspace:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                if SETTINGS.IncreasedDistance then
                    pcall(function() pp.MaxActivationDistance = SETTINGS.DoorRange end)
                    pcall(function() pp.HoldDuration = 0 end)
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
-- 9. Misc 辅助
-- ══════════════════════════════════════════════════════════════════
local function rejoin()
    notify("Rejoin", "正在重新加入...", 3, "Info")
    local ts = game:GetService("TeleportService")
    local pid = game.PlaceId
    ts:Teleport(pid, LocalPlayer)
end

local function destroyScript()
    if isDestroyed then return end
    isDestroyed = true
    if heartbeatConnection then heartbeatConnection:Disconnect(); heartbeatConnection = nil end
    if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    if infJumpConnection then infJumpConnection:Disconnect(); infJumpConnection = nil end
    if antiAFKConnection then antiAFKConnection:Disconnect(); antiAFKConnection = nil end
    if speedConnection then speedConnection:Disconnect(); speedConnection = nil end
    stopFly()
    clearESP()
    if Window then pcall(function() Window:Destroy() end) end
    if _G.QuantumUI_Window then _G.QuantumUI_Window = nil end
    notify("销毁", "脚本已彻底销毁", 2, "Warning")
    print("[Doors] 脚本已彻底销毁")
end

-- ══════════════════════════════════════════════════════════════════
-- 10. 构建 Quantum UI 界面
-- ══════════════════════════════════════════════════════════════════
Window = QuantumUI.new({
    Title = "Doors 辅助",
    Subtitle = "恐怖门",
    ThemeColor = Color3.fromRGB(255, 150, 200),
    Transparency = 0.3,
    Size = UDim2.new(0, 640, 0, 520),
    Keybind = Enum.KeyCode.RightShift,
})

_G.QuantumUI_Window = Window

task.wait(3.5)

-- ========== TAB 1: ESP ==========
local ESPTab = Window:AddTab({
    Name = "ESP",
    Icon = "rbxassetid://6034509993"
})

ESPTab:AddSection({ Name = "👁️ ESP 分类" })

ESPTab:AddToggle({
    Name = "物品 ESP (Key/Book/...)",
    Default = SETTINGS.DoorsESP,
    Flag = "ESP_DoorsItems",
    Callback = function(val)
        SETTINGS.DoorsESP = val
        notify("物品 ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "柜子 ESP (Cabinet)",
    Default = SETTINGS.CabinetESP,
    Flag = "ESP_Cabinet",
    Callback = function(val)
        SETTINGS.CabinetESP = val
        notify("柜子 ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "宝箱 ESP (Chest)",
    Default = SETTINGS.ChestESP,
    Flag = "ESP_Chest",
    Callback = function(val)
        SETTINGS.ChestESP = val
        notify("宝箱 ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "实体 ESP (Entity)",
    Default = SETTINGS.EntityESP,
    Flag = "ESP_Entity",
    Callback = function(val)
        SETTINGS.EntityESP = val
        notify("实体 ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddToggle({
    Name = "其他 ESP (Door/Lever/Gold)",
    Default = SETTINGS.OtherESP,
    Flag = "ESP_Other",
    Callback = function(val)
        SETTINGS.OtherESP = val
        notify("其他 ESP", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

ESPTab:AddSection({ Name = "🎨 ESP 颜色" })

ESPTab:AddColorPicker({
    Name = "物品颜色",
    Default = SETTINGS.DoorsESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_DoorsColor",
    Callback = function(c) SETTINGS.DoorsESPColor = c end
})

ESPTab:AddColorPicker({
    Name = "柜子颜色",
    Default = SETTINGS.CabinetESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_CabinetColor",
    Callback = function(c) SETTINGS.CabinetESPColor = c end
})

ESPTab:AddColorPicker({
    Name = "宝箱颜色",
    Default = SETTINGS.ChestESPColor,
    Presets = PRESET_COLORS,
    Flag = "ESP_ChestColor",
    Callback = function(c) SETTINGS.ChestESPColor = c end
})

ESPTab:AddSection({ Name = "⚙️ ESP 参数" })

ESPTab:AddSlider({
    Name = "ESP 刷新速率",
    Min = 0.05, Max = 1, Default = SETTINGS.ESPRefreshRate, Increment = 0.05,
    Suffix = " s",
    Flag = "Doors_ESPRefresh",
    Callback = function(val) SETTINGS.ESPRefreshRate = val end
})

ESPTab:AddSection({ Name = "📋 物品列表" })
ESPTab:AddParagraph({
    Title = "追踪物品",
    Content = table.concat({
        "Key | Book | Lighter | Lockpicks",
        "Vitamins | Crucifix | SkeletonKey | Flashlight",
        "Candle | Fuse | Shears | Battery",
        "Paper | ElectricalKey | Shakelight | iPad",
    }, "\n")
})

ESPTab:AddParagraph({
    Title = "追踪实体",
    Content = table.concat({
        "Rush | Ambush | Figure | Seek",
        "Screech | Eyes | Snare | A60 | A120",
    }, "\n")
})

-- ========== TAB 2: Entity ==========
local EntityTab = Window:AddTab({
    Name = "Entity",
    Icon = "rbxassetid://6034287594"
})

EntityTab:AddSection({ Name = "🚫 Entity 拦截" })

EntityTab:AddToggle({
    Name = "禁用 Screech (尖叫)",
    Default = SETTINGS.DisableScreech,
    Flag = "Ent_DisableScreech",
    Callback = function(val)
        SETTINGS.DisableScreech = val
        notify("Screech", val and "已禁用" or "已启用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "禁用 Timothy (蜘蛛)",
    Default = SETTINGS.DisableTimothy,
    Flag = "Ent_DisableTimothy",
    Callback = function(val)
        SETTINGS.DisableTimothy = val
        notify("Timothy", val and "已禁用" or "已启用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "禁用 A90",
    Default = SETTINGS.DisableA90,
    Flag = "Ent_DisableA90",
    Callback = function(val)
        SETTINGS.DisableA90 = val
        notify("A90", val and "已禁用" or "已启用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "禁用 Seek (追逐)",
    Default = SETTINGS.DisableSeek,
    Flag = "Ent_DisableSeek",
    Callback = function(val)
        SETTINGS.DisableSeek = val
        notify("Seek", val and "已禁用" or "已启用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "禁用 Glitch (故障)",
    Default = SETTINGS.DisableGlitch,
    Flag = "Ent_DisableGlitch",
    Callback = function(val)
        SETTINGS.DisableGlitch = val
        notify("Glitch", val and "已禁用" or "已启用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "禁用 Snare (陷阱)",
    Default = SETTINGS.DisableSnare,
    Flag = "Ent_DisableSnare",
    Callback = function(val)
        SETTINGS.DisableSnare = val
        notify("Snare", val and "已禁用" or "已启用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "禁用 Eyes (眼睛)",
    Default = SETTINGS.DisableEyes,
    Flag = "Ent_DisableEyes",
    Callback = function(val)
        SETTINGS.DisableEyes = val
        notify("Eyes", val and "已禁用" or "已启用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddSection({ Name = "🛠️ 其他修复" })

EntityTab:AddToggle({
    Name = "移除死亡提示",
    Default = SETTINGS.RemoveDeathHint,
    Flag = "Ent_RemoveDeathHint",
    Callback = function(val)
        SETTINGS.RemoveDeathHint = val
        notify("死亡提示", val and "已移除" or "已恢复", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "衣柜退出修复",
    Default = SETTINGS.ClosetExitFix,
    Flag = "Ent_ClosetExitFix",
    Callback = function(val)
        SETTINGS.ClosetExitFix = val
        notify("衣柜修复", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

EntityTab:AddToggle({
    Name = "跳过断路器",
    Default = SETTINGS.NoBreaker,
    Flag = "Ent_NoBreaker",
    Callback = function(val)
        SETTINGS.NoBreaker = val
        notify("断路器", val and "已跳过" or "已恢复", 2, val and "Success" or "Warning")
    end
})

-- ========== TAB 3: Interaction ==========
local InteractTab = Window:AddTab({
    Name = "Interaction",
    Icon = "rbxassetid://6034281467"
})

InteractTab:AddSection({ Name = "🤝 交互设置" })

InteractTab:AddToggle({
    Name = "即时交互",
    Default = SETTINGS.InstantInteract,
    Flag = "Int_Instant",
    Callback = function(val)
        SETTINGS.InstantInteract = val
        notify("即时交互", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if val then setupInstantInteract() end
    end
})

InteractTab:AddToggle({
    Name = "启用所有交互",
    Default = SETTINGS.EnableInteractions,
    Flag = "Int_EnableAll",
    Callback = function(val)
        SETTINGS.EnableInteractions = val
        notify("全部交互", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

InteractTab:AddToggle({
    Name = "交互穿墙",
    Default = SETTINGS.InteractNoclip,
    Flag = "Int_Noclip",
    Callback = function(val)
        SETTINGS.InteractNoclip = val
        notify("交互穿墙", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

InteractTab:AddToggle({
    Name = "增加交互距离",
    Default = SETTINGS.IncreasedDistance,
    Flag = "Int_IncreasedDist",
    Callback = function(val)
        SETTINGS.IncreasedDistance = val
        notify("交互距离", val and "已增加" or "已恢复", 2, val and "Success" or "Warning")
        if val then setupInstantInteract() end
    end
})

InteractTab:AddSlider({
    Name = "门交互范围",
    Min = 8, Max = 40, Default = SETTINGS.DoorRange, Increment = 1,
    Suffix = " studs",
    Flag = "Doors_DoorRange",
    Callback = function(val)
        SETTINGS.DoorRange = math.floor(val)
    end
})

InteractTab:AddSection({ Name = "💡 环境设置" })

InteractTab:AddToggle({
    Name = "反黑暗 (NoDark)",
    Default = SETTINGS.NoDark,
    Flag = "Int_NoDark",
    Callback = function(val)
        SETTINGS.NoDark = val
        notify("反黑暗", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if val then setupNoDark() end
    end
})

InteractTab:AddToggle({
    Name = "浪费物品 (WasteItems)",
    Default = SETTINGS.WasteItems,
    Flag = "Int_WasteItems",
    Callback = function(val)
        SETTINGS.WasteItems = val
        notify("浪费物品", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

-- ========== TAB 4: Movement ==========
local MovementTab = Window:AddTab({
    Name = "Movement",
    Icon = "rbxassetid://6031280882"
})

MovementTab:AddSection({ Name = "🏃 基础移动" })

MovementTab:AddSlider({
    Name = "速度加成 (总速度=17+值)",
    Min = 0, Max = 200, Default = SETTINGS.SpeedBoost, Increment = 1,
    Suffix = "",
    Flag = "Doors_SpeedBoost",
    Callback = function(val)
        SETTINGS.SpeedBoost = val
        updateSpeed()
    end
})

MovementTab:AddSlider({
    Name = "跳跃力",
    Min = 50, Max = 200, Default = SETTINGS.JumpPower, Increment = 1,
    Flag = "Move_JumpPower",
    Callback = function(val)
        SETTINGS.JumpPower = val
        updateSpeed()
    end
})

MovementTab:AddToggle({
    Name = "无限跳跃",
    Default = SETTINGS.InfJump,
    Flag = "Move_InfJump",
    Callback = function(val)
        SETTINGS.InfJump = val
        notify("无限跳跃", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if val then setupInfJump() end
    end
})

MovementTab:AddSection({ Name = "🪁 穿墙/飞行" })

MovementTab:AddToggle({
    Name = "穿墙 (Noclip)",
    Default = SETTINGS.Noclip,
    Flag = "Move_Noclip",
    Callback = function(val)
        SETTINGS.Noclip = val
        notify("穿墙", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

MovementTab:AddToggle({
    Name = "飞行 (Fly)",
    Default = SETTINGS.Fly,
    Flag = "Move_Fly",
    Callback = function(val)
        SETTINGS.Fly = val
        notify("飞行", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
        if not val then stopFly() end
    end
})

MovementTab:AddSlider({
    Name = "飞行速度",
    Min = 10, Max = 200, Default = SETTINGS.FlySpeed, Increment = 5,
    Suffix = "",
    Flag = "Move_FlySpeed",
    Callback = function(val) SETTINGS.FlySpeed = val end
})

MovementTab:AddToggle({
    Name = "下一房间自动穿墙",
    Default = SETTINGS.NoclipNext,
    Flag = "Move_NoclipNext",
    Callback = function(val)
        SETTINGS.NoclipNext = val
        notify("下房穿墙", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

-- ========== TAB 5: Keybinds ==========
local KeybindsTab = Window:AddTab({
    Name = "Keybinds",
    Icon = "rbxassetid://6034996037"
})

KeybindsTab:AddSection({ Name = "⌨️ 快捷键绑定" })

KeybindsTab:AddKeybind({
    Name = "UI 切换",
    Default = SETTINGS.UIKeybind,
    Flag = "KB_UI",
    ChangedCallback = function(key)
        SETTINGS.UIKeybind = key
    end
})

KeybindsTab:AddKeybind({
    Name = "穿墙 (Noclip)",
    Default = SETTINGS.NoclipKeybind,
    Flag = "KB_Noclip",
    ChangedCallback = function(key)
        SETTINGS.NoclipKeybind = key
    end
})

KeybindsTab:AddKeybind({
    Name = "飞行 (Fly)",
    Default = SETTINGS.FlyKeybind,
    Flag = "KB_Fly",
    ChangedCallback = function(key)
        SETTINGS.FlyKeybind = key
    end
})

KeybindsTab:AddKeybind({
    Name = "Screech 安全屋",
    Default = SETTINGS.ScreechSafeRoomKeybind,
    Flag = "KB_ScreechSafe",
    ChangedCallback = function(key)
        SETTINGS.ScreechSafeRoomKeybind = key
    end
})

KeybindsTab:AddSection({ Name = "💡 使用说明" })
KeybindsTab:AddParagraph({
    Title = "按键说明",
    Content = table.concat({
        "UI切换键 - 显示/隐藏 UI 面板",
        "穿墙键 - 开关 Noclip 模式",
        "飞行键 - 开关 Fly 模式",
        "Screech键 - 进入最近柜子/安全点",
        "WASD - 飞行方向控制",
        "Shift (飞行中) - 加速飞行",
    }, "\n")
})

-- ========== TAB 6: Misc ==========
local MiscTab = Window:AddTab({
    Name = "Misc",
    Icon = "rbxassetid://6023243660"
})

MiscTab:AddSection({ Name = "🔧 常规设置" })

MiscTab:AddToggle({
    Name = "反挂机 (AntiAFK)",
    Default = SETTINGS.AntiAFK,
    Flag = "Misc_AntiAFK",
    Callback = function(val)
        SETTINGS.AntiAFK = val
        notify("反挂机", val and "已启用" or "已禁用", 2, val and "Success" or "Warning")
    end
})

MiscTab:AddSection({ Name = "🔘 按钮" })

MiscTab:AddButton({
    Name = "🔄 重新加入 (Rejoin)",
    Callback = function()
        rejoin()
    end
})

MiscTab:AddButton({
    Name = "💀 销毁脚本 (Destroy)",
    Callback = function()
        destroyScript()
    end
})

MiscTab:AddSection({ Name = "🌈 彩虹边框" })

MiscTab:AddToggle({
    Name = "彩虹边框动画",
    Default = SETTINGS.RainbowBorder,
    Flag = "Misc_Rainbow",
    Callback = function(state)
        SETTINGS.RainbowBorder = state
        QuantumUI.RainbowEnabled = state
    end
})

MiscTab:AddSlider({
    Name = "彩虹速度",
    Min = 0.1, Max = 5, Default = SETTINGS.RainbowSpeed, Increment = 0.1,
    Suffix = "x",
    Flag = "Misc_RainbowSpeed",
    Callback = function(value)
        SETTINGS.RainbowSpeed = value
        QuantumUI.RainbowSpeed = value
    end
})

MiscTab:AddSection({ Name = "🎨 主题预设" })

MiscTab:AddDropdown({
    Name = "预设主题色",
    Items = {"DoorsPink", "Cyan", "Purple", "Green", "Red", "Gold", "Pink"},
    Default = "DoorsPink",
    Flag = "Misc_Theme",
    Callback = function(selected)
        local color = THEME_PRESETS[selected]
        if color then
            Window.ThemeColor = color
            QuantumUI.ThemeColor = color
            Window:RefreshTheme()
            notify("主题", "已切换: " .. selected, 2, "Success")
        end
    end
})

MiscTab:AddSection({ Name = "📖 About" })

MiscTab:AddParagraph({
    Title = "Doors 辅助 Features",
    Content = table.concat({
        "✨ ESP 系统:",
        "  - 物品透视 (Key/Book/Lighter...)",
        "  - 柜子透视 (Cabinet/Closet)",
        "  - 宝箱透视 (Chest/Drawer)",
        "  - 实体透视 (Rush/Ambush/Figure...)",
        "  - 门/拉杆/黄金透视",
        "",
        "🚫 Entity 拦截:",
        "  - 禁用 Screech/Timothy/A90",
        "  - 禁用 Seek/Glitch/Snare/Eyes",
        "  - 衣柜修复 + 断路器跳过",
        "",
        "🤝 交互增强:",
        "  - 即时交互 + 超远距离",
        "  - 反黑暗 (NoDark)",
        "",
        "🏃 移动作弊:",
        "  - 速度/跳跃加成",
        "  - 无限跳 + 穿墙 + 飞行",
        "",
        "PlaceId: 6839808510 / 7894711641",
    }, "\n")
})

-- ══════════════════════════════════════════════════════════════════
-- 11. 主初始化
-- ══════════════════════════════════════════════════════════════════
task.wait(0.5)

QuantumUI.RainbowEnabled = SETTINGS.RainbowBorder
QuantumUI.RainbowSpeed = SETTINGS.RainbowSpeed

heartbeatConnection = RunService.Heartbeat:Connect(updateESP)
setupNoclip()
setupInfJump()
setupFly()
setupSpeedConnection()
setupAntiAFK()
setupEntityInterceptors()

-- ══════════════════════════════════════════════════════════════════
-- 12. 快捷键处理
-- ══════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or isDestroyed then return end
    local key = input.KeyCode

    if key == SETTINGS.NoclipKeybind then
        SETTINGS.Noclip = not SETTINGS.Noclip
        if Window and Window.Flags and Window.Flags["Move_Noclip"] then
            pcall(function() Window.Flags["Move_Noclip"]:Set(SETTINGS.Noclip) end)
        end
        notify("穿墙", SETTINGS.Noclip and "已启用" or "已禁用", 2, SETTINGS.Noclip and "Success" or "Warning")
    elseif key == SETTINGS.FlyKeybind then
        SETTINGS.Fly = not SETTINGS.Fly
        if Window and Window.Flags and Window.Flags["Move_Fly"] then
            pcall(function() Window.Flags["Move_Fly"]:Set(SETTINGS.Fly) end)
        end
        notify("飞行", SETTINGS.Fly and "已启用" or "已禁用", 2, SETTINGS.Fly and "Success" or "Warning")
        if not SETTINGS.Fly then stopFly() end
    elseif key == SETTINGS.ScreechSafeRoomKeybind then
        pcall(function()
            local char = getChar()
            if not char then return end
            local closestCabinet = nil
            local closestDist = math.huge
            for _, v in pairs(Workspace:GetDescendants()) do
                if isCabinet(v) and (v:IsA("Model") or v:IsA("BasePart")) then
                    local pp = v:FindFirstChildOfClass("ProximityPrompt", true)
                    local pos = v:IsA("BasePart") and v.Position or (v.PrimaryPart and v.PrimaryPart.Position)
                    if pos and char.PrimaryPart then
                        local dist = (pos - char.PrimaryPart.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestCabinet = pp or v
                        end
                    end
                end
            end
            if closestCabinet then
                firesignal(closestCabinet.Triggered, LocalPlayer)
                notify("安全屋", "已触发最近柜子", 2, "Success")
            else
                notify("安全屋", "附近未找到柜子", 2, "Warning")
            end
        end)
    end
end)

-- ══════════════════════════════════════════════════════════════════
-- 13. 加载完成通知
-- ══════════════════════════════════════════════════════════════════
task.wait(0.3)
notify("✅ Doors 辅助加载完成!",
    "Quantum UI 版本 v1.0\n" ..
    "按 " .. SETTINGS.UIKeybind.Name .. " 切换 UI 显示\n" ..
    "PlaceId: 6839808510 / 7894711641",
    6, "Success")

print("========================================")
print(" Doors 辅助 v1.0 (Quantum UI 版) 加载完成")
print("   UI切换    - " .. SETTINGS.UIKeybind.Name)
print("   穿墙      - " .. SETTINGS.NoclipKeybind.Name)
print("   飞行      - " .. SETTINGS.FlyKeybind.Name)
print("   Screech   - " .. SETTINGS.ScreechSafeRoomKeybind.Name)
print("   PlaceId   - 6839808510 / 7894711641")
print("========================================")
