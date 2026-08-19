--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║                        QUANTUM UI LIBRARY                        ║
    ║                Version 3.2.0 - DangerConfirm API                ║
    ║                         Created by log_quick                     ║
    ║                                                                  ║
    ║  Changelog v3.2.0:                                              ║
    ║  • FIX: Destroy 后无法再次注入的 BUG (清理 _G.QuantumUI_Window,║
    ║       CoreGui 内遗留 QuantumUI_* 实例、RainbowHandler.Objects)  ║
    ║  • NEW: Window:DangerConfirm() 危险确认模态弹窗 API             ║
    ║  • NEW: Tab:AddDangerToggle() 危险开关(带二次确认)              ║
    ║  • NEW: 销毁 UI (Settings→Destroy) 先弹出 DangerConfirm         ║
    ╚══════════════════════════════════════════════════════════════════╝
--]]

local QuantumUI = {}
QuantumUI.__index = QuantumUI
QuantumUI.Version = "3.2.0"
QuantumUI.Author = "log_quick"
QuantumUI.ThemeColor = Color3.fromRGB(0, 200, 255)
QuantumUI.Transparency = 0.3
QuantumUI.RainbowEnabled = true
QuantumUI.RainbowSpeed = 1
QuantumUI.Instance = nil  -- 单例：防止重复注入
QuantumUI.Assets = CustomAssets
QuantumUI.RainbowColors = {
    Color3.fromRGB(255, 0, 0),
    Color3.fromRGB(255, 127, 0),
    Color3.fromRGB(255, 255, 0),
    Color3.fromRGB(0, 255, 0),
    Color3.fromRGB(0, 0, 255),
    Color3.fromRGB(75, 0, 130),
    Color3.fromRGB(143, 0, 255)
}

-- ═══════════════════════════════════════════════════════════════════
--                       KEYAUTH STATIC API
-- ═══════════════════════════════════════════════════════════════════
-- 开发者在 QuantumUI.new() 之前调用 QuantumUI.SetupKeyAuth({...}) 启用
local KeyAuth = {
    Enabled = false,
    ValidKeys = {},       -- [key] = true (plaintext, for shared simple keys)
    ValidHashes = {},     -- [sha256hex] = true (recommended: don't embed raw keys in source)
    BindToHWID = false,   -- key ↔ HWID 绑定，防止一人发群
    HWIDWhitelist = nil,  -- nil = bind to first login hwid; 否则 {hwid=true} 允许
    AllowTrial = false,   -- true = 未授权用户 10 分钟试用
    TrialSeconds = 600,
    OnSuccess = nil,      -- function(key)
    OnFail = nil,         -- function(reason)
    GateOnLoad = false    -- RequireKeyAuth 自动门控（由 RequireKeyAuth 设置）
}

-- 简单可靠的 SHA-256 + base16（用于推荐的哈希模式，避免明文 key 泄漏）
local function sha256hex(str)
    -- 使用 HttpService JSONEncode + 一个临时表？实际上 Roblox 没有内建 hash，
    -- 这里实现一个标准化的 SHA-256 via bit32（兼容大多数 exploit env）
    local b32 = bit32 or bit
    if not b32 then return tostring(str) end
    local bx, brs, bls = b32.bxor, b32.rrotate, b32.lshift
    local band, bor = b32.band, b32.bor
    local k = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    }
    local function pad(msg)
        local len = #msg
        local tbl = {string.byte(msg,1,len)}
        tbl[len+1] = 0x80
        local bits = len*8
        for i = len+2, 64 - ((len+9)%64) do tbl[i]=0 end
        for i=1,8 do tbl[#tbl+1] = band(b32.rshift(bits,(8-i)*8),0xFF) end
        return tbl
    end
    local function sha(data)
        local h0,h1,h2,h3,h4,h5,h6,h7=0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
        local bytes = pad(data)
        for chunk=0, #bytes/64-1 do
            local w = {}
            for i=1,16 do w[i] = bor(bor(bor(bls(bytes[chunk*64+i*4-3],24),bls(bytes[chunk*64+i*4-2],16)),bls(bytes[chunk*64+i*4-1],8)),bytes[chunk*64+i*4]) end
            for i=17,64 do
                local s0 = bx(bx(brs(w[i-15],7),brs(w[i-15],18)),b32.rshift(w[i-15],3))
                local s1 = bx(bx(brs(w[i-2],17),brs(w[i-2],19)),b32.rshift(w[i-2],10))
                w[i] = band(w[i-16]+s0+w[i-7]+s1,0xFFFFFFFF)
            end
            local a,b,c,d,e,f,g,h=h0,h1,h2,h3,h4,h5,h6,h7
            for i=1,64 do
                local S1 = bx(bx(brs(e,6),brs(e,11)),brs(e,25))
                local ch = bx(band(e,f),band(b32.bnot(e),g))
                local t1 = band(h+S1+ch+k[i]+w[i],0xFFFFFFFF)
                local S0 = bx(bx(brs(a,2),brs(a,13)),brs(a,22))
                local mj = bx(bx(band(a,b),band(a,c)),band(b,c))
                local t2 = band(S0+mj,0xFFFFFFFF)
                h=g g=f f=e e=band(d+t1,0xFFFFFFFF) d=c c=b b=a a=band(t1+t2,0xFFFFFFFF)
            end
            h0=band(h0+a,0xFFFFFFFF) h1=band(h1+b,0xFFFFFFFF) h2=band(h2+c,0xFFFFFFFF) h3=band(h3+d,0xFFFFFFFF)
            h4=band(h4+e,0xFFFFFFFF) h5=band(h5+f,0xFFFFFFFF) h6=band(h6+g,0xFFFFFFFF) h7=band(h7+h,0xFFFFFFFF)
        end
        local out = ""
        for _,v in ipairs{h0,h1,h2,h3,h4,h5,h6,h7} do
            for i=7,0,-1 do
                local b = band(b32.rshift(v,i*4),0xF)
                out = out .. string.format("%x",b)
            end
        end
        return out
    end
    return sha(str)
end

-- 稳定硬件 ID（基于 UserId + 机器指纹，不可伪造为他人）
local function GetHWID()
    local uid = tostring(LocalPlayer and LocalPlayer.UserId or 0)
    local accountAge = LocalPlayer and LocalPlayer.AccountAge or 0
    local name = LocalPlayer and LocalPlayer.Name or ""
    local base = ("QUANTUM_HWID_%s_%d_%s"):format(uid, accountAge, name)
    return sha256hex(base):sub(1, 16):upper()
end

-- 保存/读取已授权密钥文件（独立目录 QuantumUI/KeyAuth/）
local KeyAuthPath = "QuantumUI/KeyAuth/saved_key.json"
local function SaveAuthorizedKey(key, hwid)
    pcall(function()
        if not isfolder("QuantumUI") then makefolder("QuantumUI") end
        if not isfolder("QuantumUI/KeyAuth") then makefolder("QuantumUI/KeyAuth") end
        writefile(KeyAuthPath, HttpService:JSONEncode({Key = key, HWID = hwid, Time = os.time()}))
    end)
end
local function LoadAuthorizedKey()
    local ok, res = pcall(function()
        if isfile(KeyAuthPath) then
            return HttpService:JSONDecode(readfile(KeyAuthPath))
        end
        return nil
    end)
    return ok and res or nil
end

function QuantumUI.SetupKeyAuth(options)
    options = options or {}
    KeyAuth.Enabled = true
    KeyAuth.ValidKeys = {}
    KeyAuth.ValidHashes = {}
    if options.Keys then
        for _, k in ipairs(options.Keys) do KeyAuth.ValidKeys[k] = true end
    end
    if options.Hashes then
        for _, h in ipairs(options.Hashes) do KeyAuth.ValidHashes[tostring(h):lower()] = true end
    end
    KeyAuth.BindToHWID = not not options.BindToHWID
    if options.HWIDWhitelist then
        KeyAuth.HWIDWhitelist = {}
        for _, h in ipairs(options.HWIDWhitelist) do KeyAuth.HWIDWhitelist[tostring(h):upper()] = true end
    end
    KeyAuth.AllowTrial = not not options.AllowTrial
    KeyAuth.TrialSeconds = tonumber(options.TrialSeconds) or 600
    KeyAuth.OnSuccess = options.OnSuccess
    KeyAuth.OnFail = options.OnFail
end

function QuantumUI.HashKey(keyStr)
    return sha256hex(tostring(keyStr or "")):lower()
end

function QuantumUI.GetHWID()
    return GetHWID()
end

-- 核心验证：bool success, string reason
local function VerifyKey(inputKey, inputHWID)
    if not KeyAuth.Enabled then return true, "no_keyauth" end
    inputKey = tostring(inputKey or ""):gsub("%s+", "")
    if inputKey == "" then return false, "empty" end
    -- 1. plaintext key
    local matched = KeyAuth.ValidKeys[inputKey] and true or false
    -- 2. hash of input key
    local hash = sha256hex(inputKey):lower()
    matched = matched or (KeyAuth.ValidHashes[hash] and true)
    if not matched then return false, "invalid_key" end
    -- 3. HWID 绑定检查
    if KeyAuth.BindToHWID then
        local hwid = inputHWID or GetHWID()
        -- 白名单优先（开发者自己的 hwid 免首次绑定）
        if KeyAuth.HWIDWhitelist and KeyAuth.HWIDWhitelist[hwid] then
            return true, "authorized_whitelist", hwid
        end
        local saved = LoadAuthorizedKey()
        if saved and saved.Key == inputKey then
            -- 曾经授权过：必须 HWID 一致
            if saved.HWID ~= hwid then return false, "hwid_mismatch", hwid end
            return true, "authorized", hwid
        else
            -- 首次使用该 key：绑定当前 HWID
            SaveAuthorizedKey(inputKey, hwid)
            return true, "bound", hwid
        end
    end
    return true, "authorized", inputHWID or GetHWID()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ╔══════════════════════════════════════════════════════════════╗
-- ║   CUSTOM ASSET TABLE (uploaded via Roblox Studio MCP)        ║
-- ║   Fill in real AssetIds after upload_image completes.        ║
-- ╚══════════════════════════════════════════════════════════════╝
local CustomAssets = {
    -- Backgrounds & panels
    PanelBg        = "rbxassetid://PENDING_BG_PANEL",
    Divider        = "rbxassetid://PENDING_DIVIDER",
    -- Buttons
    BtnPrimary     = "rbxassetid://PENDING_BTN_PRIMARY",
    BtnHover       = "rbxassetid://PENDING_BTN_HOVER",
    -- Tab / section icons
    IconSettings   = "rbxassetid://PENDING_ICON_SETTINGS",
    IconPlayer     = "rbxassetid://PENDING_ICON_PLAYER",
    IconCode       = "rbxassetid://PENDING_ICON_CODE",
    IconWorld      = "rbxassetid://PENDING_ICON_WORLD",
}

local Sounds = {
    Click = "rbxassetid://6895079853",
    Hover = "rbxassetid://6895079709",
    Toggle = "rbxassetid://6895079565",
    Open = "rbxassetid://6895079422",
    Close = "rbxassetid://6895079278",
    ConfigLoad = "rbxassetid://6026984224",
    ConfigSave = "rbxassetid://6895079134",
    Startup = "rbxassetid://5853855460",
    Error = "rbxassetid://6895078990",
    Notification = "rbxassetid://4590657391",
    SpecialLoad = "rbxassetid://5856815743"
}

-- ═══════════════════════════════════════════════════════════════
--               SQUARE-CORNER (NO UICorner) MODE
--   Set USE_SQUARE_CORNERS = true to strip ALL rounded corners.
-- ═══════════════════════════════════════════════════════════════
local USE_SQUARE_CORNERS = true

-- ═══════════════════════════════════════════════════════════════════
--                          UTILITY
-- ═══════════════════════════════════════════════════════════════════

local Utility = {}

function Utility.Create(className, properties, children)
    if className == "UICorner" and USE_SQUARE_CORNERS then
        local proxy = {Parent = nil, Destroy = function() end, IsA = function() return false end}
        local mt = {}
        mt.__newindex = function() end
        mt.__index = function() return nil end
        setmetatable(proxy, mt)
        function proxy:GetPropertyChangedSignal()
            local e = {Connect = function() return {Disconnect = function() end} end}
            return e
        end
        return proxy
    end
    local instance = Instance.new(className)
    for prop, value in pairs(properties or {}) do
        if prop ~= "Parent" then
            pcall(function() instance[prop] = value end)
        end
    end
    for _, child in pairs(children or {}) do
        if child and child ~= true then
            local ok = pcall(function() child.Parent = instance end)
            if not ok then
                pcall(function()
                    if type(child) == "userdata" then child.Parent = instance end
                end)
            end
        end
    end
    if properties and properties.Parent then
        instance.Parent = properties.Parent
    end
    return instance
end

function Utility.Tween(object, properties, duration, style, direction)
    if not object then return end
    local tween = TweenService:Create(object, TweenInfo.new(duration or 0.3, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out), properties)
    tween:Play()
    return tween
end

function Utility.PlaySound(soundId, volume)
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = soundId
        sound.Volume = volume or 0.5
        sound.Parent = SoundService
        sound:Play()
        sound.Ended:Connect(function() sound:Destroy() end)
    end)
end

function Utility.Ripple(parent, position, color)
    if not parent then return end
    local ripple = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = color or Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.7,
        BorderSizePixel = 0,
        Position = UDim2.new(0, position.X - parent.AbsolutePosition.X, 0, position.Y - parent.AbsolutePosition.Y),
        Size = UDim2.new(0, 0, 0, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ZIndex = 100
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    
    local maxSize = math.max(parent.AbsoluteSize.X, parent.AbsoluteSize.Y) * 2
    Utility.Tween(ripple, {Size = UDim2.new(0, maxSize, 0, maxSize), BackgroundTransparency = 1}, 0.5)
    task.delay(0.5, function() if ripple then ripple:Destroy() end end)
end

function Utility.CreateGradient(colors, rotation)
    local gradient = Instance.new("UIGradient")
    if #colors >= 2 then
        local seq = {}
        for i, c in ipairs(colors) do
            table.insert(seq, ColorSequenceKeypoint.new((i-1)/(#colors-1), c))
        end
        gradient.Color = ColorSequence.new(seq)
    end
    gradient.Rotation = rotation or 0
    return gradient
end

function Utility.HSVToRGB(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return Color3.new(r, g, b)
end

function Utility.RGBToHSV(color)
    local r, g, b = color.R, color.G, color.B
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local h, s, v = 0, 0, max
    local d = max - min
    s = max == 0 and 0 or d / max
    if max ~= min then
        if max == r then h = (g - b) / d + (g < b and 6 or 0)
        elseif max == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, s, v
end

function Utility.ScreenFlash(color, duration, intensity)
    pcall(function()
        local gui = Utility.Create("ScreenGui", {
            Parent = LocalPlayer:FindFirstChild("PlayerGui"),
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder = 99999,
            IgnoreGuiInset = true
        })
        local flash = Utility.Create("Frame", {
            Parent = gui,
            BackgroundColor3 = color,
            BackgroundTransparency = 1 - (intensity or 0.4),
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 1, 0)
        })
        task.spawn(function()
            Utility.Tween(flash, {BackgroundTransparency = 0.3}, (duration or 0.5) * 0.2)
            task.wait((duration or 0.5) * 0.2)
            Utility.Tween(flash, {BackgroundTransparency = 1}, (duration or 0.5) * 0.8)
            task.wait((duration or 0.5) * 0.8)
            gui:Destroy()
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--                          CONFIG SYSTEM (COMPLETELY REWRITTEN)
-- ═══════════════════════════════════════════════════════════════════

local ConfigSystem = {}

-- 默认目录：功能配置
local DEFAULT_FOLDER = "QuantumUI/Configs"
-- UI 配置独立目录
local UI_CONFIG_FOLDER = "QuantumUI/UIConfigs"

function ConfigSystem.Init(folder)
    folder = folder or DEFAULT_FOLDER
    pcall(function()
        if not isfolder("QuantumUI") then makefolder("QuantumUI") end
        if not isfolder(folder) then makefolder(folder) end
    end)
end

function ConfigSystem.Save(name, data, folder)
    folder = folder or DEFAULT_FOLDER
    ConfigSystem.Init(folder)
    local success = pcall(function()
        writefile(folder .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
    return success
end

function ConfigSystem.Load(name, folder)
    folder = folder or DEFAULT_FOLDER
    local success, data = pcall(function()
        if isfile(folder .. "/" .. name .. ".json") then
            return HttpService:JSONDecode(readfile(folder .. "/" .. name .. ".json"))
        end
        return nil
    end)
    return success and data or nil
end

function ConfigSystem.Delete(name, folder)
    folder = folder or DEFAULT_FOLDER
    pcall(function()
        if isfile(folder .. "/" .. name .. ".json") then
            delfile(folder .. "/" .. name .. ".json")
        end
    end)
end

function ConfigSystem.List(folder)
    folder = folder or DEFAULT_FOLDER
    local list = {}
    pcall(function()
        if isfolder(folder) then
            for _, file in ipairs(listfiles(folder)) do
                local name = file:match("([^/\\]+)%.json$")
                if name then table.insert(list, name) end
            end
        end
    end)
    return list
end

-- UI Config 专用快捷方法
function ConfigSystem.SaveUI(name, data)
    return ConfigSystem.Save(name, data, UI_CONFIG_FOLDER)
end

function ConfigSystem.LoadUI(name)
    return ConfigSystem.Load(name, UI_CONFIG_FOLDER)
end

function ConfigSystem.DeleteUI(name)
    return ConfigSystem.Delete(name, UI_CONFIG_FOLDER)
end

function ConfigSystem.ListUI()
    return ConfigSystem.List(UI_CONFIG_FOLDER)
end

function ConfigSystem.SaveAutoLoad(configName)
    ConfigSystem.Init()
    pcall(function()
        writefile("QuantumUI/autoload.txt", configName or "")
    end)
end

function ConfigSystem.GetAutoLoad()
    local success, name = pcall(function()
        if isfile("QuantumUI/autoload.txt") then
            return readfile("QuantumUI/autoload.txt")
        end
        return nil
    end)
    if success and name and name ~= "" then
        return name
    end
    return nil
end

function ConfigSystem.ClearAutoLoad()
    pcall(function()
        if isfile("QuantumUI/autoload.txt") then
            delfile("QuantumUI/autoload.txt")
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--                          RAINBOW HANDLER
-- ═══════════════════════════════════════════════════════════════════

local RainbowHandler = {Objects = {}, Connection = nil}

function RainbowHandler.Add(object)
    table.insert(RainbowHandler.Objects, object)
end

function RainbowHandler.Start()
    if RainbowHandler.Connection then return end
    local hue = 0
    RainbowHandler.Connection = RunService.RenderStepped:Connect(function(dt)
        if not QuantumUI.RainbowEnabled then return end
        hue = (hue + dt * QuantumUI.RainbowSpeed * 0.1) % 1
        for i = #RainbowHandler.Objects, 1, -1 do
            local obj = RainbowHandler.Objects[i]
            if obj and obj.Parent then
                local gradient = obj:FindFirstChildOfClass("UIGradient")
                if gradient then
                    local colors = {}
                    for j = 1, 7 do
                        colors[j] = ColorSequenceKeypoint.new((j-1)/6, Utility.HSVToRGB((hue + (j-1)/7) % 1, 1, 1))
                    end
                    gradient.Color = ColorSequence.new(colors)
                end
            else
                table.remove(RainbowHandler.Objects, i)
            end
        end
    end)
end

function RainbowHandler.Stop()
    if RainbowHandler.Connection then
        RainbowHandler.Connection:Disconnect()
        RainbowHandler.Connection = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════
--                          MAIN LIBRARY
-- ═══════════════════════════════════════════════════════════════════

function QuantumUI.new(options)
    options = options or {}
    
    -- 单例保护：使用 _G 全局变量（跨 loadstring 持久）
    if _G.QuantumUI_Instance then
        pcall(function() _G.QuantumUI_Instance:Destroy() end)
        _G.QuantumUI_Instance = nil
    end
    
    local self = setmetatable({}, QuantumUI)
    self.Title = options.Title or "Quantum UI"
    self.Subtitle = options.Subtitle or "by log_quick"
    self.ThemeColor = options.ThemeColor or Color3.fromRGB(0, 200, 255)
    self.Transparency = options.Transparency or 0.3
    self.Size = options.Size or (IsMobile and UDim2.new(0.95, 0, 0.85, 0) or UDim2.new(0, 600, 0, 450))
    self.BackgroundImage = options.BackgroundImage or nil
    self.BackgroundTransparency = options.BackgroundTransparency or 0.5
    self.Tabs = {}
    self.Flags = {}
    self.Elements = {}
    self.ConfigData = {}
    self.ThemeElements = {}
    self.Keybind = options.Keybind or Enum.KeyCode.RightControl
    self.Visible = true
    self.Minimized = false
    self.Maximized = false
    self.CanDrag = true
    self.SavedPosition = nil
    self.SavedSize = nil
    self.BackgroundLabel = nil
    
    QuantumUI.ThemeColor = self.ThemeColor
    QuantumUI.Transparency = self.Transparency
    
    -- 注册到 _G 全局，确保跨 loadstring 可见
    _G.QuantumUI_Instance = self
    
    -- Initialize config system
    ConfigSystem.Init()
    
    self:Initialize()
    
    return self
end

function QuantumUI:Initialize()
    self.ScreenGui = Utility.Create("ScreenGui", {
        Name = "QuantumUI_" .. HttpService:GenerateGUID(false),
        Parent = CoreGui,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        DisplayOrder = 999
    })
    
    self:CreateLoadingScreen()
end

function QuantumUI:CreateLoadingScreen()
    local loadingFrame = Utility.Create("Frame", {
        Name = "LoadingScreen",
        Parent = self.ScreenGui,
        BackgroundColor3 = Color3.fromRGB(10, 10, 20),
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 1000
    })
    
    for i = 1, 20 do
        Utility.Create("Frame", {
            Parent = loadingFrame,
            BackgroundColor3 = self.ThemeColor,
            BackgroundTransparency = 0.92,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 1),
            Position = UDim2.new(0, 0, i/20 - 0.025, 0)
        })
    end
    for i = 1, 30 do
        Utility.Create("Frame", {
            Parent = loadingFrame,
            BackgroundColor3 = self.ThemeColor,
            BackgroundTransparency = 0.92,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 1, 1, 0),
            Position = UDim2.new(i/30 - 0.017, 0, 0, 0)
        })
    end
    
    local logoContainer = Utility.Create("Frame", {
        Parent = loadingFrame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 180, 0, 180),
        Position = UDim2.new(0.5, 0, 0.35, 0),
        AnchorPoint = Vector2.new(0.5, 0.5)
    })
    
    local ring = Utility.Create("ImageLabel", {
        Parent = logoContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(1.2, 0, 1.2, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Image = "rbxassetid://6034281467",
        ImageColor3 = self.ThemeColor,
        ImageTransparency = 0.5
    })
    
    Utility.Create("TextLabel", {
        Parent = logoContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.5, 0, 0.5, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Font = Enum.Font.GothamBold,
        Text = "Q",
        TextColor3 = self.ThemeColor,
        TextScaled = true
    })
    
    local title = Utility.Create("TextLabel", {
        Parent = loadingFrame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 50),
        Position = UDim2.new(0, 0, 0.55, 0),
        Font = Enum.Font.GothamBold,
        Text = "QUANTUM UI",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 32,
        TextTransparency = 1
    })
    
    local subtitle = Utility.Create("TextLabel", {
        Parent = loadingFrame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 25),
        Position = UDim2.new(0, 0, 0.55, 45),
        Font = Enum.Font.Gotham,
        Text = "INITIALIZING...",
        TextColor3 = self.ThemeColor,
        TextSize = 14,
        TextTransparency = 1
    })
    
    local loadingBarBg = Utility.Create("Frame", {
        Parent = loadingFrame,
        BackgroundColor3 = Color3.fromRGB(30, 30, 40),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Size = UDim2.new(0.35, 0, 0, 6),
        Position = UDim2.new(0.325, 0, 0.7, 0)
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    
    local loadingBar = Utility.Create("Frame", {
        Parent = loadingBarBg,
        BackgroundColor3 = self.ThemeColor,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0)
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    
    local rotation = 0
    local rotateConn = RunService.RenderStepped:Connect(function(dt)
        rotation = rotation + dt * 50
        ring.Rotation = rotation
    end)
    
    Utility.PlaySound(Sounds.Startup, 0.6)
    
    task.spawn(function()
        task.wait(0.3)
        Utility.Tween(title, {TextTransparency = 0}, 0.4)
        Utility.Tween(subtitle, {TextTransparency = 0}, 0.4)
        
        local steps = {
            {0.2, "Loading components..."},
            {0.4, "Initializing theme..."},
            {0.6, "Setting up config..."},
            {0.8, "Preparing UI..."},
            {1.0, "Ready!"}
        }
        
        for _, step in ipairs(steps) do
            Utility.Tween(loadingBar, {Size = UDim2.new(step[1], 0, 1, 0)}, 0.25)
            subtitle.Text = step[2]
            Utility.PlaySound(Sounds.Click, 0.15)
            task.wait(0.25)
        end
        
        task.wait(0.3)
        Utility.Tween(loadingFrame, {BackgroundTransparency = 1}, 0.4)
        for _, child in ipairs(loadingFrame:GetDescendants()) do
            if child:IsA("TextLabel") then
                Utility.Tween(child, {TextTransparency = 1}, 0.4)
            elseif child:IsA("ImageLabel") then
                Utility.Tween(child, {ImageTransparency = 1}, 0.4)
            elseif child:IsA("Frame") then
                Utility.Tween(child, {BackgroundTransparency = 1}, 0.4)
            end
        end
        
        task.wait(0.4)
        rotateConn:Disconnect()
        loadingFrame:Destroy()
        
        -- KeyAuth Gate: 若启用了 RequireKeyAuth 且未授权，阻塞在 KeyGate 界面
        if KeyAuth.Enabled and KeyAuth.GateOnLoad then
            local authed = self:RunKeyGate(loadingFrame)
            if not authed then
                -- 用户取消/失败：销毁 UI，不进入主界面
                self:Destroy()
                return
            end
        end
        
        self:CreateMainWindow()
    end)
end

function QuantumUI:CreateMainWindow()
    self.MainFrame = Utility.Create("Frame", {
        Name = "MainFrame",
        Parent = self.ScreenGui,
        BackgroundColor3 = Color3.fromRGB(15, 15, 25),
        BackgroundTransparency = self.Transparency,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ClipsDescendants = true
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 12)})})
    
    -- NEW: Custom Background Image
    if self.BackgroundImage then
        self.BackgroundLabel = Utility.Create("ImageLabel", {
            Name = "BackgroundImage",
            Parent = self.MainFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            Image = self.BackgroundImage,
            ImageTransparency = self.BackgroundTransparency,
            ScaleType = Enum.ScaleType.Crop,
            ZIndex = 0
        })
    end
    
    -- Rainbow Border
    local borderStroke = Utility.Create("UIStroke", {
        Parent = self.MainFrame,
        Color = self.ThemeColor,
        Thickness = 2,
        Transparency = 0.3
    })
    self:AddThemeElement(borderStroke, "Color")
    local borderGradient = Utility.CreateGradient(QuantumUI.RainbowColors, 0)
    borderGradient.Parent = borderStroke
    RainbowHandler.Add(borderStroke)
    RainbowHandler.Start()
    
    -- Scanlines
    Utility.Create("ImageLabel", {
        Parent = self.MainFrame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Image = "rbxassetid://594768915",
        ImageTransparency = 0.96,
        ScaleType = Enum.ScaleType.Tile,
        TileSize = UDim2.new(0, 100, 0, 100),
        ZIndex = 2
    })
    
    -- Top Bar
    local topBar = Utility.Create("Frame", {
        Name = "TopBar",
        Parent = self.MainFrame,
        BackgroundColor3 = Color3.fromRGB(20, 20, 35),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 50),
        ZIndex = 10
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 12)})})
    
    Utility.Create("Frame", {
        Parent = topBar,
        BackgroundColor3 = Color3.fromRGB(20, 20, 35),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 1, -20),
        ZIndex = 9
    })
    
    Utility.Create("TextLabel", {
        Parent = topBar,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 10, 0, 5),
        Font = Enum.Font.GothamBold,
        Text = "Q",
        TextColor3 = self.ThemeColor,
        TextSize = 28,
        ZIndex = 11
    })
    
    Utility.Create("TextLabel", {
        Parent = topBar,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 200, 0, 25),
        Position = UDim2.new(0, 55, 0, 5),
        Font = Enum.Font.GothamBold,
        Text = self.Title,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 11
    })
    
    Utility.Create("TextLabel", {
        Parent = topBar,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 200, 0, 15),
        Position = UDim2.new(0, 55, 0, 30),
        Font = Enum.Font.Gotham,
        Text = self.Subtitle,
        TextColor3 = Color3.fromRGB(150, 150, 150),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 11
    })
    
    local controls = Utility.Create("Frame", {
        Parent = topBar,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 90, 0, 30),
        Position = UDim2.new(1, -100, 0, 10),
        ZIndex = 11
    })
    
    local minimizeBtn = self:CreateControlButton(controls, "—", Color3.fromRGB(255, 190, 0), 0)
    local maximizeBtn = self:CreateControlButton(controls, "□", Color3.fromRGB(0, 200, 100), 30)
    local closeBtn = self:CreateControlButton(controls, "×", Color3.fromRGB(255, 80, 80), 60)
    
    local tabWidth = IsMobile and 50 or 150
    local tabContainer = Utility.Create("Frame", {
        Name = "TabContainer",
        Parent = self.MainFrame,
        BackgroundColor3 = Color3.fromRGB(18, 18, 30),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(0, tabWidth - 1, 1, -52),
        Position = UDim2.new(0, 1, 0, 51),
        ZIndex = 5
    })
    
    local tabList = Utility.Create("ScrollingFrame", {
        Name = "TabList",
        Parent = tabContainer,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -10),
        Position = UDim2.new(0, 0, 0, 5),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = self.ThemeColor,
        ZIndex = 6
    }, {
        Utility.Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5)}),
        Utility.Create("UIPadding", {PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingTop = UDim.new(0, 5)})
    })
    
    local contentContainer = Utility.Create("Frame", {
        Name = "ContentContainer",
        Parent = self.MainFrame,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -tabWidth - 1, 1, -52),
        Position = UDim2.new(0, tabWidth, 0, 51),
        ZIndex = 5
    })
    
    self.TopBar = topBar
    self.TabContainer = tabContainer
    self.TabList = tabList
    self.ContentContainer = contentContainer
    
    self:SetupDragging()
    self:SetupBorderDragging()
    self:SetupControlButtons(minimizeBtn, maximizeBtn, closeBtn)
    self:SetupKeybind()
    self:CreateFloatingButton()
    
    Utility.PlaySound(Sounds.Open, 0.5)
    Utility.Tween(self.MainFrame, {Size = self.Size}, 0.5, Enum.EasingStyle.Back)
    
    -- Create settings tab and handle auto-load
    task.spawn(function()
        task.wait(0.6)
        self:CreateSettingsTab()
        
        -- AUTO LOAD CONFIG (FIXED!)
        task.wait(0.5)
        self:TryAutoLoadConfig()
    end)
end

-- NEW: Set custom background
function QuantumUI:SetBackground(imageId, transparency)
    self.BackgroundImage = imageId
    self.BackgroundTransparency = transparency or self.Transparency
    
    -- 设置背景时同步让 MainFrame 变透明，否则背景图被深色底色盖住
    if self.MainFrame then
        Utility.Tween(self.MainFrame, {BackgroundTransparency = 1}, 0.3)
    end
    
    if self.BackgroundLabel then
        self.BackgroundLabel.Image = imageId
        self.BackgroundLabel.ImageTransparency = self.BackgroundTransparency
    elseif self.MainFrame then
        self.BackgroundLabel = Utility.Create("ImageLabel", {
            Name = "BackgroundImage",
            Parent = self.MainFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            Image = imageId,
            ImageTransparency = self.BackgroundTransparency,
            ScaleType = Enum.ScaleType.Crop,
            ZIndex = 0
        })
    end
end

-- NEW: Update background transparency
function QuantumUI:SetBackgroundTransparency(transparency)
    self.BackgroundTransparency = transparency
    if self.BackgroundLabel then
        Utility.Tween(self.BackgroundLabel, {ImageTransparency = transparency}, 0.3)
    end
end

-- NEW: Remove background
function QuantumUI:RemoveBackground()
    self.BackgroundImage = nil
    if self.BackgroundLabel then
        self.BackgroundLabel:Destroy()
        self.BackgroundLabel = nil
    end
    -- 恢复 MainFrame 原本的背景透明度
    if self.MainFrame then
        Utility.Tween(self.MainFrame, {BackgroundTransparency = self.Transparency}, 0.3)
    end
end

-- FIXED: Auto load config function
function QuantumUI:TryAutoLoadConfig()
    local autoLoadName = ConfigSystem.GetAutoLoad()
    
    if autoLoadName and autoLoadName ~= "" then
        print("[QuantumUI] Auto loading config:", autoLoadName)
        
        local configData = ConfigSystem.Load(autoLoadName)
        
        if configData then
            -- Wait a bit for all elements to be ready
            task.wait(0.3)
            
            -- Apply the config
            self:ApplyConfig(configData)
            
            -- Visual feedback
            Utility.PlaySound(Sounds.SpecialLoad, 0.7)
            Utility.ScreenFlash(self.ThemeColor, 0.5, 0.4)
            
            self:Notify({
                Title = "✅ Auto Loaded!",
                Content = "Config '" .. autoLoadName .. "' loaded automatically.",
                Duration = 4,
                Type = "Success"
            })
            
            print("[QuantumUI] Auto load complete!")
        else
            print("[QuantumUI] Auto load config not found:", autoLoadName)
        end
    else
        print("[QuantumUI] No auto load config set")
    end
end

-- Apply config to all flagged elements
function QuantumUI:ApplyConfig(configData)
    if not configData then return end
    
    for flag, value in pairs(configData) do
        local element = self.Flags[flag]
        if element and element.Set then
            local ok, err = pcall(function()
                if type(value) == "table" then
                    if value._type == "Color3" then
                        -- R,G,B 可能是 0-255 整数（fromRGB序列化）也可能是 0-1 浮点数
                        -- 统一按 Color3.new 处理：如果 > 1 则 /255
                        local r = value.R > 1 and value.R / 255 or value.R
                        local g = value.G > 1 and value.G / 255 or value.G
                        local b = value.B > 1 and value.B / 255 or value.B
                        element:Set(Color3.new(r, g, b))
                    elseif value._type == "KeyCode" then
                        element:Set(Enum.KeyCode[value.Name] or Enum.KeyCode.Unknown)
                    elseif value._type == "table" then
                        element:Set(value._data)
                    else
                        element:Set(value)
                    end
                else
                    element:Set(value)
                end
            end)
            if not ok then
                warn("[QuantumUI] ApplyConfig error for flag '" .. tostring(flag) .. "':", err)
            end
        end
    end
end

function QuantumUI:CreateControlButton(parent, text, color, xOffset)
    local btn = Utility.Create("TextButton", {
        Parent = parent,
        BackgroundColor3 = color,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 25, 0, 25),
        Position = UDim2.new(0, xOffset, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = text,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = text == "×" and 20 or 14,
        ZIndex = 12
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)})})
    
    btn.MouseEnter:Connect(function()
        Utility.PlaySound(Sounds.Hover, 0.1)
        Utility.Tween(btn, {BackgroundTransparency = 0.2}, 0.2)
    end)
    btn.MouseLeave:Connect(function()
        Utility.Tween(btn, {BackgroundTransparency = 0.5}, 0.2)
    end)
    
    return btn
end

function QuantumUI:SetupBorderDragging()
    local edges = {
        {size = UDim2.new(0, 12, 1, 0), pos = UDim2.new(0, 0, 0, 0)},
        {size = UDim2.new(0, 12, 1, 0), pos = UDim2.new(1, -12, 0, 0)},
        {size = UDim2.new(1, 0, 0, 12), pos = UDim2.new(0, 0, 1, -12)},
    }
    
    for _, edge in ipairs(edges) do
        local edgeFrame = Utility.Create("Frame", {
            Parent = self.MainFrame,
            BackgroundTransparency = 1,
            Size = edge.size,
            Position = edge.pos,
            ZIndex = 50
        })
        
        local dragging, dragStart, startPos = false, nil, nil
        
        edgeFrame.InputBegan:Connect(function(input)
            if self.Maximized or not self.CanDrag then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = self.MainFrame.Position
            end
        end)
        
        edgeFrame.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
        
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                self.MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end
end

function QuantumUI:SetupDragging()
    local dragging, dragStart, startPos = false, nil, nil
    
    self.TopBar.InputBegan:Connect(function(input)
        if self.Maximized or not self.CanDrag then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = self.MainFrame.Position
        end
    end)
    
    self.TopBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            self.MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

function QuantumUI:SetupControlButtons(minimize, maximize, close)
    minimize.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        if self.MainFrame.Size.Y.Offset > 60 or self.MainFrame.Size.Y.Scale > 0.1 then
            self._savedSize = self.MainFrame.Size
            Utility.Tween(self.MainFrame, {Size = UDim2.new(self.MainFrame.Size.X.Scale, self.MainFrame.Size.X.Offset, 0, 50)}, 0.3)
        else
            Utility.Tween(self.MainFrame, {Size = self._savedSize or self.Size}, 0.3)
        end
    end)
    
    maximize.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        if self.Maximized then
            self.Maximized = false
            self.CanDrag = true
            Utility.Tween(self.MainFrame, {Size = self.SavedSize or self.Size, Position = self.SavedPosition or UDim2.new(0.5, 0, 0.5, 0)}, 0.3)
            maximize.Text = "□"
        else
            self.Maximized = true
            self.CanDrag = false
            self.SavedSize = self.MainFrame.Size
            self.SavedPosition = self.MainFrame.Position
            Utility.Tween(self.MainFrame, {Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}, 0.3)
            maximize.Text = "❐"
        end
    end)
    
    close.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Close, 0.3)
        self:MinimizeToButton()
    end)
end

function QuantumUI:CreateFloatingButton()
    self.FloatingButton = Utility.Create("TextButton", {
        Parent = self.ScreenGui,
        BackgroundColor3 = self.ThemeColor,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Font = Enum.Font.GothamBold,
        Text = "Q",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 24,
        TextTransparency = 1,
        Visible = false,
        ZIndex = 1000,
        AutoLocalize = false
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)}),
        Utility.Create("UIStroke", {Color = Color3.fromRGB(255, 255, 255), Thickness = 2, Transparency = 0.5})
    })
    
    local DRAG_THRESHOLD = 5  -- 拖动超过 5px 视为拖动而非点击
    local dragging, dragStart, startPos = false, nil, nil
    local didDrag = false
    
    self.FloatingButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            didDrag = false
            dragStart = input.Position
            startPos = self.FloatingButton.Position
        end
    end)
    self.FloatingButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if math.abs(delta.X) > DRAG_THRESHOLD or math.abs(delta.Y) > DRAG_THRESHOLD then
                didDrag = true
            end
            if didDrag then
                self.FloatingButton.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
    
    self.FloatingButton.MouseButton1Click:Connect(function()
        -- 只有在未发生拖动时才执行打开 UI
        if didDrag then return end
        Utility.PlaySound(Sounds.Open, 0.5)
        self:RestoreFromMinimize()
    end)
end

function QuantumUI:MinimizeToButton()
    if self.Minimized then return end
    self.Minimized = true
    
    local pos = self.MainFrame.AbsolutePosition
    local size = self.MainFrame.AbsoluteSize
    
    -- 保存最小化前的位置，展开时恢复
    self._SavedFramePosition = self.MainFrame.Position
    
    Utility.Tween(self.MainFrame, {Size = UDim2.new(0, 0, 0, 0)}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.wait(0.3)
    self.MainFrame.Visible = false
    
    self.FloatingButton.Position = UDim2.new(0, pos.X + size.X/2, 0, pos.Y + size.Y/2)
    self.FloatingButton.Size = UDim2.new(0, 0, 0, 0)
    self.FloatingButton.TextTransparency = 1
    self.FloatingButton.Visible = true
    Utility.Tween(self.FloatingButton, {Size = UDim2.new(0, 50, 0, 50), TextTransparency = 0}, 0.3, Enum.EasingStyle.Back)
end

function QuantumUI:RestoreFromMinimize()
    if not self.Minimized then return end
    self.Minimized = false
    
    Utility.Tween(self.FloatingButton, {Size = UDim2.new(0, 0, 0, 0), TextTransparency = 1}, 0.2)
    task.wait(0.2)
    self.FloatingButton.Visible = false
    
    -- 恢复到最小化前的位置（没有保存过则用当前小球位置展开到附近，避免跳变）
    local targetPos = self._SavedFramePosition or self.MainFrame.Position
    if not self._SavedFramePosition and self.FloatingButton then
        local fbPos = self.FloatingButton.AbsolutePosition
        local w = self.Size.X.Offset or 600
        local h = self.Size.Y.Offset or 400
        targetPos = UDim2.new(0, fbPos.X - w/2, 0, fbPos.Y - h/2)
    end
    self.MainFrame.Position = targetPos
    self.MainFrame.Size = UDim2.new(0, 0, 0, 0)
    self.MainFrame.Visible = true
    Utility.Tween(self.MainFrame, {Size = self.Size, Position = targetPos}, 0.4, Enum.EasingStyle.Back)
end

function QuantumUI:SetupKeybind()
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == self.Keybind then
            if self.Minimized then self:RestoreFromMinimize() else self:MinimizeToButton() end
        end
    end)
end

function QuantumUI:Destroy()
    RainbowHandler.Stop()
    -- 清空 RainbowHandler 对象池 (防止重注入时残留的死亡引用影响渲染)
    table.clear(RainbowHandler.Objects)
    if self.ScreenGui then self.ScreenGui:Destroy() end
    -- 清理 _G 全局引用
    if _G.QuantumUI_Instance == self then
        _G.QuantumUI_Instance = nil
    end
    if _G.QuantumUI_Window == self then
        _G.QuantumUI_Window = nil
    end
    -- 兜底：CoreGui 中任何 QuantumUI_ 前缀的孤儿实例都清理掉
    pcall(function()
        for _, child in ipairs(CoreGui:GetChildren()) do
            if child:IsA("ScreenGui") and child.Name:sub(1, 9) == "QuantumUI_" then
                pcall(function() child:Destroy() end)
            end
        end
    end)
end

function QuantumUI:UpdateContentSize(parent, delayAfter)
    if parent and parent:IsA("ScrollingFrame") then
        local layout = parent:FindFirstChildOfClass("UIListLayout")
        if layout then
            task.defer(function()
                parent.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
            end)
            -- 双重保险：如果提供了 delayAfter（通常是 Tween 时长），
            -- 等待动画结束后再更新一次，防止动画期间 AbsoluteContentSize 没及时触发 Changed
            if type(delayAfter) == "number" and delayAfter > 0 then
                task.delay(delayAfter + 0.02, function()
                    if parent and parent.Parent and layout and layout.Parent then
                        parent.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
                    end
                end)
            end
        end
    end
end

-- NEW: Set UI transparency (also updates background)
function QuantumUI:SetTransparency(transparency)
    self.Transparency = transparency
    QuantumUI.Transparency = transparency
    
    if self.MainFrame then
        Utility.Tween(self.MainFrame, {BackgroundTransparency = transparency}, 0.3)
    end
    
    -- Sync background transparency
    if self.BackgroundLabel then
        local bgTransparency = math.max(0, transparency - 0.2)  -- Background slightly more visible
        Utility.Tween(self.BackgroundLabel, {ImageTransparency = bgTransparency}, 0.3)
    end
end

function QuantumUI:AddThemeElement(element, property)
    if element then
        table.insert(self.ThemeElements, {element, property})
    end
end

function QuantumUI:RefreshTheme()
    local c = self.ThemeColor
    QuantumUI.ThemeColor = c
    
    -- Clean up destroyed elements first
    local cleaned = {}
    for _, entry in ipairs(self.ThemeElements) do
        local elem, prop = entry[1], entry[2]
        if elem and elem.Parent then
            if prop == "BackgroundColor3" then
                elem.BackgroundColor3 = c
            elseif prop == "TextColor3" then
                elem.TextColor3 = c
            elseif prop == "Color" then
                elem.Color = c
            elseif prop == "ImageColor3" then
                elem.ImageColor3 = c
            elseif prop == "ScrollBarImageColor3" then
                elem.ScrollBarImageColor3 = c
            end
            table.insert(cleaned, entry)
        end
    end
    self.ThemeElements = cleaned
    
    -- Update selected tab icon color
    if self.SelectedTab and self.SelectedTab.Icon then
        self.SelectedTab.Icon.ImageColor3 = c
    end
    
    -- Update rainbow border color
    if self.MainFrame then
        local stroke = self.MainFrame:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = c end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--                          TAB SYSTEM
-- ═══════════════════════════════════════════════════════════════════

function QuantumUI:AddTab(options)
    options = options or {}
    local tabName = options.Name or "Tab"
    local tabIcon = options.Icon or "rbxassetid://6031280882"
    
    local tab = {Name = tabName, Elements = {}}
    
    local iconOffset = IsMobile and 12 or 10
    local iconSize = 20
    local textStartX = iconOffset + iconSize + 8

    local tabButton = Utility.Create("TextButton", {
        Parent = self.TabList,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, IsMobile and 45 or 40),
        Text = "",
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})

    local icon = Utility.Create("ImageLabel", {
        Parent = tabButton,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, iconSize, 0, iconSize),
        Position = UDim2.new(0, iconOffset, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Image = tabIcon,
        ImageColor3 = Color3.fromRGB(200, 200, 200),
        ZIndex = 8
    })

    local textLabel
    if not IsMobile then
        textLabel = Utility.Create("TextLabel", {
            Parent = tabButton,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -textStartX - 5, 1, 0),
            Position = UDim2.new(0, textStartX, 0, 0),
            Font = Enum.Font.GothamSemibold,
            Text = tabName,
            TextColor3 = Color3.fromRGB(200, 200, 200),
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 9
        })
    end
    
    local indicator = Utility.Create("Frame", {
        Parent = tabButton,
        BackgroundColor3 = self.ThemeColor,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 3, 0.6, 0),
        Position = UDim2.new(0, 0, 0.2, 0),
        Visible = false,
        ZIndex = 8
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 2)})})
    self:AddThemeElement(indicator, "BackgroundColor3")
    
    local tabPage = Utility.Create("ScrollingFrame", {
        Parent = self.ContentContainer,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 1, -20),
        Position = UDim2.new(0, 10, 0, 10),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = self.ThemeColor,
        Visible = false,
        ZIndex = 6
    }, {
        Utility.Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10)}),
        Utility.Create("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5)})
    })
    self:AddThemeElement(tabPage, "ScrollBarImageColor3")

    -- 自动更新滚动区域大小：内容高度变化（例如 Tween 动画）时实时更新 CanvasSize
    local pageLayout = tabPage:FindFirstChildOfClass("UIListLayout")
    if pageLayout then
        pageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            local newCanvas = UDim2.new(0, 0, 0, pageLayout.AbsoluteContentSize.Y + 20)
            if tabPage.CanvasSize ~= newCanvas then
                tabPage.CanvasSize = newCanvas
            end
        end)
    end
    
    tab.Button = tabButton
    tab.Page = tabPage
    tab.Indicator = indicator
    tab.Icon = icon
    tab.TextLabel = textLabel
    
    tabButton.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        self:SelectTab(tab)
    end)
    
    tabButton.MouseEnter:Connect(function()
        Utility.PlaySound(Sounds.Hover, 0.1)
        Utility.Tween(tabButton, {BackgroundTransparency = 0.3}, 0.2)
    end)
    tabButton.MouseLeave:Connect(function()
        if self.SelectedTab ~= tab then
            Utility.Tween(tabButton, {BackgroundTransparency = 0.5}, 0.2)
        end
    end)
    
    table.insert(self.Tabs, tab)
    
    local layout = self.TabList:FindFirstChildOfClass("UIListLayout")
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        self.TabList.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end)
    
    if #self.Tabs == 1 then self:SelectTab(tab) end
    
    local window = self
    function tab:AddSection(opts) return window:CreateSection(tabPage, opts) end
    function tab:AddButton(opts) return window:CreateButton(tabPage, opts) end
    function tab:AddToggle(opts) return window:CreateToggle(tabPage, opts) end
    function tab:AddDangerToggle(opts) return window:CreateDangerToggle(tabPage, opts) end
    function tab:AddSlider(opts) return window:CreateSlider(tabPage, opts) end
    function tab:AddDropdown(opts) return window:CreateDropdown(tabPage, opts) end
    function tab:AddTextbox(opts) return window:CreateTextbox(tabPage, opts) end
    function tab:AddCommandBar(opts) return window:CreateCommandBar(tabPage, opts) end
    function tab:AddColorPicker(opts) return window:CreateColorPicker(tabPage, opts) end
    function tab:AddKeybind(opts) return window:CreateKeybind(tabPage, opts) end
    function tab:AddKeyAuth(opts) return window:CreateKeyAuth(tabPage, opts) end
    function tab:AddLabel(opts) return window:CreateLabel(tabPage, opts) end
    function tab:AddParagraph(opts) return window:CreateParagraph(tabPage, opts) end
    
    return tab
end

function QuantumUI:SelectTab(tab)
    for _, t in ipairs(self.Tabs) do
        t.Page.Visible = false
        t.Indicator.Visible = false
        Utility.Tween(t.Button, {BackgroundTransparency = 0.5}, 0.2)
        Utility.Tween(t.Icon, {ImageColor3 = Color3.fromRGB(200, 200, 200)}, 0.2)
        if t.TextLabel then
            Utility.Tween(t.TextLabel, {TextColor3 = Color3.fromRGB(200, 200, 200)}, 0.2)
        end
    end
    tab.Page.Visible = true
    tab.Indicator.Visible = true
    self.SelectedTab = tab
    Utility.Tween(tab.Button, {BackgroundTransparency = 0.2}, 0.2)
    Utility.Tween(tab.Icon, {ImageColor3 = self.ThemeColor}, 0.2)
    if tab.TextLabel then
        Utility.Tween(tab.TextLabel, {TextColor3 = Color3.fromRGB(255, 255, 255)}, 0.2)
    end
end

-- ═══════════════════════════════════════════════════════════════════
--                          UI ELEMENTS
-- ═══════════════════════════════════════════════════════════════════

function QuantumUI:CreateSection(parent, options)
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(25, 25, 40),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 35),
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = options.Name or "Section",
        TextColor3 = self.ThemeColor,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    self:UpdateContentSize(parent)
    return frame
end

function QuantumUI:CreateButton(parent, options)
    options = options or {}
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 45),
        ZIndex = 7
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
        Utility.Create("UIStroke", {Color = self.ThemeColor, Thickness = 1, Transparency = 0.7})
    })
    
    local btn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Button",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        ZIndex = 8
    })
    
    btn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        Utility.Ripple(frame, Vector2.new(Mouse.X, Mouse.Y), self.ThemeColor)
        if options.Callback then options.Callback() end
    end)
    
    btn.MouseEnter:Connect(function()
        Utility.PlaySound(Sounds.Hover, 0.1)
        Utility.Tween(frame:FindFirstChildOfClass("UIStroke"), {Transparency = 0.3}, 0.2)
    end)
    btn.MouseLeave:Connect(function()
        Utility.Tween(frame:FindFirstChildOfClass("UIStroke"), {Transparency = 0.7}, 0.2)
    end)
    
    self:UpdateContentSize(parent)
    return {Frame = frame, SetText = function(_, t) btn.Text = t end}
end

function QuantumUI:CreateToggle(parent, options)
    options = options or {}
    local flag = options.Flag
    local toggled = options.Default or false
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 45),
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 15, 0, 0),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Toggle",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    local toggleBg = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(50, 50, 65),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 50, 0, 26),
        Position = UDim2.new(1, -60, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        ZIndex = 8
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    self:AddThemeElement(toggleBg, "BackgroundColor3")
    
    local toggleIndicator = Utility.Create("Frame", {
        Parent = toggleBg,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 20, 0, 20),
        Position = UDim2.new(0, 3, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        ZIndex = 9
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    
    local function update(state, skip, noAnimate)
        toggled = state
        local targetPos = toggled and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        local targetColor = toggled and self.ThemeColor or Color3.fromRGB(50, 50, 65)

        if toggleBg and toggleBg.Parent then toggleBg.BackgroundColor3 = targetColor end
        if toggleIndicator and toggleIndicator.Parent then toggleIndicator.Position = targetPos end

        if not noAnimate then
            if toggleIndicator and toggleIndicator.Parent then
                Utility.Tween(toggleIndicator, {Size = UDim2.new(0, 26, 0, 26)}, 0.08)
                task.delay(0.08, function()
                    if toggleIndicator and toggleIndicator.Parent then
                        Utility.Tween(toggleIndicator, {Size = UDim2.new(0, 20, 0, 20)}, 0.12)
                    end
                end)
            end
            task.defer(function()
                if toggleBg and toggleBg.Parent then
                    Utility.Tween(toggleBg, {BackgroundColor3 = targetColor}, 0.2)
                end
                if toggleIndicator and toggleIndicator.Parent then
                    Utility.Tween(toggleIndicator, {Position = targetPos}, 0.2)
                end
            end)
        end

        if flag then self.ConfigData[flag] = toggled end
        if not skip and options.Callback then options.Callback(toggled) end
    end
    
    local btn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 10
    })
    
    btn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Toggle, 0.3)
        update(not toggled)
    end)
    
    local obj = {
        Frame = frame,
        Value = toggled,
        ToggleBg = toggleBg,
        ToggleIndicator = toggleIndicator,
        Set = function(selfObj, s)
            toggled = s and true or false
            Utility.PlaySound(Sounds.Toggle, 0.3)
            update(toggled, true, false)
            selfObj.Value = toggled
            if options.Callback then options.Callback(toggled) end
        end,
        Get = function() return toggled end
    }
    
    update(toggled, true, true)
    self:UpdateContentSize(parent)
    
    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

-- DangerToggle: 当用户尝试把开关置为 true 时先弹 DangerConfirm 二次确认 (关闭时直接)
-- options = { Name, Default, Flag, ConfirmTitle?, ConfirmContent?, ConfirmText?, CancelText?, Callback }
function QuantumUI:CreateDangerToggle(parent, options)
    options = options or {}
    local flag = options.Flag
    local toggled = options.Default or false
    local win = self

    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(45, 25, 30),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 45),
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})

    -- 危险标识
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 20, 0, 20),
        Position = UDim2.new(0, 12, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Font = Enum.Font.GothamBold,
        Text = "⚠",
        TextColor3 = Color3.fromRGB(255, 120, 120),
        TextSize = 18,
        ZIndex = 8,
    })

    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -100, 1, 0),
        Position = UDim2.new(0, 38, 0, 0),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Danger Toggle",
        TextColor3 = Color3.fromRGB(255, 220, 220),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })

    local toggleBg = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(80, 40, 45),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 50, 0, 26),
        Position = UDim2.new(1, -60, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        ZIndex = 8
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    self:AddThemeElement(toggleBg, "BackgroundColor3")

    local toggleIndicator = Utility.Create("Frame", {
        Parent = toggleBg,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 20, 0, 20),
        Position = UDim2.new(0, 3, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        ZIndex = 9
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})

    local DANGER_COLOR = Color3.fromRGB(255, 80, 90)

    local function update(state, skip, noAnimate)
        toggled = state
        local targetPos = toggled and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        local targetColor = toggled and DANGER_COLOR or Color3.fromRGB(80, 40, 45)

        if toggleBg and toggleBg.Parent then toggleBg.BackgroundColor3 = targetColor end
        if toggleIndicator and toggleIndicator.Parent then toggleIndicator.Position = targetPos end

        if not noAnimate then
            if toggleIndicator and toggleIndicator.Parent then
                Utility.Tween(toggleIndicator, {Size = UDim2.new(0, 26, 0, 26)}, 0.08)
                task.delay(0.08, function()
                    if toggleIndicator and toggleIndicator.Parent then
                        Utility.Tween(toggleIndicator, {Size = UDim2.new(0, 20, 0, 20)}, 0.12)
                    end
                end)
            end
            task.defer(function()
                if toggleBg and toggleBg.Parent then
                    Utility.Tween(toggleBg, {BackgroundColor3 = targetColor}, 0.2)
                end
                if toggleIndicator and toggleIndicator.Parent then
                    Utility.Tween(toggleIndicator, {Position = targetPos}, 0.2)
                end
            end)
        end

        if flag then self.ConfigData[flag] = toggled end
        if not skip and options.Callback then options.Callback(toggled) end
    end

    local btn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 10
    })

    btn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Toggle, 0.3)
        if toggled then
            -- 关: 直接执行 (从危险状态退出)
            update(false)
        else
            -- 开: 先弹二次确认
            win:DangerConfirm({
                Title = options.ConfirmTitle or ("启用: " .. tostring(options.Name or "Danger Toggle")),
                Content = options.ConfirmContent or "该功能被开发者标记为危险操作，启用后可能导致账号被检测或其他不可逆后果！\n\n确定要继续吗？",
                ConfirmText = options.ConfirmText or "我已知风险，确定启用",
                CancelText  = options.CancelText  or "取消",
                OnConfirm = function()
                    update(true)
                end,
                OnCancel = function()
                    -- 保持状态不变, 播放失败音效
                    Utility.PlaySound(Sounds.Error, 0.2)
                end,
            })
        end
    end)

    local obj = {
        Frame = frame,
        Value = toggled,
        ToggleBg = toggleBg,
        ToggleIndicator = toggleIndicator,
        Set = function(selfObj, s, skipConfirm)
            local newState = s and true or false
            if newState and not skipConfirm and not toggled then
                -- 从外部置为 true 时也走确认流程
                win:DangerConfirm({
                    Title = options.ConfirmTitle or ("启用: " .. tostring(options.Name or "Danger Toggle")),
                    Content = options.ConfirmContent or "该功能被开发者标记为危险操作，启用后可能导致账号被检测或其他不可逆后果！\n\n确定要继续吗？",
                    ConfirmText = options.ConfirmText or "我已知风险，确定启用",
                    CancelText  = options.CancelText  or "取消",
                    OnConfirm = function()
                        toggled = true
                        Utility.PlaySound(Sounds.Toggle, 0.3)
                        update(toggled, true, false)
                        selfObj.Value = toggled
                        if options.Callback then options.Callback(toggled) end
                    end,
                })
            else
                toggled = newState
                Utility.PlaySound(Sounds.Toggle, 0.3)
                update(toggled, true, false)
                selfObj.Value = toggled
                if options.Callback then options.Callback(toggled) end
            end
        end,
        Get = function() return toggled end
    }

    update(toggled, true, true)
    self:UpdateContentSize(parent)

    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

function QuantumUI:CreateSlider(parent, options)
    options = options or {}
    local flag = options.Flag
    local min, max = options.Min or 0, options.Max or 100
    local value = options.Default or min
    local increment = options.Increment or 1
    local suffix = options.Suffix or ""
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 55),
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.6, 0, 0, 25),
        Position = UDim2.new(0, 15, 0, 5),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Slider",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    local valueLabel = Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.3, 0, 0, 25),
        Position = UDim2.new(0.7, -15, 0, 5),
        Font = Enum.Font.GothamSemibold,
        Text = tostring(value) .. suffix,
        TextColor3 = self.ThemeColor,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 8
    })
    self:AddThemeElement(valueLabel, "TextColor3")
    
    local sliderBg = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(50, 50, 65),
        BorderSizePixel = 0,
        Size = UDim2.new(1, -30, 0, 8),
        Position = UDim2.new(0, 15, 0, 35),
        ZIndex = 8
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    
    local sliderFill = Utility.Create("Frame", {
        Parent = sliderBg,
        BackgroundColor3 = self.ThemeColor,
        BorderSizePixel = 0,
        Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
        ZIndex = 9
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
    self:AddThemeElement(sliderFill, "BackgroundColor3")
    
    local sliderKnob = Utility.Create("Frame", {
        Parent = sliderBg,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new((value - min) / (max - min), -8, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        ZIndex = 10
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)}),
        Utility.Create("UIStroke", {Color = self.ThemeColor, Thickness = 2, Name = "KnobStroke"})
    })
    self:AddThemeElement(sliderKnob:FindFirstChild("KnobStroke"), "Color")
    
    local function update(newVal, skip)
        value = math.clamp(newVal, min, max)
        value = math.floor(value / increment + 0.5) * increment
        local pct = (value - min) / (max - min)
        local fillSize = UDim2.new(pct, 0, 1, 0)
        local knobPos = UDim2.new(pct, -8, 0.5, 0)
        local labelText = tostring(value) .. suffix
        sliderFill.Size = fillSize
        sliderKnob.Position = knobPos
        valueLabel.Text = labelText
        task.defer(function()
            if sliderFill and sliderFill.Parent then
                Utility.Tween(sliderFill, {Size = fillSize}, 0.1)
            end
            if sliderKnob and sliderKnob.Parent then
                Utility.Tween(sliderKnob, {Position = knobPos}, 0.1)
            end
        end)
        if flag then self.ConfigData[flag] = value end
        -- obj.SetValue 是对 update 的外部引用，保证设置后 obj.Value 同步
        if obj then obj.Value = value end
        if not skip and options.Callback then options.Callback(value) end
    end

    local dragging = false
    sliderBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local pct = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            update(min + (max - min) * pct)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local pct = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
            update(min + (max - min) * pct)
        end
    end)
    
    -- ⚠️ obj 必须在 update 之前创建，update 内部才会正确同步 obj.Value
    local obj = {
        Frame = frame,
        Value = value,
        SliderFill = sliderFill,
        SliderKnob = sliderKnob,
        ValueLabel = valueLabel,
        Min = min, Max = max, Increment = increment, Suffix = suffix,
        Set = function(selfObj, v)
            v = math.clamp(v, min, max)
            v = math.floor(v / increment + 0.5) * increment
            local pct = (v - min) / (max - min)
            local fillSize = UDim2.new(pct, 0, 1, 0)
            local knobPos = UDim2.new(pct, -8, 0.5, 0)
            -- 直接设置 + 动画（保证视觉改变且平滑）
            if sliderFill and sliderFill.Parent then sliderFill.Size = fillSize end
            if sliderKnob and sliderKnob.Parent then sliderKnob.Position = knobPos end
            if valueLabel and valueLabel.Parent then valueLabel.Text = tostring(v) .. suffix end
            task.defer(function()
                if sliderFill and sliderFill.Parent then
                    Utility.Tween(sliderFill, {Size = fillSize}, 0.2)
                end
                if sliderKnob and sliderKnob.Parent then
                    Utility.Tween(sliderKnob, {Position = knobPos}, 0.2)
                end
            end)
            -- 同步到所有变量
            value = v
            selfObj.Value = v
            if flag then self.ConfigData[flag] = v end
            if options.Callback then options.Callback(v) end
        end,
        Get = function() return value end
    }

    update(value, true)
    self:UpdateContentSize(parent)
    
    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

function QuantumUI:CreateDropdown(parent, options)
    options = options or {}
    local flag = options.Flag
    local items = options.Items or {}
    local multi = options.Multi or false
    local selected = multi and {} or (options.Default or items[1])
    local isOpen = false
    
    if multi and options.Default then
        for _, item in ipairs(type(options.Default) == "table" and options.Default or {options.Default}) do
            selected[item] = true
        end
    end
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 45),
        ClipsDescendants = true,
        ZIndex = 20
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.5, 0, 0, 45),
        Position = UDim2.new(0, 15, 0, 0),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Dropdown",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21
    })
    
    local selectedLabel = Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.4, -30, 0, 45),
        Position = UDim2.new(0.5, 0, 0, 0),
        Font = Enum.Font.Gotham,
        Text = "",
        TextColor3 = self.ThemeColor,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 21
    })
    
    local arrow = Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 20, 0, 45),
        Position = UDim2.new(1, -25, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = "▼",
        TextColor3 = self.ThemeColor,
        TextSize = 12,
        ZIndex = 21
    })
    
    local itemContainer = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(25, 25, 40),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 0),
        Position = UDim2.new(0, 10, 0, 50),
        ClipsDescendants = true,
        ZIndex = 21
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
        Utility.Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2)}),
        Utility.Create("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5)})
    })
    
    local function updateLabel()
        if multi then
            local list = {}
            for item, v in pairs(selected) do if v then table.insert(list, item) end end
            selectedLabel.Text = #list > 0 and table.concat(list, ", ") or "Select..."
        else
            selectedLabel.Text = selected or "Select..."
        end
    end
    
    local function createItem(itemName)
        local itemBtn = Utility.Create("TextButton", {
            Name = itemName,
            Parent = itemContainer,
            BackgroundColor3 = Color3.fromRGB(40, 40, 55),
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 30),
            Font = Enum.Font.Gotham,
            Text = multi and ("  " .. itemName) or itemName,
            TextColor3 = Color3.fromRGB(200, 200, 200),
            TextSize = 12,
            TextXAlignment = multi and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center,
            ZIndex = 22
        }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 4)})})
        
        local check
        if multi then
            check = Utility.Create("TextLabel", {
                Parent = itemBtn,
                BackgroundTransparency = 1,
                Size = UDim2.new(0, 20, 1, 0),
                Position = UDim2.new(1, -25, 0, 0),
                Font = Enum.Font.GothamBold,
                Text = selected[itemName] and "✓" or "",
                TextColor3 = self.ThemeColor,
                TextSize = 14,
                ZIndex = 23
            })
        end
        
        itemBtn.MouseButton1Click:Connect(function()
            Utility.PlaySound(Sounds.Click, 0.2)
            if multi then
                selected[itemName] = not selected[itemName]
                check.Text = selected[itemName] and "✓" or ""
                updateLabel()
                if options.Callback then options.Callback(selected) end
                if flag then self.ConfigData[flag] = {_data = selected, _type = "table"} end
            else
                selected = itemName
                updateLabel()
                isOpen = false
                Utility.Tween(frame, {Size = UDim2.new(1, 0, 0, 45)}, 0.3)
                Utility.Tween(arrow, {Rotation = 0}, 0.3)
                if options.Callback then options.Callback(selected) end
                if flag then self.ConfigData[flag] = selected end
            end
        end)
        
        itemBtn.MouseEnter:Connect(function() Utility.Tween(itemBtn, {BackgroundTransparency = 0.3}, 0.2) end)
        itemBtn.MouseLeave:Connect(function() Utility.Tween(itemBtn, {BackgroundTransparency = 0.5}, 0.2) end)
    end
    
    for _, item in ipairs(items) do createItem(item) end
    
    local toggle = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 45),
        Text = "",
        ZIndex = 25
    })
    
    toggle.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        isOpen = not isOpen
        if isOpen then
            local h = math.min(#items * 32 + 15, 200)
            Utility.Tween(frame, {Size = UDim2.new(1, 0, 0, 50 + h)}, 0.3)
            Utility.Tween(itemContainer, {Size = UDim2.new(1, -20, 0, h)}, 0.3)
            Utility.Tween(arrow, {Rotation = 180}, 0.3)
        else
            Utility.Tween(frame, {Size = UDim2.new(1, 0, 0, 45)}, 0.3)
            Utility.Tween(itemContainer, {Size = UDim2.new(1, -20, 0, 0)}, 0.3)
            Utility.Tween(arrow, {Rotation = 0}, 0.3)
        end
        self:UpdateContentSize(parent, 0.3)
    end)
    
    updateLabel()
    self:UpdateContentSize(parent)
    
    local obj = {
        Frame = frame,
        Value = selected,
        Set = function(_, v)
            if multi then
                selected = {}
                if type(v) == "table" then
                    -- 兼容两种格式：字典 {item=true} 或列表 {item1, item2}
                    for key, val in pairs(v) do
                        if type(key) == "string" and val == true then
                            selected[key] = true
                        elseif type(val) == "string" then
                            selected[val] = true
                        end
                    end
                else
                    selected[v] = true
                end
            else
                selected = v
            end
            updateLabel()
            if options.Callback then options.Callback(selected) end
        end,
        Get = function() return selected end,
        Refresh = function(_, newItems)
            items = newItems
            for _, c in ipairs(itemContainer:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            for _, item in ipairs(items) do createItem(item) end
        end
    }
    
    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

function QuantumUI:CreateTextbox(parent, options)
    options = options or {}
    local flag = options.Flag
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 45),
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.4, 0, 1, 0),
        Position = UDim2.new(0, 15, 0, 0),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Textbox",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    local container = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BorderSizePixel = 0,
        Size = UDim2.new(0.55, -20, 0, 30),
        Position = UDim2.new(0.45, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        ZIndex = 8
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
        Utility.Create("UIStroke", {Color = self.ThemeColor, Thickness = 1, Transparency = 0.7})
    })
    
    local textbox = Utility.Create("TextBox", {
        Parent = container,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        Font = Enum.Font.Gotham,
        Text = options.Default or "",
        PlaceholderText = options.Placeholder or "Enter text...",
        PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = options.ClearOnFocus or false,
        ZIndex = 9
    })
    
    textbox.Focused:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.2)
        Utility.Tween(container:FindFirstChildOfClass("UIStroke"), {Transparency = 0.3}, 0.2)
    end)
    
    textbox.FocusLost:Connect(function(enter)
        Utility.Tween(container:FindFirstChildOfClass("UIStroke"), {Transparency = 0.7}, 0.2)
        if flag then self.ConfigData[flag] = textbox.Text end
        if options.Callback then options.Callback(textbox.Text, enter) end
    end)
    
    self:UpdateContentSize(parent)
    
    local obj = {
        Frame = frame,
        Value = textbox.Text,
        Set = function(_, t) textbox.Text = t; if flag then self.ConfigData[flag] = t end end,
        Get = function() return textbox.Text end
    }
    
    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

function QuantumUI:CreateCommandBar(parent, options)
    options = options or {}
    local flag = options.Flag
    local currentMode = (options.DefaultMode == "loop") and "loop" or "single"
    local running = false

    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 204),
        ZIndex = 7
    }, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8) }) })

    -- 标题
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 0, 20),
        Position = UDim2.new(0, 15, 0, 5),
        Font = Enum.Font.GothamBold,
        Text = options.Name or "命令栏 (Command Bar)",
        TextColor3 = self.ThemeColor,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })

    -- 代码输入区（多行可滚动）
    local codeContainer = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 90),
        Position = UDim2.new(0, 10, 0, 30),
        ZIndex = 8
    }, {
        Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        Utility.Create("UIStroke", { Color = self.ThemeColor, Thickness = 1, Transparency = 0.7 })
    })

    local codeScroll = Utility.Create("ScrollingFrame", {
        Parent = codeContainer,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -12, 1, -4),
        Position = UDim2.new(0, 6, 0, 2),
        CanvasSize = UDim2.new(0, 0, 0, 28),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = self.ThemeColor,
        ZIndex = 9
    })
    self:AddThemeElement(codeScroll, "ScrollBarImageColor3")

    local codeBox = Utility.Create("TextBox", {
        Parent = codeScroll,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -16, 0, 28),
        Position = UDim2.new(0, 8, 0, 0),
        Font = Enum.Font.Code,
        Text = options.Default or "",
        PlaceholderText = options.Placeholder or "在此粘贴要运行的 Lua 代码...",
        PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ClearTextOnFocus = false,
        MultiLine = true,
        TextWrapped = true,
        ZIndex = 9
    })

    local function refreshCodeScroll()
        local h = math.max(28, codeBox.TextBounds.Y + 8)
        codeBox.Size = UDim2.new(1, -16, 0, h)
        codeScroll.CanvasSize = UDim2.new(0, 0, 0, h + 4)
    end
    codeBox:GetPropertyChangedSignal("TextBounds"):Connect(refreshCodeScroll)
    codeBox:GetPropertyChangedSignal("Text"):Connect(function() task.defer(refreshCodeScroll) end)
    task.defer(refreshCodeScroll)

    codeBox.Focused:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.2)
        Utility.Tween(codeContainer:FindFirstChildOfClass("UIStroke"), { Transparency = 0.3 }, 0.2)
    end)
    codeBox.FocusLost:Connect(function(enter)
        Utility.Tween(codeContainer:FindFirstChildOfClass("UIStroke"), { Transparency = 0.7 }, 0.2)
        if flag then self.ConfigData[flag] = codeBox.Text end
    end)

    -- 运行模式选择：单次 / 循环
    local singleBtn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(0.5, -15, 0, 30),
        Position = UDim2.new(0, 10, 0, 128),
        Font = Enum.Font.GothamSemibold,
        Text = "单次运行",
        TextColor3 = Color3.fromRGB(220, 220, 220),
        TextSize = 13,
        ZIndex = 9
    }, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })

    local loopBtn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(0.5, -15, 0, 30),
        Position = UDim2.new(0.5, 5, 0, 128),
        Font = Enum.Font.GothamSemibold,
        Text = "循环运行",
        TextColor3 = Color3.fromRGB(220, 220, 220),
        TextSize = 13,
        ZIndex = 9
    }, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })

    local function refreshModeButtons()
        if currentMode == "single" then
            singleBtn.BackgroundColor3 = self.ThemeColor
            singleBtn.TextColor3 = Color3.fromRGB(20, 20, 30)
            loopBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
            loopBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
        else
            loopBtn.BackgroundColor3 = self.ThemeColor
            loopBtn.TextColor3 = Color3.fromRGB(20, 20, 30)
            singleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
            singleBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
        end
    end

    singleBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        currentMode = "single"
        refreshModeButtons()
    end)
    loopBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        currentMode = "loop"
        refreshModeButtons()
    end)

    -- 运行 / 停止 按钮
    local runBtn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(0.5, -15, 0, 34),
        Position = UDim2.new(0, 10, 0, 164),
        Font = Enum.Font.GothamBold,
        Text = "运行",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        ZIndex = 9
    }, {
        Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        Utility.Create("UIStroke", { Color = self.ThemeColor, Thickness = 1, Transparency = 0.6 })
    })

    local stopBtn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(0.5, -15, 0, 34),
        Position = UDim2.new(0.5, 5, 0, 164),
        Font = Enum.Font.GothamBold,
        Text = "停止",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        ZIndex = 9
    }, {
        Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
        Utility.Create("UIStroke", { Color = Color3.fromRGB(255, 90, 90), Thickness = 1, Transparency = 0.6 })
    })

    -- 执行逻辑
    local function stop()
        running = false
    end

    local function execOnce(code)
        if not code or code:match("^%s*$") then
            return false, "代码为空"
        end
        local fn, compileErr = loadstring(code)
        if not fn then
            return false, "语法错误: " .. tostring(compileErr)
        end
        return pcall(fn)
    end

    local function run()
        local code = codeBox.Text
        if currentMode == "single" then
            task.spawn(function()
                local ok, e = execOnce(code)
                if options.Callback then options.Callback(ok, e, code) end
            end)
            return
        end

        -- 循环模式
        if running then return end
        local fn, compileErr = loadstring(code)
        if not fn then
            local msg
            if not code or code:match("^%s*$") then
                msg = "代码为空"
            else
                msg = "语法错误: " .. tostring(compileErr)
            end
            warn("[CommandBar] " .. msg)
            if options.Callback then options.Callback(false, msg, code) end
            return
        end
        running = true
        task.spawn(function()
            while running do
                local ok, e = pcall(fn)
                if not ok then
                    warn("[CommandBar] 循环运行错误: " .. tostring(e))
                    if options.Callback then options.Callback(false, tostring(e), code) end
                end
                task.wait(options.Interval or 0.1)
            end
        end)
    end

    runBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        run()
    end)
    stopBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        stop()
    end)

    pcall(function() frame.Destroying:Connect(function() running = false end) end)

    refreshModeButtons()
    self:UpdateContentSize(parent)

    local obj = {
        Frame = frame,
        Value = codeBox.Text,
        GetCode = function() return codeBox.Text end,
        SetCode = function(v) codeBox.Text = v or ""; task.defer(refreshCodeScroll) end,
        GetMode = function() return currentMode end,
        SetMode = function(m) currentMode = (m == "loop") and "loop" or "single"; refreshModeButtons() end,
        Run = run,
        Stop = stop,
        IsRunning = function() return running end,
        Set = function(_, v)
            codeBox.Text = v or ""
            if flag then self.ConfigData[flag] = codeBox.Text end
            task.defer(refreshCodeScroll)
        end,
        Get = function() return codeBox.Text end
    }

    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

function QuantumUI:CreateColorPicker(parent, options)
    options = options or {}
    local flag = options.Flag
    local currentColor = options.Default or Color3.fromRGB(255, 255, 255)
    local isOpen = false
    local h, s, v = Utility.RGBToHSV(currentColor)
    local presets = options.Presets or {
        Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 127, 0), Color3.fromRGB(255, 255, 0),
        Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 255, 255), Color3.fromRGB(0, 0, 255),
        Color3.fromRGB(127, 0, 255), Color3.fromRGB(255, 0, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 0, 0)
    }
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 45),
        ClipsDescendants = true,
        ZIndex = 15
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.6, 0, 0, 45),
        Position = UDim2.new(0, 15, 0, 0),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Color Picker",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 16
    })
    
    local preview = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = currentColor,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 35, 0, 25),
        Position = UDim2.new(1, -50, 0, 10),
        ZIndex = 16
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
        Utility.Create("UIStroke", {Color = Color3.fromRGB(255, 255, 255), Thickness = 1, Transparency = 0.5})
    })
    
    local pickerContainer = Utility.Create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(25, 25, 40),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 0),
        Position = UDim2.new(0, 10, 0, 50),
        ClipsDescendants = true,
        ZIndex = 16
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    local wheelSize = IsMobile and 140 or 170
    
    local wheelContainer = Utility.Create("Frame", {
        Parent = pickerContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, wheelSize, 0, wheelSize),
        Position = UDim2.new(0, 15, 0, 15),
        ZIndex = 17
    })
    
    local colorWheel = Utility.Create("ImageLabel", {
        Parent = wheelContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Image = "rbxassetid://6020299385",
        ZIndex = 18
    })
    
    local valueOverlay = Utility.Create("ImageLabel", {
        Parent = wheelContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Image = "rbxassetid://6020299385",
        ImageColor3 = Color3.fromRGB(0, 0, 0),
        ImageTransparency = v,
        ZIndex = 19
    })
    
    local wheelCursor = Utility.Create("Frame", {
        Parent = wheelContainer,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 14, 0, 14),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ZIndex = 20
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(1, 0)}),
        Utility.Create("UIStroke", {Color = Color3.fromRGB(0, 0, 0), Thickness = 2})
    })
    
    local valueSlider = Utility.Create("Frame", {
        Parent = pickerContainer,
        BackgroundColor3 = Color3.fromRGB(50, 50, 65),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 18, 0, wheelSize),
        Position = UDim2.new(0, wheelSize + 25, 0, 15),
        ZIndex = 17
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
        Utility.Create("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
            }),
            Rotation = 90
        })
    })
    
    local valueKnob = Utility.Create("Frame", {
        Parent = valueSlider,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Size = UDim2.new(1, 4, 0, 8),
        Position = UDim2.new(0, -2, 1 - v, -4),
        ZIndex = 18
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 3)}),
        Utility.Create("UIStroke", {Color = Color3.fromRGB(0, 0, 0), Thickness = 1})
    })
    
    local hexContainer = Utility.Create("Frame", {
        Parent = pickerContainer,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 90, 0, 28),
        Position = UDim2.new(0, 15, 0, wheelSize + 25),
        ZIndex = 17
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)})})
    
    Utility.Create("TextLabel", {
        Parent = hexContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 20, 1, 0),
        Font = Enum.Font.GothamBold,
        Text = "#",
        TextColor3 = self.ThemeColor,
        TextSize = 14,
        ZIndex = 18
    })
    
    local hexInput = Utility.Create("TextBox", {
        Parent = hexContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -25, 1, 0),
        Position = UDim2.new(0, 20, 0, 0),
        Font = Enum.Font.Code,
        Text = string.format("%02X%02X%02X", currentColor.R * 255, currentColor.G * 255, currentColor.B * 255),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 11,
        ZIndex = 18
    })
    
    local presetContainer = Utility.Create("Frame", {
        Parent = pickerContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 0, 30),
        Position = UDim2.new(0, 15, 0, wheelSize + 60),
        ZIndex = 17
    }, {Utility.Create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5)})})
    
    local function updateColor(newColor, skip)
        currentColor = newColor
        h, s, v = Utility.RGBToHSV(newColor)
        preview.BackgroundColor3 = newColor
        valueOverlay.ImageTransparency = v
        local angle = h * math.pi * 2
        local radius = s * (wheelSize / 2 - 8)
        wheelCursor.Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, -math.sin(angle) * radius)
        valueKnob.Position = UDim2.new(0, -2, 1 - v, -4)
        hexInput.Text = string.format("%02X%02X%02X", newColor.R * 255, newColor.G * 255, newColor.B * 255)
        if flag then self.ConfigData[flag] = {R = newColor.R, G = newColor.G, B = newColor.B, _type = "Color3"} end
        if not skip and options.Callback then options.Callback(newColor) end
    end
    
    for _, preset in ipairs(presets) do
        local presetBtn = Utility.Create("TextButton", {
            Parent = presetContainer,
            BackgroundColor3 = preset,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 22, 0, 22),
            Text = "",
            ZIndex = 18
        }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 4)})})
        
        presetBtn.MouseButton1Click:Connect(function()
            Utility.PlaySound(Sounds.Click, 0.2)
            updateColor(preset)
        end)
    end
    
    local wheelDragging, valueDragging = false, false
    
    colorWheel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            wheelDragging = true
        end
    end)
    colorWheel.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            wheelDragging = false
        end
    end)
    
    valueSlider.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            valueDragging = true
            local pct = math.clamp((input.Position.Y - valueSlider.AbsolutePosition.Y) / valueSlider.AbsoluteSize.Y, 0, 1)
            v = 1 - pct
            updateColor(Utility.HSVToRGB(h, s, v))
        end
    end)
    valueSlider.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            valueDragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if wheelDragging then
                local centerX = wheelContainer.AbsolutePosition.X + wheelSize / 2
                local centerY = wheelContainer.AbsolutePosition.Y + wheelSize / 2
                local dx = input.Position.X - centerX
                local dy = input.Position.Y - centerY
                local dist = math.sqrt(dx * dx + dy * dy)
                local maxR = wheelSize / 2 - 5
                if dist <= maxR then
                    local angle = math.atan2(-dy, dx)
                    if angle < 0 then angle = angle + math.pi * 2 end
                    h = angle / (math.pi * 2)
                    s = math.min(dist / maxR, 1)
                    updateColor(Utility.HSVToRGB(h, s, v))
                end
            end
            if valueDragging then
                local pct = math.clamp((input.Position.Y - valueSlider.AbsolutePosition.Y) / valueSlider.AbsoluteSize.Y, 0, 1)
                v = 1 - pct
                updateColor(Utility.HSVToRGB(h, s, v))
            end
        end
    end)
    
    hexInput.FocusLost:Connect(function()
        local hex = hexInput.Text:gsub("#", "")
        local success, r, g, b = pcall(function()
            return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
        end)
        if success and r and g and b then updateColor(Color3.fromRGB(r, g, b)) end
    end)
    
    local toggle = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 45),
        Text = "",
        ZIndex = 20
    })
    
    toggle.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        isOpen = not isOpen
        if isOpen then
            local height = wheelSize + 105
            Utility.Tween(frame, {Size = UDim2.new(1, 0, 0, 50 + height)}, 0.3)
            Utility.Tween(pickerContainer, {Size = UDim2.new(1, -20, 0, height)}, 0.3)
        else
            Utility.Tween(frame, {Size = UDim2.new(1, 0, 0, 45)}, 0.3)
            Utility.Tween(pickerContainer, {Size = UDim2.new(1, -20, 0, 0)}, 0.3)
        end
        self:UpdateContentSize(parent, 0.3)
    end)
    
    updateColor(currentColor, true)
    self:UpdateContentSize(parent)
    
    local obj = {
        Frame = frame,
        Value = currentColor,
        Set = function(_, c)
            if type(c) == "table" then
                -- 兼容 0-255 整数和 0-1 浮点
                local r = c.R > 1 and c.R / 255 or c.R
                local g = c.G > 1 and c.G / 255 or c.G
                local b = c.B > 1 and c.B / 255 or c.B
                c = Color3.new(r, g, b)
            end
            updateColor(c)
        end,
        Get = function() return currentColor end
    }
    
    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

function QuantumUI:CreateKeybind(parent, options)
    options = options or {}
    local flag = options.Flag
    local currentKey = options.Default or Enum.KeyCode.Unknown
    local listening = false
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 45),
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0.6, 0, 1, 0),
        Position = UDim2.new(0, 15, 0, 0),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or "Keybind",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    local keyBtn = Utility.Create("TextButton", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(40, 40, 55),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 80, 0, 28),
        Position = UDim2.new(1, -95, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Font = Enum.Font.GothamSemibold,
        Text = currentKey == Enum.KeyCode.Unknown and "None" or currentKey.Name,
        TextColor3 = self.ThemeColor,
        TextSize = 12,
        ZIndex = 8
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
        Utility.Create("UIStroke", {Color = self.ThemeColor, Thickness = 1, Transparency = 0.5})
    })
    
    keyBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        listening = true
        keyBtn.Text = "..."
        Utility.Tween(keyBtn, {BackgroundColor3 = self.ThemeColor}, 0.2)
    end)
    
    UserInputService.InputBegan:Connect(function(input, processed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                listening = false
                Utility.Tween(keyBtn, {BackgroundColor3 = Color3.fromRGB(40, 40, 55)}, 0.2)
                if input.KeyCode == Enum.KeyCode.Escape then
                    currentKey = Enum.KeyCode.Unknown
                    keyBtn.Text = "None"
                else
                    currentKey = input.KeyCode
                    keyBtn.Text = input.KeyCode.Name
                end
                if flag then self.ConfigData[flag] = {Name = currentKey.Name, _type = "KeyCode"} end
                if options.ChangedCallback then options.ChangedCallback(currentKey) end
            end
        elseif not processed and input.KeyCode == currentKey then
            if options.Callback then options.Callback(currentKey) end
        end
    end)
    
    self:UpdateContentSize(parent)
    
    local obj = {
        Frame = frame,
        Value = currentKey,
        Set = function(_, k)
            if type(k) == "string" then k = Enum.KeyCode[k] or Enum.KeyCode.Unknown end
            currentKey = k
            keyBtn.Text = k == Enum.KeyCode.Unknown and "None" or k.Name
            if flag then self.ConfigData[flag] = {Name = k.Name, _type = "KeyCode"} end
        end,
        Get = function() return currentKey end
    }
    
    if flag then self.Flags[flag] = obj; self.Elements[flag] = obj end
    return obj
end

-- ═══════════════════════════════════════════════════════════════════
--                    KEYAUTH UI ELEMENT + METHODS
-- ═══════════════════════════════════════════════════════════════════
function QuantumUI:CreateKeyAuth(parent, options)
    options = options or {}
    local titleText = options.Name or "Access Key"
    local placeholderText = options.Placeholder or "Enter key..."
    local showHWID = options.ShowHWID ~= false
    local onAuthorize = options.Callback
    local requireGate = not not options.RequireGate -- 若为 true，UI 创建时若未授权，禁用整个 Tab
    
    local container = Utility.Create("Frame", {
        Name = "KeyAuthContainer",
        Parent = parent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -10, 0, 120),
        Position = UDim2.new(0, 5, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 5
    })
    
    local title = Utility.Create("TextLabel", {
        Parent = container,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22),
        Position = UDim2.new(0, 0, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = titleText,
        TextColor3 = Color3.fromRGB(240, 240, 240),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    self:AddThemeElement(title, "TextColor3")
    
    local hwidBox
    if showHWID then
        hwidBox = Utility.Create("TextLabel", {
            Parent = container,
            BackgroundColor3 = Color3.fromRGB(20, 20, 32),
            BackgroundTransparency = 0.3,
            Size = UDim2.new(1, 0, 0, 24),
            Position = UDim2.new(0, 0, 0, 26),
            Font = Enum.Font.Code,
            Text = "HWID: " .. GetHWID(),
            TextColor3 = Color3.fromRGB(160, 160, 180),
            TextSize = 12,
            ClipsDescendants = true,
            ZIndex = 6
        }, {
            Utility.Create("UICorner", {CornerRadius = UDim.new(0, 4)})
        })
    end
    
    local rowY = showHWID and 56 or 26
    local inputFrame = Utility.Create("Frame", {
        Parent = container,
        BackgroundColor3 = Color3.fromRGB(22, 22, 35),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -95, 0, 32),
        Position = UDim2.new(0, 0, 0, rowY),
        ZIndex = 6
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
        Utility.Create("UIStroke", {Color = self.ThemeColor, Thickness = 1, Transparency = 0.7})
    })
    self:AddThemeElement(inputFrame.UIStroke, "Color")
    
    local textBox = Utility.Create("TextBox", {
        Parent = inputFrame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        Font = Enum.Font.Code,
        Text = "",
        TextColor3 = Color3.fromRGB(230, 230, 240),
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        PlaceholderText = placeholderText,
        PlaceholderColor3 = Color3.fromRGB(120, 120, 140),
        ClipsDescendants = true,
        ZIndex = 7
    })
    
    local activateBtn = Utility.Create("TextButton", {
        Parent = container,
        BackgroundColor3 = self.ThemeColor,
        BackgroundTransparency = 0.1,
        Size = UDim2.new(0, 85, 0, 32),
        Position = UDim2.new(1, -85, 0, rowY),
        Font = Enum.Font.GothamBold,
        Text = "Activate",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 12,
        ZIndex = 7
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
        Utility.Create("UIStroke", {Color = Color3.fromRGB(255,255,255), Thickness = 1, Transparency = 0.6})
    })
    self:AddThemeElement(activateBtn, "BackgroundColor3")
    
    local statusY = rowY + 38
    local statusLabel = Utility.Create("TextLabel", {
        Parent = container,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0, statusY),
        Font = Enum.Font.Gotham,
        Text = "",
        TextColor3 = Color3.fromRGB(200, 200, 220),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6
    })
    
    -- 初始检查：已保存的 key
    local currentKey, currentState = nil, "unauthorized"
    local saved = LoadAuthorizedKey()
    if saved and saved.Key then
        currentKey = saved.Key
        textBox.Text = saved.Key
    end
    
    local function setStatus(text, color, code)
        statusLabel.Text = text
        statusLabel.TextColor3 = color or Color3.fromRGB(200, 200, 220)
        currentState = code or currentState
    end
    
    if not KeyAuth.Enabled then
        setStatus("⚠ No KeyAuth configured (dev mode)", Color3.fromRGB(255, 200, 100), "dev_mode")
    elseif saved and saved.Key then
        local ok, reason, hwid = VerifyKey(saved.Key)
        if ok then
            setStatus("✓ Authorized (" .. reason .. ")", Color3.fromRGB(100, 255, 160), reason)
        else
            local msgMap = {
                empty = "Empty saved key",
                invalid_key = "✗ Key invalid or revoked",
                hwid_mismatch = "✗ HWID mismatch (key bound to another device)"
            }
            setStatus(msgMap[reason] or "Unauthorized", Color3.fromRGB(255, 120, 120), reason)
        end
    else
        setStatus("Enter key to activate", Color3.fromRGB(180, 180, 200), "unauthorized")
    end
    
    local function doActivate()
        Utility.PlaySound(Sounds.Click, 0.3)
        if not KeyAuth.Enabled then
            setStatus("⚠ KeyAuth disabled by developer", Color3.fromRGB(255, 200, 100), "dev_mode")
            return
        end
        local input = textBox.Text
        local ok, reason, hwid = VerifyKey(input)
        if ok then
            currentKey = input
            Utility.PlaySound(Sounds.SpecialLoad, 0.5)
            Utility.ScreenFlash(Color3.fromRGB(100, 255, 160), 0.3, 0.4)
            local msgMap = {
                authorized = "✓ Authorized",
                authorized_whitelist = "✓ Authorized (whitelisted)",
                bound = "✓ Key bound to your device",
                no_keyauth = "✓ Dev mode pass"
            }
            setStatus(msgMap[reason] or "✓ Authorized", Color3.fromRGB(100, 255, 160), reason)
            if KeyAuth.OnSuccess then task.spawn(KeyAuth.OnSuccess, input) end
            if onAuthorize then task.spawn(onAuthorize, ok, input, reason) end
        else
            currentKey = nil
            Utility.PlaySound(Sounds.Error, 0.5)
            local msgMap = {
                empty = "✗ Please enter a key",
                invalid_key = "✗ Invalid key",
                hwid_mismatch = "✗ HWID mismatch"
            }
            setStatus(msgMap[reason] or "Unauthorized", Color3.fromRGB(255, 120, 120), reason)
            if KeyAuth.OnFail then task.spawn(KeyAuth.OnFail, reason) end
        end
    end
    
    activateBtn.MouseButton1Click:Connect(doActivate)
    textBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then doActivate() end
    end)
    
    container.Size = UDim2.new(1, -10, 0, statusY + 22)
    self:UpdateContentSize(parent)
    
    local obj = {
        Frame = container,
        Value = currentKey,
        State = currentState,
        Activate = function(_) doActivate() end,
        IsAuthorized = function(_)
            if not KeyAuth.Enabled then return true end
            local k = textBox.Text
            if k == "" and saved then k = saved.Key end
            local ok = VerifyKey(k)
            return ok
        end,
        GetState = function() return currentState end,
        Reset = function()
            textBox.Text = ""
            pcall(function() if isfile(KeyAuthPath) then delfile(KeyAuthPath) end end)
            setStatus("Enter key to activate", Color3.fromRGB(180, 180, 200), "unauthorized")
        end,
        SetKey = function(_, k)
            textBox.Text = tostring(k or "")
            doActivate()
        end,
        GetHWID = function() return GetHWID() end
    }
    return obj
end

function QuantumUI:IsKeyAuthorized()
    if not KeyAuth.Enabled then return true, "dev_mode" end
    local saved = LoadAuthorizedKey()
    if saved and saved.Key then
        local ok, reason = VerifyKey(saved.Key)
        return ok, reason
    end
    return false, "no_key_saved"
end

function QuantumUI:ActivateKey(keyStr)
    local ok, reason, hwid = VerifyKey(keyStr)
    if ok and KeyAuth.OnSuccess then task.spawn(KeyAuth.OnSuccess, keyStr) end
    if not ok and KeyAuth.OnFail then task.spawn(KeyAuth.OnFail, reason) end
    return ok, reason, hwid
end

function QuantumUI:ResetKeyAuth()
    pcall(function() if isfile(KeyAuthPath) then delfile(KeyAuthPath) end end)
end

function QuantumUI.RequireKeyAuth(options)
    -- 在 QuantumUI.new 之前调用：SetupKeyAuth 的“Gate”快捷方式
    if not KeyAuth.Enabled then QuantumUI.SetupKeyAuth(options or {}) end
    KeyAuth.GateOnLoad = true
    if options then
        if options.Keys then for _,k in ipairs(options.Keys) do KeyAuth.ValidKeys[k]=true end end
        if options.Hashes then for _,h in ipairs(options.Hashes) do KeyAuth.ValidHashes[tostring(h):lower()]=true end end
        KeyAuth.BindToHWID = options.BindToHWID and true or KeyAuth.BindToHWID
        KeyAuth.AllowTrial = options.AllowTrial and true or KeyAuth.AllowTrial
        KeyAuth.TrialSeconds = options.TrialSeconds or KeyAuth.TrialSeconds
        if options.HWIDWhitelist then
            KeyAuth.HWIDWhitelist = KeyAuth.HWIDWhitelist or {}
            for _,h in ipairs(options.HWIDWhitelist) do KeyAuth.HWIDWhitelist[tostring(h):upper()]=true end
        end
        if options.OnSuccess then KeyAuth.OnSuccess = options.OnSuccess end
        if options.OnFail then KeyAuth.OnFail = options.OnFail end
    end
end

function QuantumUI:RunKeyGate()
    -- 返回 true 表示授权通过 / 试用模式；false 表示拒绝
    -- 先检查已保存的 key
    local saved = LoadAuthorizedKey()
    if saved and saved.Key then
        local ok = VerifyKey(saved.Key)
        if ok then return true end
    end
    -- 试用模式（AllowTrial）：弹出一个 trial 倒计时对话框
    local trialStart = KeyAuth.AllowTrial and tick() or nil
    local trialDuration = KeyAuth.TrialSeconds

    local screen = self.ScreenGui or error("KeyGate: ScreenGui missing", 2)
    
    -- 全屏背景遮罩
    local gateFrame = Utility.Create("Frame", {
        Name = "KeyGateScreen",
        Parent = screen,
        BackgroundColor3 = Color3.fromRGB(5, 5, 12),
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 9998
    })
    for i = 1, 20 do
        Utility.Create("Frame", {
            Parent = gateFrame,
            BackgroundColor3 = self.ThemeColor,
            BackgroundTransparency = 0.94,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 1),
            Position = UDim2.new(0, 0, i/20 - 0.025, 0)
        })
    end
    
    local card = Utility.Create("Frame", {
        Parent = gateFrame,
        BackgroundColor3 = Color3.fromRGB(15, 15, 28),
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 440, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ZIndex = 9999,
        ClipsDescendants = true
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 14)}),
        Utility.Create("UIStroke", {Color = self.ThemeColor, Thickness = 2, Transparency = 0.5})
    })
    
    local header = Utility.Create("Frame", {
        Parent = card,
        BackgroundColor3 = self.ThemeColor,
        BackgroundTransparency = 0.85,
        Size = UDim2.new(1, 0, 0, 54),
        ZIndex = 10000
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 14)})})
    
    Utility.Create("TextLabel", {
        Parent = header,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = "🔑 Access Required",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 10001
    })
    
    local content = Utility.Create("Frame", {
        Parent = card,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -32, 1, -70),
        Position = UDim2.new(0, 16, 0, 62),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 10000
    })
    
    local hwidLabel = Utility.Create("TextLabel", {
        Parent = content,
        BackgroundColor3 = Color3.fromRGB(20, 20, 32),
        BackgroundTransparency = 0.3,
        Size = UDim2.new(1, 0, 0, 28),
        Font = Enum.Font.Code,
        Text = "HWID: " .. GetHWID(),
        TextColor3 = Color3.fromRGB(180, 180, 200),
        TextSize = 12,
        ClipsDescendants = true,
        ZIndex = 10001
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 6)})})
    
    Utility.Create("TextLabel", {
        Parent = content,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22),
        Position = UDim2.new(0, 0, 0, 38),
        Font = Enum.Font.GothamBold,
        Text = "License Key",
        TextColor3 = Color3.fromRGB(230, 230, 245),
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 10001
    })
    
    local keyBox = Utility.Create("Frame", {
        Parent = content,
        BackgroundColor3 = Color3.fromRGB(20, 20, 35),
        BackgroundTransparency = 0.15,
        Size = UDim2.new(1, 0, 0, 38),
        Position = UDim2.new(0, 0, 0, 64),
        ZIndex = 10001
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
        Utility.Create("UIStroke", {Color = self.ThemeColor, Thickness = 1, Transparency = 0.7})
    })
    
    local keyInput = Utility.Create("TextBox", {
        Parent = keyBox,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        Font = Enum.Font.Code,
        Text = saved and saved.Key or "",
        TextColor3 = Color3.fromRGB(240, 240, 250),
        TextSize = 14,
        PlaceholderText = "XXXX-XXXX-XXXX-XXXX",
        PlaceholderColor3 = Color3.fromRGB(120, 120, 150),
        ClearTextOnFocus = false,
        ClipsDescendants = true,
        ZIndex = 10002
    })
    
    local statusLabel = Utility.Create("TextLabel", {
        Parent = content,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22),
        Position = UDim2.new(0, 0, 0, 108),
        Font = Enum.Font.Gotham,
        Text = "Enter a valid key to continue",
        TextColor3 = Color3.fromRGB(180, 180, 200),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 10001
    })
    
    local buttonsRow = Utility.Create("Frame", {
        Parent = content,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 134),
        ZIndex = 10001
    })
    
    local trialBtn
    if KeyAuth.AllowTrial then
        trialBtn = Utility.Create("TextButton", {
            Parent = buttonsRow,
            BackgroundColor3 = Color3.fromRGB(60, 60, 85),
            BackgroundTransparency = 0.2,
            Size = UDim2.new(0, 140, 1, 0),
            Font = Enum.Font.GothamBold,
            Text = ("Trial %ds"):format(trialDuration),
            TextColor3 = Color3.fromRGB(230, 230, 245),
            TextSize = 12,
            ZIndex = 10002
        }, {
            Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
            Utility.Create("UIStroke", {Color = Color3.fromRGB(200,200,220), Thickness = 1, Transparency = 0.6})
        })
    end
    
    local activateBtn = Utility.Create("TextButton", {
        Parent = buttonsRow,
        BackgroundColor3 = self.ThemeColor,
        BackgroundTransparency = 0.1,
        Size = KeyAuth.AllowTrial and UDim2.new(0, 140, 1, 0) or UDim2.new(0, 180, 1, 0),
        Position = KeyAuth.AllowTrial and UDim2.new(1, -140, 0, 0) or UDim2.new(1, -180, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = "Activate",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 13,
        ZIndex = 10002
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
        Utility.Create("UIStroke", {Color = Color3.fromRGB(255,255,255), Thickness = 1, Transparency = 0.6})
    })
    
    local cancelBtn = Utility.Create("TextButton", {
        Parent = buttonsRow,
        BackgroundColor3 = Color3.fromRGB(120, 40, 40),
        BackgroundTransparency = 0.3,
        Size = UDim2.new(0, 70, 1, 0),
        Position = KeyAuth.AllowTrial and UDim2.new(0.5, -35, 0, 0) or UDim2.new(0, 200, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = "Cancel",
        TextColor3 = Color3.fromRGB(255, 220, 220),
        TextSize = 12,
        ZIndex = 10002
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    -- 把 buttonsRow 往右挪，让 Cancel 出现位置正确
    if not KeyAuth.AllowTrial then
        -- Activate(180) + Cancel(70) = 250. We center buttons
        buttonsRow.Size = UDim2.new(0, 250, 0, 40)
        buttonsRow.AnchorPoint = Vector2.new(0.5, 0)
        buttonsRow.Position = UDim2.new(0.5, 0, 0, 134)
        activateBtn.Position = UDim2.new(0, 0, 0, 0)
        cancelBtn.Position = UDim2.new(0, 180, 0, 0)
    end
    
    local contentHeight = 180
    content.Size = UDim2.new(1, -32, 0, contentHeight)
    card.Size = UDim2.new(0, 440, 0, contentHeight + 78)
    
    -- Initial card appear animation
    card.BackgroundTransparency = 1
    card.Size = UDim2.new(0, 440, 0, 0)
    task.defer(function()
        Utility.Tween(card, {Size = UDim2.new(0, 440, 0, contentHeight + 78), BackgroundTransparency = 0.1}, 0.45, Enum.EasingStyle.Back)
    end)
    
    local done = false
    local result = false
    
    local function setStatus(msg, color)
        statusLabel.Text = msg
        statusLabel.TextColor3 = color or Color3.fromRGB(180, 180, 200)
    end
    
    local function finish(ok)
        if done then return end
        done = true
        result = ok
        Utility.Tween(card, {Size = UDim2.new(0, 440, 0, 0), BackgroundTransparency = 1}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        task.wait(0.3)
        gateFrame:Destroy()
    end
    
    local function tryActivate()
        local k = keyInput.Text
        if k == "" then
            setStatus("✗ Enter a key first", Color3.fromRGB(255, 140, 140))
            return
        end
        local ok, reason, hwid = VerifyKey(k)
        if ok then
            Utility.PlaySound(Sounds.SpecialLoad, 0.6)
            Utility.ScreenFlash(Color3.fromRGB(100, 255, 160), 0.4, 0.5)
            local msg = "✓ Authorized"
            if reason == "bound" then msg = "✓ Key bound to your HWID" end
            if reason == "authorized_whitelist" then msg = "✓ Whitelisted" end
            setStatus(msg, Color3.fromRGB(100, 255, 160))
            if KeyAuth.OnSuccess then task.spawn(KeyAuth.OnSuccess, k) end
            task.wait(0.6)
            finish(true)
        else
            Utility.PlaySound(Sounds.Error, 0.5)
            local map = {
                empty = "✗ Empty key",
                invalid_key = "✗ Invalid key",
                hwid_mismatch = "✗ HWID mismatch"
            }
            setStatus(map[reason] or "Unauthorized", Color3.fromRGB(255, 120, 120))
            if KeyAuth.OnFail then task.spawn(KeyAuth.OnFail, reason) end
        end
    end
    
    activateBtn.MouseButton1Click:Connect(tryActivate)
    keyInput.FocusLost:Connect(function(enterPressed) if enterPressed then tryActivate() end end)
    cancelBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        finish(false)
    end)
    if trialBtn then
        trialBtn.MouseButton1Click:Connect(function()
            Utility.PlaySound(Sounds.Click, 0.4)
            setStatus(("⏳ Trial active (%ds) - features limited"):format(trialDuration), Color3.fromRGB(255, 210, 110))
            if KeyAuth.OnSuccess then task.spawn(KeyAuth.OnSuccess, "TRIAL_MODE") end
            task.wait(0.6)
            finish(true)
        end)
    end
    
    -- 若已保存过 key，自动尝试验证
    if saved and saved.Key then
        task.defer(tryActivate)
    end
    
    -- 阻塞直到用户完成
    local t0 = tick()
    local timeout = KeyAuth.AllowTrial and (trialDuration + 7200) or 3600
    while not done and (tick() - t0 < timeout) do task.wait(0.1) end
    
    return result
end

function QuantumUI:CreateLabel(parent, options)
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 25),
        ZIndex = 7
    })
    
    local label = Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 1, 0),
        Position = UDim2.new(0, 15, 0, 0),
        Font = Enum.Font.Gotham,
        Text = options.Text or "Label",
        TextColor3 = Color3.fromRGB(200, 200, 200),
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        ZIndex = 8
    })
    
    self:UpdateContentSize(parent)
    return {Frame = frame, SetText = function(_, t) label.Text = t end}
end

function QuantumUI:CreateParagraph(parent, options)
    options = options or {}
    
    local frame = Utility.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = Color3.fromRGB(30, 30, 45),
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 70),
        ZIndex = 7
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 8)})})
    
    local titleLabel = Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 0, 25),
        Position = UDim2.new(0, 15, 0, 5),
        Font = Enum.Font.GothamBold,
        Text = options.Title or "Paragraph",
        TextColor3 = self.ThemeColor,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8
    })
    
    local contentLabel = Utility.Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -30, 0, 35),
        Position = UDim2.new(0, 15, 0, 30),
        Font = Enum.Font.Gotham,
        Text = options.Content or "",
        TextColor3 = Color3.fromRGB(180, 180, 180),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        ZIndex = 8
    })
    
    local textSize = TextService:GetTextSize(options.Content or "", 12, Enum.Font.Gotham, Vector2.new(500, math.huge))
    frame.Size = UDim2.new(1, 0, 0, math.max(70, textSize.Y + 45))
    contentLabel.Size = UDim2.new(1, -30, 0, textSize.Y + 10)
    
    self:UpdateContentSize(parent)
    
    return {
        Frame = frame,
        SetTitle = function(_, t) titleLabel.Text = t end,
        SetContent = function(_, c)
            contentLabel.Text = c
            local ts = TextService:GetTextSize(c, 12, Enum.Font.Gotham, Vector2.new(500, math.huge))
            frame.Size = UDim2.new(1, 0, 0, math.max(70, ts.Y + 45))
            contentLabel.Size = UDim2.new(1, -30, 0, ts.Y + 10)
            self:UpdateContentSize(parent)
        end
    }
end

-- ═══════════════════════════════════════════════════════════════════
--                          SETTINGS TAB (FIXED AUTO LOAD)
-- ═══════════════════════════════════════════════════════════════════

function QuantumUI:CreateSettingsTab()
    local settingsTab = self:AddTab({Name = "Settings", Icon = CustomAssets.IconSettings})
    
    -- ═══════════════════════════════════════
    -- CONFIG SECTION
    -- ═══════════════════════════════════════
    settingsTab:AddSection({Name = "📁 Config System"})
    
    local configNameTextbox = settingsTab:AddTextbox({
        Name = "Config Name",
        Placeholder = "Enter config name...",
        Callback = function(text) _G.QuantumUI_ConfigName = text end
    })
    
    settingsTab:AddButton({
        Name = "💾 Save Config",
        Callback = function()
            local configName = configNameTextbox and configNameTextbox:Get() or _G.QuantumUI_ConfigName or ""
            if configName == "" then
                self:Notify({Title = "Error", Content = "Please enter a config name!", Duration = 3, Type = "Error"})
                return
            end
            
            local saveData = {}
            for flag, element in pairs(self.Flags) do
                if element.Get then
                    local value = element:Get()
                    if typeof(value) == "Color3" then
                        -- 统一存 0-255 整数，避免浮点数误差
                        saveData[flag] = {
                            R = math.floor(value.R * 255 + 0.5),
                            G = math.floor(value.G * 255 + 0.5),
                            B = math.floor(value.B * 255 + 0.5),
                            _type = "Color3"
                        }
                    elseif typeof(value) == "EnumItem" then
                        saveData[flag] = {Name = value.Name, _type = "KeyCode"}
                    elseif type(value) == "table" then
                        saveData[flag] = {_data = value, _type = "table"}
                    else
                        saveData[flag] = value
                    end
                end
            end
            
            if ConfigSystem.Save(configName, saveData) then
                Utility.PlaySound(Sounds.ConfigSave, 0.5)
                Utility.ScreenFlash(Color3.fromRGB(0, 255, 100), 0.4, 0.3)
                self:RefreshConfigDropdowns()
                self:Notify({Title = "Saved!", Content = "Config '" .. configName .. "' saved!", Duration = 3, Type = "Success"})
            else
                self:Notify({Title = "Error", Content = "Failed to save config!", Duration = 3, Type = "Error"})
            end
        end
    })
    
    local configDropdown = settingsTab:AddDropdown({
        Name = "Select Config",
        Items = ConfigSystem.List(),
        Callback = function(selected) self.SelectedConfig = selected end
    })
    self.ConfigDropdown = configDropdown
    
    settingsTab:AddButton({
        Name = "📂 Load Config",
        Callback = function()
            if not self.SelectedConfig then
                self:Notify({Title = "Error", Content = "Please select a config!", Duration = 3, Type = "Error"})
                return
            end
            
            local data = ConfigSystem.Load(self.SelectedConfig)
            if data then
                self:ApplyConfig(data)
                Utility.PlaySound(Sounds.SpecialLoad, 0.7)
                Utility.ScreenFlash(self.ThemeColor, 0.5, 0.5)
                self:Notify({Title = "Loaded!", Content = "Config '" .. self.SelectedConfig .. "' loaded!", Duration = 3, Type = "Success"})
            else
                self:Notify({Title = "Error", Content = "Failed to load config!", Duration = 3, Type = "Error"})
            end
        end
    })
    
    settingsTab:AddButton({
        Name = "🗑️ Delete Config",
        Callback = function()
            if not self.SelectedConfig then
                self:Notify({Title = "Error", Content = "Please select a config!", Duration = 3, Type = "Error"})
                return
            end
            
            ConfigSystem.Delete(self.SelectedConfig)
            Utility.PlaySound(Sounds.Close, 0.4)
            self:RefreshConfigDropdowns()
            self.SelectedConfig = nil
            self:Notify({Title = "Deleted", Content = "Config deleted!", Duration = 3, Type = "Info"})
        end
    })
    
    -- ═══════════════════════════════════════
    -- AUTO LOAD SECTION (FIXED!)
    -- ═══════════════════════════════════════
    settingsTab:AddSection({Name = "🔄 Auto Load Config"})
    
    -- Show current auto load
    local currentAutoLoad = ConfigSystem.GetAutoLoad()
    if currentAutoLoad then
        settingsTab:AddLabel({Text = "📌 Current: " .. currentAutoLoad})
    else
        settingsTab:AddLabel({Text = "📌 No auto load config set"})
    end
    
    local autoLoadDropdown = settingsTab:AddDropdown({
        Name = "Set Auto Load",
        Items = ConfigSystem.List(),
        Callback = function(selected)
            ConfigSystem.SaveAutoLoad(selected)
            Utility.PlaySound(Sounds.ConfigSave, 0.4)
            self:Notify({
                Title = "✅ Auto Load Set!",
                Content = "'" .. selected .. "' will load on next startup.",
                Duration = 4,
                Type = "Success"
            })
        end
    })
    self.AutoLoadDropdown = autoLoadDropdown
    
    settingsTab:AddButton({
        Name = "❌ Clear Auto Load",
        Callback = function()
            ConfigSystem.ClearAutoLoad()
            Utility.PlaySound(Sounds.Close, 0.4)
            self:Notify({Title = "Cleared", Content = "Auto load disabled.", Duration = 3, Type = "Info"})
        end
    })
    
    -- ═══════════════════════════════════════
    -- UI SETTINGS SECTION
    -- ═══════════════════════════════════════
    settingsTab:AddSection({Name = "🎨 UI Settings"})
    
    self.ThemeColorPicker = settingsTab:AddColorPicker({
        Name = "Theme Color",
        Default = self.ThemeColor,
        Callback = function(color)
            self.ThemeColor = color
            QuantumUI.ThemeColor = color
            self:RefreshTheme()
        end
    })
    
    self.UITransparencySlider = settingsTab:AddSlider({
        Name = "UI Transparency",
        Min = 0,
        Max = 90,
        Default = self.Transparency * 100,
        Suffix = "%",
        Callback = function(value)
            self:SetTransparency(value / 100)
        end
    })
    
    -- NEW: Background Settings
    settingsTab:AddSection({Name = "🖼️ Background"})
    
    local bgImageId = ""
    settingsTab:AddTextbox({
        Name = "Background Image ID",
        Placeholder = "rbxassetid://...",
        Callback = function(text) bgImageId = text end
    })
    
    settingsTab:AddButton({
        Name = "🖼️ Set Background",
        Callback = function()
            if bgImageId ~= "" then
                self:SetBackground(bgImageId)
                self:Notify({Title = "Background Set", Content = "Background image applied!", Duration = 3, Type = "Success"})
            end
        end
    })
    
    settingsTab:AddButton({
        Name = "❌ Remove Background",
        Callback = function()
            self:RemoveBackground()
            self:Notify({Title = "Background Removed", Content = "Background image removed.", Duration = 3, Type = "Info"})
        end
    })
    
    self.BgTransparencySlider = settingsTab:AddSlider({
        Name = "Background Transparency",
        Min = 0,
        Max = 100,
        Default = 50,
        Suffix = "%",
        Callback = function(value)
            self:SetBackgroundTransparency(value / 100)
        end
    })
    
    -- Rainbow Settings
    settingsTab:AddSection({Name = "🌈 Rainbow Border"})
    
    self.RainbowBorderToggle = settingsTab:AddToggle({
        Name = "Rainbow Border",
        Default = QuantumUI.RainbowEnabled,
        Callback = function(state) QuantumUI.RainbowEnabled = state end
    })
    
    self.RainbowSpeedSlider = settingsTab:AddSlider({
        Name = "Rainbow Speed",
        Min = 0.1,
        Max = 5,
        Default = QuantumUI.RainbowSpeed,
        Increment = 0.1,
        Callback = function(value) QuantumUI.RainbowSpeed = value end
    })
    
    -- ═══════════════════════════════════════
    -- UI CONFIG SECTION (save/load UI appearance)
    -- ═══════════════════════════════════════
    settingsTab:AddSection({Name = "⚙️ UI Config"})
    
    local uiConfigNameTextbox = settingsTab:AddTextbox({
        Name = "UI Config Name",
        Placeholder = "Enter config name...",
        Callback = function(text) _G.QuantumUI_UIConfigName = text end
    })
    
    settingsTab:AddButton({
        Name = "💾 Save UI Config",
        Callback = function()
            local uiConfigName = uiConfigNameTextbox and uiConfigNameTextbox:Get() or _G.QuantumUI_UIConfigName or ""
            if uiConfigName == "" then
                self:Notify({Title = "Error", Content = "Enter a config name first!", Duration = 3, Type = "Error"})
                return
            end
            
            local uiData = {
                _type = "UIConfig",
                ThemeColor = {R = self.ThemeColor.R, G = self.ThemeColor.G, B = self.ThemeColor.B},
                Transparency = self.Transparency,
                BackgroundImage = self.BackgroundImage,
                BackgroundTransparency = self.BackgroundTransparency,
                RainbowEnabled = QuantumUI.RainbowEnabled,
                RainbowSpeed = QuantumUI.RainbowSpeed,
                WindowSize = {X = self.Size.X.Offset, Y = self.Size.Y.Offset},
                WindowPosition = self.MainFrame and {
                    X = self.MainFrame.Position.X.Scale,
                    Y = self.MainFrame.Position.Y.Scale,
                    XOff = self.MainFrame.Position.X.Offset,
                    YOff = self.MainFrame.Position.Y.Offset
                } or nil,
            }
            
            if ConfigSystem.SaveUI(uiConfigName, uiData) then
                Utility.PlaySound(Sounds.ConfigSave, 0.5)
                Utility.ScreenFlash(Color3.fromRGB(0, 200, 255), 0.4, 0.3)
                self:RefreshConfigDropdowns()
                self:Notify({Title = "UI Config Saved!", Content = "'" .. uiConfigName .. "' saved.", Duration = 3, Type = "Success"})
            else
                self:Notify({Title = "Error", Content = "Failed to save UI config!", Duration = 3, Type = "Error"})
            end
        end
    })
    
    local uiConfigDropdown = settingsTab:AddDropdown({
        Name = "UI Config List",
        Items = ConfigSystem.ListUI(),
        Callback = function(selected) self.SelectedUIConfig = selected end
    })
    self.UIConfigDropdown = uiConfigDropdown
    
    settingsTab:AddButton({
        Name = "📂 Load UI Config",
        Callback = function()
            if not self.SelectedUIConfig then
                self:Notify({Title = "Error", Content = "Select a UI config first!", Duration = 3, Type = "Error"})
                return
            end
            
            local data = ConfigSystem.LoadUI(self.SelectedUIConfig)
            if not data or data._type ~= "UIConfig" then
                self:Notify({Title = "Error", Content = "Not a valid UI config!", Duration = 3, Type = "Error"})
                return
            end
            
            -- Apply theme color
            if data.ThemeColor then
                local r = data.ThemeColor.R > 1 and data.ThemeColor.R / 255 or data.ThemeColor.R
                local g = data.ThemeColor.G > 1 and data.ThemeColor.G / 255 or data.ThemeColor.G
                local b = data.ThemeColor.B > 1 and data.ThemeColor.B / 255 or data.ThemeColor.B
                local c = Color3.new(r, g, b)
                self.ThemeColor = c
                QuantumUI.ThemeColor = c
                self:RefreshTheme()
            end
            
            -- Apply transparency
            if data.Transparency then
                self:SetTransparency(data.Transparency)
            end
            
            -- Apply background
            if data.BackgroundImage then
                self:SetBackground(data.BackgroundImage, data.BackgroundTransparency)
            else
                self:RemoveBackground()
            end
            
            -- Apply rainbow
            if data.RainbowEnabled ~= nil then
                QuantumUI.RainbowEnabled = data.RainbowEnabled
            end
            if data.RainbowSpeed then
                QuantumUI.RainbowSpeed = data.RainbowSpeed
            end
            
            -- Apply window size
            if data.WindowSize and self.MainFrame then
                Utility.Tween(self.MainFrame, {
                    Size = UDim2.new(0, data.WindowSize.X, 0, data.WindowSize.Y)
                }, 0.3)
            end
            
            -- Apply window position
            if data.WindowPosition and self.MainFrame then
                Utility.Tween(self.MainFrame, {
                    Position = UDim2.new(
                        data.WindowPosition.X, data.WindowPosition.XOff,
                        data.WindowPosition.Y, data.WindowPosition.YOff
                    )
                }, 0.3)
            end
            
            -- SYNC Settings Tab controls with loaded values
            task.defer(function()
                if self.ThemeColorPicker and self.ThemeColorPicker.Set and data.ThemeColor then
                    self.ThemeColorPicker:Set(self.ThemeColor)
                end
                if self.UITransparencySlider and self.UITransparencySlider.Set and data.Transparency then
                    self.UITransparencySlider:Set(math.round(data.Transparency * 100))
                end
                if self.BgTransparencySlider and self.BgTransparencySlider.Set then
                    self.BgTransparencySlider:Set(math.round((data.BackgroundTransparency or self.BackgroundTransparency or 0.5) * 100))
                end
                if self.RainbowBorderToggle and self.RainbowBorderToggle.Set and data.RainbowEnabled ~= nil then
                    self.RainbowBorderToggle:Set(data.RainbowEnabled)
                end
                if self.RainbowSpeedSlider and self.RainbowSpeedSlider.Set and data.RainbowSpeed then
                    self.RainbowSpeedSlider:Set(data.RainbowSpeed)
                end
            end)
            
            Utility.PlaySound(Sounds.SpecialLoad, 0.7)
            Utility.ScreenFlash(self.ThemeColor, 0.5, 0.5)
            self:Notify({Title = "UI Config Loaded!", Content = "'" .. self.SelectedUIConfig .. "' applied.", Duration = 3, Type = "Success"})
        end
    })
    
    settingsTab:AddButton({
        Name = "🗑️ Delete UI Config",
        Callback = function()
            if not self.SelectedUIConfig then
                self:Notify({Title = "Error", Content = "Select a UI config first!", Duration = 3, Type = "Error"})
                return
            end
            
            ConfigSystem.DeleteUI(self.SelectedUIConfig)
            Utility.PlaySound(Sounds.Close, 0.4)
            self:RefreshConfigDropdowns()
            self.SelectedUIConfig = nil
            self:Notify({Title = "Deleted", Content = "UI config deleted.", Duration = 3, Type = "Info"})
        end
    })
    
    settingsTab:AddButton({
        Name = "🔄 Refresh List",
        Callback = function()
            self:RefreshConfigDropdowns()
            self:Notify({Title = "Refreshed", Content = "Config list updated.", Duration = 2, Type = "Info"})
        end
    })
    
    -- ═══════════════════════════════════════
    -- ACTIONS SECTION
    -- ═══════════════════════════════════════
    settingsTab:AddSection({Name = "🎮 Actions"})
    
    settingsTab:AddButton({
        Name = "🔄 Rejoin Server",
        Callback = function()
            Utility.PlaySound(Sounds.Click, 0.3)
            self:Notify({Title = "Rejoining...", Content = "Teleporting back...", Duration = 2, Type = "Info"})
            task.wait(0.5)
            game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
        end
    })
    
    settingsTab:AddButton({
        Name = "❌ Disable All Features",
        Callback = function()
            Utility.PlaySound(Sounds.Close, 0.4)
            local count = 0
            for _, element in pairs(self.Flags) do
                if element.Get and type(element:Get()) == "boolean" and element:Get() == true then
                    element:Set(false)
                    count = count + 1
                end
            end
            Utility.ScreenFlash(Color3.fromRGB(255, 0, 0), 0.3, 0.3)
            self:Notify({Title = "Disabled", Content = count .. " features disabled.", Duration = 3, Type = "Warning"})
        end
    })
    
    settingsTab:AddButton({
        Name = "💀 Destroy UI",
        Callback = function()
            self:DangerConfirm({
                Title = "销毁 UI 确认",
                Content = "你确定要销毁 Quantum UI 吗？\n\n销毁后需要重新注入 loadstring 才能恢复，\n并且所有未保存的配置会丢失！",
                ConfirmText = "确定销毁",
                CancelText  = "取消",
                OnConfirm = function()
                    Utility.PlaySound(Sounds.Close, 0.5)
                    pcall(function()
                        self:Notify({Title = "Goodbye!", Content = "Destroying UI...", Duration = 1, Type = "Info"})
                    end)
                    task.wait(1)
                    self:Destroy()
                end,
            })
        end
    })
    
    settingsTab:AddKeybind({
        Name = "Toggle UI Key",
        Default = self.Keybind,
        ChangedCallback = function(key) self.Keybind = key end
    })
    
    -- ═══════════════════════════════════════
    -- CREDITS SECTION
    -- ═══════════════════════════════════════
    settingsTab:AddSection({Name = "ℹ️ Credits"})
    
    settingsTab:AddParagraph({
        Title = "Quantum UI v" .. QuantumUI.Version,
        Content = "Sci-fi UI library with:\n• Rainbow borders\n• Config system with Auto Load\n• Custom background support\n• Mobile support"
    })
    
    settingsTab:AddLabel({Text = "Created by: log_quick"})
    settingsTab:AddLabel({Text = "GitHub: github.com/logquickly"})
end

function QuantumUI:RefreshConfigDropdowns()
    local functionConfigs = ConfigSystem.List()      -- QuantumUI/Configs/
    local uiConfigs = ConfigSystem.ListUI()          -- QuantumUI/UIConfigs/
    
    if self.ConfigDropdown then self.ConfigDropdown:Refresh(functionConfigs) end
    if self.AutoLoadDropdown then self.AutoLoadDropdown:Refresh(functionConfigs) end
    if self.UIConfigDropdown then self.UIConfigDropdown:Refresh(uiConfigs) end
end

-- ═══════════════════════════════════════════════════════════════════
--                          NOTIFICATION SYSTEM
-- ═══════════════════════════════════════════════════════════════════

function QuantumUI:Notify(options)
    options = options or {}
    local title = options.Title or "Notification"
    local content = options.Content or ""
    local duration = options.Duration or 3
    local nType = options.Type or "Info"
    
    local colors = {
        Info = Color3.fromRGB(0, 170, 255),
        Success = Color3.fromRGB(0, 255, 100),
        Warning = Color3.fromRGB(255, 200, 0),
        Error = Color3.fromRGB(255, 80, 80)
    }
    local color = colors[nType] or self.ThemeColor
    
    if not self.NotifContainer then
        self.NotifContainer = Utility.Create("Frame", {
            Parent = self.ScreenGui,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 300, 1, 0),
            Position = UDim2.new(1, -320, 0, 0),
            ZIndex = 100
        }, {
            Utility.Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 10)}),
            Utility.Create("UIPadding", {PaddingBottom = UDim.new(0, 20)})
        })
    end
    
    local notif = Utility.Create("Frame", {
        Parent = self.NotifContainer,
        BackgroundColor3 = Color3.fromRGB(20, 20, 35),
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        ZIndex = 101
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 10)}),
        Utility.Create("UIStroke", {Color = color, Thickness = 2, Transparency = 0.3})
    })
    
    Utility.Create("Frame", {
        Parent = notif,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 4, 1, -10),
        Position = UDim2.new(0, 5, 0, 5),
        ZIndex = 102
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 2)})})
    
    Utility.Create("TextLabel", {
        Parent = notif,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -25, 0, 25),
        Position = UDim2.new(0, 15, 0, 5),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = color,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 102
    })
    
    Utility.Create("TextLabel", {
        Parent = notif,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -25, 0, 40),
        Position = UDim2.new(0, 15, 0, 30),
        Font = Enum.Font.Gotham,
        Text = content,
        TextColor3 = Color3.fromRGB(200, 200, 200),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        ZIndex = 102
    })
    
    local progress = Utility.Create("Frame", {
        Parent = notif,
        BackgroundColor3 = color,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 3),
        Position = UDim2.new(0, 0, 1, -3),
        ZIndex = 102
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 2)})})
    
    local textSize = TextService:GetTextSize(content, 12, Enum.Font.Gotham, Vector2.new(270, math.huge))
    local height = math.max(70, textSize.Y + 45)
    
    Utility.PlaySound(Sounds.Notification, 0.4)
    Utility.Tween(notif, {Size = UDim2.new(1, 0, 0, height)}, 0.3, Enum.EasingStyle.Back)
    Utility.Tween(progress, {Size = UDim2.new(0, 0, 0, 3)}, duration, Enum.EasingStyle.Linear)
    
    task.delay(duration, function()
        Utility.Tween(notif, {Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1}, 0.3)
        task.wait(0.3)
        if notif then notif:Destroy() end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--  DANGERCONFIRM — 危险操作二次确认模态弹窗
--  使用: Window:DangerConfirm({
--      Title = "确认操作",
--      Content = "确定要...？此操作无法撤销！",
--      ConfirmText = "确定",          -- 可选，默认"确定"
--      CancelText  = "取消",          -- 可选，默认"取消"
--      OnConfirm   = function() ... end,
--      OnCancel    = function() ... end, -- 可选
--  })
-- ═══════════════════════════════════════════════════════════════════
function QuantumUI:DangerConfirm(options)
    options = options or {}
    local title       = options.Title       or "危险操作"
    local content     = options.Content     or "确定要继续吗？"
    local confirmText = options.ConfirmText or "确定"
    local cancelText  = options.CancelText  or "取消"
    local onConfirm   = options.OnConfirm
    local onCancel    = options.OnCancel

    if not self.ScreenGui or not self.ScreenGui.Parent then
        -- UI 已销毁的情况下仍允许通过 (方便销毁流程自举)
        if onConfirm then task.spawn(onConfirm) end
        return
    end

    Utility.PlaySound(Sounds.Error, 0.3)

    local DANGER_COLOR = Color3.fromRGB(255, 70, 80)

    -- 屏幕遮罩
    local overlay = Utility.Create("Frame", {
        Parent = self.ScreenGui,
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.6,
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        ZIndex = 9000,
        Active = true,
    })
    overlay.BackgroundTransparency = 1
    Utility.Tween(overlay, {BackgroundTransparency = 0.6}, 0.25)

    -- 弹窗容器
    local modal = Utility.Create("Frame", {
        Parent = overlay,
        BackgroundColor3 = Color3.fromRGB(15, 15, 28),
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 420, 0, 0),
        Position = UDim2.new(0.5, 0, 0.4, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ZIndex = 9001,
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 14)}),
        Utility.Create("UIStroke", {Color = DANGER_COLOR, Thickness = 2, Transparency = 0.25}),
    })

    -- 顶部红色警示条
    Utility.Create("Frame", {
        Parent = modal,
        BackgroundColor3 = DANGER_COLOR,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 4),
        Position = UDim2.new(0, 0, 0, 0),
        ZIndex = 9002,
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 2)})})

    -- ⚠ 图标
    Utility.Create("TextLabel", {
        Parent = modal,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 40, 0, 40),
        Position = UDim2.new(0, 20, 0, 22),
        Font = Enum.Font.GothamBlack,
        Text = "⚠",
        TextColor3 = DANGER_COLOR,
        TextSize = 34,
        ZIndex = 9002,
    })

    -- 标题
    Utility.Create("TextLabel", {
        Parent = modal,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -80, 0, 30),
        Position = UDim2.new(0, 68, 0, 20),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = DANGER_COLOR,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 9002,
    })

    -- 正文
    local contentLabel = Utility.Create("TextLabel", {
        Parent = modal,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -40, 0, 60),
        Position = UDim2.new(0, 20, 0, 72),
        Font = Enum.Font.Gotham,
        Text = content,
        TextColor3 = Color3.fromRGB(220, 220, 220),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        ZIndex = 9002,
    })

    -- 测量正文高度
    local textSize = TextService:GetTextSize(content, 14, Enum.Font.Gotham, Vector2.new(420 - 40, math.huge))
    local contentHeight = math.max(60, textSize.Y + 10)
    contentLabel.Size = UDim2.new(1, -40, 0, contentHeight)

    local modalHeight = 72 + contentHeight + 85   -- 72 = 标题到正文间距; 85 = 按钮区+padding

    -- 取消按钮
    local cancelBtn = Utility.Create("TextButton", {
        Parent = modal,
        BackgroundColor3 = Color3.fromRGB(40, 40, 60),
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 180, 0, 40),
        Position = UDim2.new(0, 20, 0, modalHeight - 60),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 9002,
    }, {Utility.Create("UICorner", {CornerRadius = UDim.new(0, 10)})})

    Utility.Create("TextLabel", {
        Parent = cancelBtn,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamSemibold,
        Text = cancelText,
        TextColor3 = Color3.fromRGB(220, 220, 220),
        TextSize = 14,
        ZIndex = 9003,
    })

    -- 确定按钮 (红色危险)
    local confirmBtn = Utility.Create("TextButton", {
        Parent = modal,
        BackgroundColor3 = DANGER_COLOR,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 180, 0, 40),
        Position = UDim2.new(1, -200, 0, modalHeight - 60),
        Text = "",
        AutoButtonColor = false,
        ZIndex = 9002,
    }, {
        Utility.Create("UICorner", {CornerRadius = UDim.new(0, 10)}),
        Utility.Create("UIStroke", {Color = Color3.fromRGB(255, 255, 255), Thickness = 1, Transparency = 0.7}),
    })

    Utility.Create("TextLabel", {
        Parent = confirmBtn,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamBold,
        Text = confirmText,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextSize = 14,
        ZIndex = 9003,
    })

    modal.Size = UDim2.new(0, 420, 0, 0)
    Utility.Tween(modal, {Size = UDim2.new(0, 420, 0, modalHeight)}, 0.35, Enum.EasingStyle.Back)

    local resolved = false
    local function closeModal()
        if resolved then return end
        resolved = true
        Utility.Tween(modal, {Size = UDim2.new(0, 420, 0, 0), BackgroundTransparency = 1}, 0.25)
        Utility.Tween(overlay, {BackgroundTransparency = 1}, 0.25)
        task.wait(0.28)
        pcall(function() overlay:Destroy() end)
    end

    cancelBtn.MouseEnter:Connect(function()
        Utility.Tween(cancelBtn, {BackgroundColor3 = Color3.fromRGB(60, 60, 85), BackgroundTransparency = 0}, 0.15)
        Utility.PlaySound(Sounds.Hover, 0.25)
    end)
    cancelBtn.MouseLeave:Connect(function()
        Utility.Tween(cancelBtn, {BackgroundColor3 = Color3.fromRGB(40, 40, 60), BackgroundTransparency = 0.15}, 0.15)
    end)
    cancelBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.3)
        closeModal()
        if onCancel then task.spawn(onCancel) end
    end)

    confirmBtn.MouseEnter:Connect(function()
        Utility.Tween(confirmBtn, {BackgroundColor3 = Color3.fromRGB(255, 90, 100)}, 0.15)
        Utility.PlaySound(Sounds.Hover, 0.25)
    end)
    confirmBtn.MouseLeave:Connect(function()
        Utility.Tween(confirmBtn, {BackgroundColor3 = DANGER_COLOR}, 0.15)
    end)
    confirmBtn.MouseButton1Click:Connect(function()
        Utility.PlaySound(Sounds.Click, 0.35)
        closeModal()
        if onConfirm then task.spawn(onConfirm) end
    end)
end

return QuantumUI
