--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║   Quantum UI — MUSIC 分支 (music.lua)  v1.0.0                    ║
    ║   by log_quick  ·  https://github.com/logz-c/Log-Hub             ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║   用法                                                            ║
    ║   ─────────────────────────────────────────────────────────────  ║
    ║   local QuantumUI = loadstring(game:HttpGet(SRC))()               ║
    ║   local MusicUI   = loadstring(game:HttpGet(MUSIC))()(QuantumUI)  ║
    ║   local Win  = QuantumUI.new({Title="Hub"})                       ║
    ║   local Tab  = Win:AddMusicTab({Name="MUSIC", Icon="rbxassetid://…"}) ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║   新增 API                                                        ║
    ║   Window:AddMusicTab(opts)        音乐分支（默认弹出式）           ║
    ║       · 选中该分支 → 隐藏主窗口 + 弹出音乐窗口（二者不并存）      ║
    ║       · 关闭音乐窗口 / 切到其它页签 → 自动恢复主窗口与上一个页签  ║
    ║       · opts.Popup = false 可改为内联（内容直接铺在主窗口页面里）  ║
    ║       · opts.WindowSize / WindowPosition / Title 控制弹出窗口      ║
    ║   Tab:OpenMusic() / CloseMusic() / GetMusicWindow()               ║
    ║   Window:CreateMusicWindow(opts)  独立浮动音乐窗口                 ║
    ║   Tab:AddMusicPlayer(opts)        播放卡片（封面/标题/传输键/进度/音量）║
    ║   Tab:AddSearchBox(opts)          搜索框（防抖 / 清空）            ║
    ║   Tab:AddSubTabs(list, cb)        二级分类条（带角标）             ║
    ║   Tab:AddPanel(name)              面板（面板间互斥显示）           ║
    ║   Tab:AddSongList(opts)           歌曲列表（封面/收藏/播放态/空态/加载态）║
    ║   Tab:AddLyricPanel(opts)         歌词面板（逐行高亮 / 点击跳转）  ║
    ║   Tab:AddQueue(opts)              播放队列（上移/下移/删除/清空）  ║
    ║   Tab:AddAlbumGrid(opts)          封面宫格（歌单 / 专辑墙）        ║
    ║   Tab:AddChipBar(opts)            标签条（分类筛选）               ║
    ║   Tab:AddSection / AddButton / AddToggle / AddSlider / …          ║
    ║                                   （标准控件可直接塞进面板）      ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║   美术资源                                                        ║
    ║   所有图标默认「代码绘制」：矩形 + 旋转矩形（裁剪成三角），       ║
    ║   零外部资源、跟随主题换色、无视 USE_SQUARE_CORNERS 方角模式。    ║
    ║   想换成上传的贴图，把 MusicUI.Assets.Play 之类改成               ║
    ║   "rbxassetid://123456789" 即可，控件自动切换为 ImageLabel。      ║
    ╚══════════════════════════════════════════════════════════════════╝
]]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local SoundService      = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer

local MusicUI = {}
MusicUI.Version = "1.4.0"

-- ═══════════════════════════════════════════════════════════════════
--  美术资源槽位
--  UPLOADED = 已上传到 Roblox 的贴图（白色图形 + 透明底，可被 ImageColor3 染色，
--  跟随主题/风格/hover 状态换色）。留空 "" 会回退到内置「代码绘制」图标。
--    · 整体切回绘制版：MusicUI.UseDrawnIcons()
--    · 恢复上传版：    MusicUI.UseUploadedIcons()
--    · 换自己的图：    MusicUI.Assets.Play = "rbxassetid://123456789"
-- ═══════════════════════════════════════════════════════════════════
local UPLOADED = {
    Play      = "rbxassetid://114740604284026",
    Pause     = "rbxassetid://111792844682744",
    Prev      = "rbxassetid://84496266493568",
    Next      = "rbxassetid://84698543566466",
    Shuffle   = "rbxassetid://97719146198787",
    Repeat    = "rbxassetid://104289200437812",
    RepeatOne = "rbxassetid://105576549727493",
    Heart     = "rbxassetid://75603968806920",
    HeartOn   = "rbxassetid://75603968806920",
    Search    = "rbxassetid://80913948633532",
    Clear     = "rbxassetid://81810251029618",
    Volume    = "rbxassetid://102533846914077",
    Mute      = "rbxassetid://105301103725420",
    Queue     = "rbxassetid://72337420724977",
    Note      = "rbxassetid://111780610859716",
    Close     = "rbxassetid://77309987267353",
    Plus      = "rbxassetid://122564974827162",
    Trash     = "rbxassetid://109916746890494",
    Up        = "rbxassetid://100978389702505",
    Down      = "rbxassetid://84206135890973",
    Cover     = "rbxassetid://128130074289760",   -- 彩色默认封面，不染色
    Bg        = "",                                -- 音乐页背景图（留空 = 纯色）
}

MusicUI.Assets = {}
for k, v in pairs(UPLOADED) do MusicUI.Assets[k] = v end

-- 一键切回「代码绘制」图标（离线 / 不依赖上传资产时用）
function MusicUI.UseDrawnIcons()
    for k in pairs(MusicUI.Assets) do MusicUI.Assets[k] = "" end
end

-- 一键恢复上传贴图
function MusicUI.UseUploadedIcons()
    for k, v in pairs(UPLOADED) do MusicUI.Assets[k] = v end
end

-- ═══════════════════════════════════════════════════════════════════
--  内部工具：优先复用主库 Utility，缺失时用精简兜底实现
-- ═══════════════════════════════════════════════════════════════════
local Util, Sounds = nil, {}

local function buildFallbackUtility()
    local U = {}
    function U.Create(className, properties, children)
        local inst = Instance.new(className)
        for prop, value in pairs(properties or {}) do
            if prop ~= "Parent" then pcall(function() inst[prop] = value end) end
        end
        for _, child in pairs(children or {}) do
            if child and child ~= true then pcall(function() child.Parent = inst end) end
        end
        if properties and properties.Parent then inst.Parent = properties.Parent end
        return inst
    end
    function U.Tween(object, properties, duration, style, direction)
        if not object then return end
        local t = TweenService:Create(object, TweenInfo.new(
            duration or 0.3, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out), properties)
        t:Play()
        return t
    end
    function U.PlaySound(soundId, volume)
        pcall(function()
            local s = Instance.new("Sound")
            s.SoundId = soundId
            s.Volume = volume or 0.5
            s.Parent = SoundService
            s:Play()
            s.Ended:Connect(function() s:Destroy() end)
        end)
    end
    function U.Ripple() end
    return U
end

local Q = nil   -- QuantumUI 类表

local function bindInternals(cls)
    Q = cls
    local int = (type(cls) == "table" and cls.Internals) or nil
    if int and type(int.Utility) == "table" then
        Util = int.Utility
        if type(int.Sounds) == "table" then Sounds = int.Sounds end
    else
        Util = buildFallbackUtility()
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  小工具
-- ═══════════════════════════════════════════════════════════════════
local function C(r, g, b) return Color3.fromRGB(r, g, b) end

local function fmtTime(sec)
    sec = tonumber(sec) or 0
    if sec < 0 then sec = 0 end
    local m = math.floor(sec / 60)
    local s = math.floor(sec % 60)
    if m >= 60 then
        return string.format("%d:%02d:%02d", math.floor(m / 60), m % 60, s)
    end
    return string.format("%02d:%02d", m, s)
end

local function clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function safeCb(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then warn("[MusicUI] callback error: " .. tostring(err)) end
end

local function mousePos()
    local ok, p = pcall(function() return UserInputService:GetMouseLocation() end)
    if ok and p then return Vector2.new(p.X, p.Y) end
    return Vector2.new(0, 0)
end

local function ripple(frame, color)
    if not Util.Ripple then return end
    pcall(function() Util.Ripple(frame, mousePos(), color) end)
end

local function snd(key, vol)
    local id = Sounds[key]
    if type(id) == "string" and id ~= "" then
        pcall(function() Util.PlaySound(id, vol) end)
    end
end

-- 主题取色（带兜底）
local function themeColor(self, key)
    if type(self) == "table" and type(self.T) == "function" then
        local ok, c = pcall(self.T, self, key)
        if ok and typeof(c) == "Color3" then return c end
    end
    local fallback = {
        Accent = C(0, 200, 255), Section = C(25, 25, 40), Control = C(30, 30, 45),
        ControlHover = C(40, 40, 55), ControlAlt = C(50, 50, 65), ControlHover2 = C(60, 60, 85),
        Text = C(255, 255, 255), TextBright = C(230, 230, 240), TextDim = C(200, 200, 200),
        TextFaint = C(150, 150, 150), TopBar = C(20, 20, 35), MainBg = C(15, 15, 25),
    }
    return fallback[key] or C(255, 255, 255)
end

-- ═══════════════════════════════════════════════════════════════════
--  图标绘制（矩形 + 旋转矩形裁剪三角，全部矢量，无外部资源）
-- ═══════════════════════════════════════════════════════════════════
local Draw = {}

local function B(parent, x, y, w, h, color, z)
    return Util.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Position = UDim2.new(0, math.floor(x + 0.5), 0, math.floor(y + 0.5)),
        Size = UDim2.new(0, math.max(1, math.ceil(w)), 0, math.max(1, math.ceil(h))),
        ZIndex = z or 10,
    })
end

-- 右指三角：容器 (w × h) 裁剪一个 45° 旋转方块（要求 h <= 2w）
function Draw.Tri(parent, w, h, color, z, rot, cx, cy)
    local cont = Util.Create("Frame", {
        Parent = parent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(0, math.ceil(w), 0, math.ceil(h)),
        ClipsDescendants = true,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, cx or 0, 0, cy or 0),
        Rotation = rot or 0,
        ZIndex = z or 10,
    })
    local L = w * 1.41421356 + 2
    Util.Create("Frame", {
        Parent = cont,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Size = UDim2.new(0, math.ceil(L), 0, math.ceil(L)),
        Rotation = 45,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        ZIndex = z or 10,
    })
    return cont
end

local IconBuilders = {}

IconBuilders.Play = function(f, S, col, z)
    Draw.Tri(f, S * 0.52, S * 0.90, col, z, 0, S / 2, S / 2)
end

IconBuilders.Pause = function(f, S, col, z)
    local bw = math.max(2, S * 0.16)
    local bh = S * 0.74
    local gap = S * 0.18
    local x0 = (S - (bw * 2 + gap)) / 2
    B(f, x0, (S - bh) / 2, bw, bh, col, z)
    B(f, x0 + bw + gap, (S - bh) / 2, bw, bh, col, z)
end

IconBuilders.Next = function(f, S, col, z)
    local bw = math.max(2, S * 0.13)
    local tw = S * 0.42
    local th = S * 0.70
    local gap = S * 0.05
    local total = tw + gap + bw
    local x0 = (S - total) / 2
    Draw.Tri(f, tw, th, col, z, 0, x0 + tw / 2, S / 2)
    B(f, x0 + tw + gap, (S - th) / 2, bw, th, col, z)
end

IconBuilders.Prev = function(f, S, col, z)
    local bw = math.max(2, S * 0.13)
    local tw = S * 0.42
    local th = S * 0.70
    local gap = S * 0.05
    local total = bw + gap + tw
    local x0 = (S - total) / 2
    B(f, x0, (S - th) / 2, bw, th, col, z)
    Draw.Tri(f, tw, th, col, z, 180, x0 + bw + gap + tw / 2, S / 2)
end

IconBuilders.Heart = function(f, S, col, z)
    local u = S / 7
    local oy = (S - u * 6) / 2
    local rows = {
        {x = 1, w = 2}, {x = 4, w = 2},
    }
    for _, r in ipairs(rows) do B(f, r.x * u, oy, r.w * u, u, col, z) end
    B(f, 0, oy + u, 7 * u, u, col, z)
    B(f, 0, oy + u * 2, 7 * u, u, col, z)
    B(f, 1 * u, oy + u * 3, 5 * u, u, col, z)
    B(f, 2 * u, oy + u * 4, 3 * u, u, col, z)
    B(f, 3 * u, oy + u * 5, 1 * u, u, col, z)
end

IconBuilders.HeartOn = IconBuilders.Heart

IconBuilders.Search = function(f, S, col, z)
    local o = S * 0.08
    local sz = S * 0.62
    local t = math.max(2, S * 0.11)
    B(f, o, o, sz, t, col, z)
    B(f, o, o + sz - t, sz, t, col, z)
    B(f, o, o, t, sz, col, z)
    B(f, o + sz - t, o, t, sz, col, z)
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, S * 0.40, 0, t),
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, S * 0.60, 0, S * 0.62),
        Rotation = 45, ZIndex = z,
    })
end

IconBuilders.Clear = function(f, S, col, z)
    local o = S * 0.20
    local sz = S * 0.60
    local t = math.max(2, S * 0.12)
    B(f, o, o, sz, t, col, z)
    B(f, o, o + sz - t, sz, t, col, z)
    B(f, o, o, t, sz, col, z)
    B(f, o + sz - t, o, t, sz, col, z)
    local d = sz * 1.41421356
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, d, 0, t), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, S / 2, 0, S / 2), Rotation = 45, ZIndex = z,
    })
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, d, 0, t), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, S / 2, 0, S / 2), Rotation = -45, ZIndex = z,
    })
end

IconBuilders.Volume = function(f, S, col, z)
    local ch = S * 0.30
    B(f, S * 0.08, (S - ch) / 2, S * 0.12, ch, col, z)
    Draw.Tri(f, S * 0.20, S * 0.52, col, z, 0, S * 0.30, S / 2)
    B(f, S * 0.54, S * 0.36, S * 0.08, S * 0.28, col, z)
    B(f, S * 0.70, S * 0.26, S * 0.08, S * 0.48, col, z)
    B(f, S * 0.86, S * 0.16, S * 0.08, S * 0.68, col, z)
end

IconBuilders.Mute = function(f, S, col, z)
    local ch = S * 0.30
    B(f, S * 0.06, (S - ch) / 2, S * 0.12, ch, col, z)
    Draw.Tri(f, S * 0.18, S * 0.52, col, z, 0, S * 0.26, S / 2)
    local d = S * 0.52
    local t = math.max(2, S * 0.10)
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, d, 0, t), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, S * 0.70, 0, S / 2), Rotation = 45, ZIndex = z,
    })
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, d, 0, t), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, S * 0.70, 0, S / 2), Rotation = -45, ZIndex = z,
    })
end

IconBuilders.Queue = function(f, S, col, z)
    local bh = math.max(2, S * 0.11)
    local bw = S * 0.52
    local x = S * 0.36
    for i = 0, 2 do
        local y = S * (0.20 + i * 0.28)
        B(f, x, y, bw, bh, col, z)
        B(f, S * 0.10, y - S * 0.03, bh + 1, bh + 2, col, z)
    end
end

IconBuilders.Note = function(f, S, col, z)
    local t = math.max(2, S * 0.10)
    B(f, S * 0.60, S * 0.16, t, S * 0.62, col, z)
    B(f, S * 0.20, S * 0.58, S * 0.44, S * 0.26, col, z)
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, S * 0.40, 0, t), AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, S * 0.62, 0, S * 0.20), Rotation = 28, ZIndex = z,
    })
end

IconBuilders.Close = function(f, S, col, z)
    local d = S * 0.72
    local t = math.max(2, S * 0.11)
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, d, 0, t), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, S / 2, 0, S / 2), Rotation = 45, ZIndex = z,
    })
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, d, 0, t), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, S / 2, 0, S / 2), Rotation = -45, ZIndex = z,
    })
end

IconBuilders.Plus = function(f, S, col, z)
    local t = math.max(2, S * 0.14)
    local d = S * 0.66
    B(f, (S - t) / 2, (S - d) / 2, t, d, col, z)
    B(f, (S - d) / 2, (S - t) / 2, d, t, col, z)
end

IconBuilders.Trash = function(f, S, col, z)
    local t = math.max(2, S * 0.09)
    B(f, S * 0.32, S * 0.14, S * 0.36, t, col, z)
    B(f, S * 0.46, S * 0.08, S * 0.08, t, col, z)
    B(f, S * 0.26, S * 0.30, t, S * 0.56, col, z)
    B(f, S * 0.42, S * 0.30, t, S * 0.56, col, z)
    B(f, S * 0.58, S * 0.30, t, S * 0.56, col, z)
    B(f, S * 0.74, S * 0.30, t, S * 0.56, col, z)
    B(f, S * 0.26, S * 0.80, S * 0.49, t, col, z)
end

IconBuilders.Up = function(f, S, col, z)
    Draw.Tri(f, S * 0.60, S * 0.60, col, z, 270, S / 2, S * 0.5)
end

IconBuilders.Down = function(f, S, col, z)
    Draw.Tri(f, S * 0.60, S * 0.60, col, z, 90, S / 2, S * 0.5)
end

IconBuilders.Shuffle = function(f, S, col, z)
    local t = math.max(2, S * 0.09)
    local bl = S * 0.60
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, bl, 0, t), AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, S * 0.16, 0, S * 0.28), Rotation = 26, ZIndex = z,
    })
    Util.Create("Frame", {
        Parent = f, BackgroundColor3 = col, BorderSizePixel = 0,
        Size = UDim2.new(0, bl, 0, t), AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, S * 0.16, 0, S * 0.72), Rotation = -26, ZIndex = z,
    })
    Draw.Tri(f, S * 0.20, S * 0.26, col, z, 0, S * 0.88, S * 0.22)
    Draw.Tri(f, S * 0.20, S * 0.26, col, z, 0, S * 0.88, S * 0.78)
end

IconBuilders.Repeat = function(f, S, col, z)
    local t = math.max(2, S * 0.10)
    local o = S * 0.12
    local w = S * 0.76
    B(f, o, o, w, t, col, z)
    B(f, o, o + w - t, w, t, col, z)
    B(f, o + w - t, o + t, t, w - t * 2, col, z)
    B(f, o, o + t, t, S * 0.20, col, z)
    B(f, o, o + w - t - S * 0.20, t, S * 0.20, col, z)
    Draw.Tri(f, S * 0.24, S * 0.24, col, z, 90, S * 0.86, S * 0.5)
end

IconBuilders.RepeatOne = function(f, S, col, z)
    IconBuilders.Repeat(f, S, col, z)
    B(f, S * 0.44, S * 0.42, S * 0.10, S * 0.24, col, z)
end

local function makeIcon(parent, key, S, color, z)
    local asset = MusicUI.Assets[key]
    if type(asset) == "string" and asset ~= "" then
        return Util.Create("ImageLabel", {
            Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0, S, 0, S),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Image = asset, ImageColor3 = color, ZIndex = z or 10,
        })
    end
    local holder = Util.Create("Frame", {
        Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, S, 0, S),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        ZIndex = z or 10,
    })
    local builder = IconBuilders[key]
    if builder then pcall(builder, holder, S, color, z or 10) end
    return holder
end

local function paintIcon(icon, color)
    if not icon then return end
    if icon:IsA("ImageLabel") then
        icon.ImageColor3 = color
        return
    end
    for _, d in ipairs(icon:GetDescendants()) do
        if d:IsA("Frame") then
            pcall(function() d.BackgroundColor3 = color end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  通用控件：图标按钮 / 滑条
-- ═══════════════════════════════════════════════════════════════════
local function iconButton(parent, opts)
    local size    = opts.Size or 26
    local iconKey = opts.Icon or "Play"
    local color   = opts.Color or C(220, 220, 220)
    local accent  = opts.Accent
    local z       = opts.ZIndex or 12
    local box = Util.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = opts.Bg or C(40, 40, 55),
        BackgroundTransparency = opts.BgTransparency or 0.55,
        BorderSizePixel = 0,
        Size = UDim2.new(0, size, 0, size),
        Position = opts.Position or UDim2.new(0, 0, 0, 0),
        ZIndex = z,
    })
    local icon = makeIcon(box, iconKey, math.floor(size * (opts.IconScale or 0.56)), color, z + 1)
    local btn = Util.Create("TextButton", {
        Parent = box, BackgroundTransparency = 1, Text = "",
        Size = UDim2.new(1, 0, 1, 0), ZIndex = z + 3,
    })
    local state = {Active = opts.Active == true, HoverColor = opts.HoverColor, BaseColor = color}

    local function repaint()
        if state.Active and accent then
            paintIcon(icon, accent)
        else
            paintIcon(icon, state.Hover and color or color)
        end
    end

    btn.MouseEnter:Connect(function()
        state.Hover = true
        snd("Hover", 0.08)
        Util.Tween(box, {BackgroundTransparency = 0.25}, 0.15)
        if state.Active and accent then paintIcon(icon, accent) end
    end)
    btn.MouseLeave:Connect(function()
        state.Hover = false
        Util.Tween(box, {BackgroundTransparency = opts.BgTransparency or 0.55}, 0.15)
        if state.Active and accent then paintIcon(icon, accent) end
    end)
    btn.MouseButton1Click:Connect(function()
        snd("Click", 0.2)
        ripple(box, accent or color)
        safeCb(opts.Callback)
    end)

    local api = {}
    api.Frame = box
    api.Button = btn
    function api:SetIcon(key)
        if icon then icon:Destroy() end
        icon = makeIcon(box, key, math.floor(size * (opts.IconScale or 0.56)), color, z + 1)
        repaint()
    end
    function api:SetActive(on)
        state.Active = on and true or false
        if state.Active and accent then
            paintIcon(icon, accent)
            box.BackgroundColor3 = accent
            box.BackgroundTransparency = 0.72
        else
            paintIcon(icon, color)
            box.BackgroundColor3 = opts.Bg or C(40, 40, 55)
            box.BackgroundTransparency = opts.BgTransparency or 0.55
        end
    end
    function api:SetColor(c)
        color = c
        paintIcon(icon, color)
    end
    function api:SetVisible(v) box.Visible = v end
    if opts.Active then api:SetActive(true) end
    return api
end

-- 滑条（进度 / 音量）：支持点击与拖拽
local function makeSlider(parent, opts)
    local h        = opts.Height or 6
    local fillCol  = opts.Color or C(0, 200, 255)
    local knob     = opts.Knob ~= false
    local knobSize = opts.KnobSize or 12
    local track = Util.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = opts.TrackColor or C(60, 60, 85),
        BackgroundTransparency = opts.TrackTransparency or 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, h),
        Position = opts.Position or UDim2.new(0, 0, 0, 0),
        ClipsDescendants = false,
        ZIndex = opts.ZIndex or 12,
    })
    local fill = Util.Create("Frame", {
        Parent = track, BackgroundColor3 = fillCol, BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0), ZIndex = (opts.ZIndex or 12) + 1,
    })
    local buffer = nil
    if opts.ShowBuffer then
        buffer = Util.Create("Frame", {
            Parent = track, BackgroundColor3 = C(120, 120, 150), BackgroundTransparency = 0.6,
            BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0), ZIndex = (opts.ZIndex or 12) + 1,
        })
    end
    local knobFrame = nil
    if knob then
        knobFrame = Util.Create("Frame", {
            Parent = track, BackgroundColor3 = C(255, 255, 255), BorderSizePixel = 0,
            Size = UDim2.new(0, knobSize, 0, knobSize),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Visible = false, ZIndex = (opts.ZIndex or 12) + 3,
        })
    end
    local hit = Util.Create("TextButton", {
        Parent = track, BackgroundTransparency = 1, Text = "",
        Size = UDim2.new(1, 0, 1, math.max(10, h + 10)),
        Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        ZIndex = (opts.ZIndex or 12) + 4,
    })

    local value    = opts.Value or 0
    local dragging = false
    local onDrag   = opts.OnChange
    local onCommit = opts.OnCommit

    local function paint()
        fill.Size = UDim2.new(clamp01(value), 0, 1, 0)
        if knobFrame then knobFrame.Position = UDim2.new(clamp01(value), 0, 0.5, 0) end
    end
    paint()

    local function fromX(x)
        local abs, len = track.AbsolutePosition.X, track.AbsoluteSize.X
        if len <= 0 then return 0 end
        return clamp01((x - abs) / len)
    end

    hit.MouseButton1Down:Connect(function(x)
        dragging = true
        if knobFrame then knobFrame.Visible = true end
        value = fromX(x)
        paint()
        safeCb(onDrag, value, true)
    end)
    hit.MouseEnter:Connect(function()
        if knobFrame then knobFrame.Visible = true end
        Util.Tween(track, {BackgroundTransparency = 0.2}, 0.15)
    end)
    hit.MouseLeave:Connect(function()
        if not dragging and knobFrame then knobFrame.Visible = false end
        Util.Tween(track, {BackgroundTransparency = opts.TrackTransparency or 0.4}, 0.15)
    end)

    local connMove = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            value = fromX(input.Position.X)
            paint()
            safeCb(onDrag, value, true)
        end
    end)
    local connEnd = UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if knobFrame then knobFrame.Visible = false end
            safeCb(onCommit, value)
        end
    end)

    local api = {}
    api.Frame = track
    api.Dragging = function() return dragging end
    function api:Get() return value end
    function api:Set(v, silent)
        value = clamp01(v)
        paint()
        if not silent then safeCb(onDrag, value, false) end
    end
    function api:SetBuffer(v)
        if buffer then buffer.Size = UDim2.new(clamp01(v), 0, 1, 0) end
    end
    function api:SetColor(c)
        fillCol = c
        fill.BackgroundColor3 = c
    end
    function api:Destroy()
        pcall(function() connMove:Disconnect() end)
        pcall(function() connEnd:Disconnect() end)
        track:Destroy()
    end
    return api
end

-- ═══════════════════════════════════════════════════════════════════
--  封面（带占位）
-- ═══════════════════════════════════════════════════════════════════
local function makeCover(parent, size, z)
    local box = Util.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = C(35, 35, 55),
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
        Size = UDim2.new(0, size, 0, size),
        ClipsDescendants = true,
        ZIndex = z or 10,
    })
    local img = Util.Create("ImageLabel", {
        Parent = box, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), Image = "", ScaleType = Enum.ScaleType.Crop,
        ImageTransparency = 0, ZIndex = (z or 10) + 1,
    })
    local ph = Util.Create("Frame", {
        Parent = box, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, size * 0.44, 0, size * 0.44),
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        ZIndex = (z or 10) + 2,
    })
    local phIcon = makeIcon(ph, "Note", math.floor(size * 0.44), C(120, 120, 150), (z or 10) + 3)
    local grad = Util.Create("UIGradient", {
        Parent = box,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, C(70, 55, 120)),
            ColorSequenceKeypoint.new(1, C(25, 25, 45)),
        }),
        Rotation = 45,
    })
    -- 占位图（可整体替换）
    local placeholderAsset = MusicUI.Assets.Cover
    if type(placeholderAsset) == "string" and placeholderAsset ~= "" then
        img.Image = placeholderAsset
    end

    local api = {}
    api.Frame = box
    function api:Set(url)
        if type(url) == "string" and url ~= "" then
            img.Image = url
            ph.Visible = false
        else
            img.Image = (type(MusicUI.Assets.Cover) == "string") and MusicUI.Assets.Cover or ""
            ph.Visible = not (img.Image ~= "")
        end
    end
    function api:SetGradient(c1, c2, rot)
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, c1 or C(70, 55, 120)),
            ColorSequenceKeypoint.new(1, c2 or C(25, 25, 45)),
        })
        if rot then grad.Rotation = rot end
    end
    function api:SetSize(s)
        box.Size = UDim2.new(0, s, 0, s)
    end
    function api:SetVisible(v) box.Visible = v end
    return api
end

-- ═══════════════════════════════════════════════════════════════════
--  面板（互斥显示）
-- ═══════════════════════════════════════════════════════════════════
local function newPanel(self, body, name)
    local sf = Util.Create("ScrollingFrame", {
        Parent = body,
        Name = "Panel_" .. tostring(name),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = themeColor(self, "Accent"),
        Visible = false,
        ZIndex = 8,
    }, {
        Util.Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)}),
        Util.Create("UIPadding", {
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
            PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 6),
        }),
    })
    local layout = sf:FindFirstChildOfClass("UIListLayout")
    if layout then
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
        end)
    end
    local p = {Name = name, Frame = sf}
    function p:Show()
        for _, child in ipairs(body:GetChildren()) do
            if child:IsA("ScrollingFrame") then child.Visible = false end
        end
        sf.Visible = true
    end
    function p:Clear()
        for _, child in ipairs(sf:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
    end
    function p:Size() return sf.AbsoluteSize end
    return p
end

-- ═══════════════════════════════════════════════════════════════════
--  歌曲行
-- ═══════════════════════════════════════════════════════════════════
local function makeSongRow(self, parent, item, opts, z)
    local height   = opts.RowHeight or 58
    local accent   = themeColor(self, "Accent")
    local row = Util.Create("Frame", {
        Parent = parent,
        BackgroundColor3 = themeColor(self, "Control"),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height),
        ZIndex = z or 10,
    })
    local coverSize = height - 12
    local cover = makeCover(row, coverSize, (z or 10) + 1)
    cover.Frame.Position = UDim2.new(0, 6, 0, 6)
    if item.Cover then cover:Set(item.Cover) end

    local textX = coverSize + 16
    local titleL = Util.Create("TextLabel", {
        Parent = row, BackgroundTransparency = 1,
        Position = UDim2.new(0, textX, 0, 8),
        Size = UDim2.new(1, -(textX + 118), 0, 20),
        Font = Enum.Font.GothamSemibold,
        Text = item.Title or "(未知标题)",
        TextColor3 = themeColor(self, "Text"),
        TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = (z or 10) + 1,
    })
    local subL = Util.Create("TextLabel", {
        Parent = row, BackgroundTransparency = 1,
        Position = UDim2.new(0, textX, 0, 30),
        Size = UDim2.new(1, -(textX + 118), 0, 18),
        Font = Enum.Font.Gotham,
        Text = item.Sub or item.Artist or "",
        TextColor3 = themeColor(self, "TextFaint"),
        TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = (z or 10) + 1,
    })
    local durL = nil
    if opts.ShowDuration ~= false then
        durL = Util.Create("TextLabel", {
            Parent = row, BackgroundTransparency = 1,
            Position = UDim2.new(1, -108, 0, 0),
            Size = UDim2.new(0, 46, 1, 0),
            Font = Enum.Font.Gotham,
            Text = item.Duration and (type(item.Duration) == "number" and fmtTime(item.Duration) or tostring(item.Duration)) or "",
            TextColor3 = themeColor(self, "TextFaint"),
            TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
            ZIndex = (z or 10) + 1,
        })
    end

    local favBtn = nil
    if opts.ShowFav ~= false then
        favBtn = iconButton(row, {
            Size = 24, Icon = item.Fav and "HeartOn" or "Heart",
            Color = item.Fav and accent or themeColor(self, "TextFaint"),
            Accent = accent, IconScale = 0.62,
            Position = UDim2.new(1, -58, 0.5, 0),
            ZIndex = (z or 10) + 2,
            Callback = function()
                local on = not (item.Fav == true)
                item.Fav = on
                favBtn:SetIcon(on and "HeartOn" or "Heart")
                favBtn:SetColor(on and accent or themeColor(self, "TextFaint"))
                safeCb(opts.OnFav, item, on)
            end,
        })
        favBtn.Frame.AnchorPoint = Vector2.new(0, 0.5)
    end

    local moreBtn = nil
    if opts.OnMenu then
        moreBtn = iconButton(row, {
            Size = 24, Icon = "Plus", Color = themeColor(self, "TextFaint"),
            Accent = accent, IconScale = 0.55,
            Position = UDim2.new(1, -28, 0.5, 0),
            ZIndex = (z or 10) + 2,
            Callback = function() safeCb(opts.OnMenu, item) end,
        })
        moreBtn.Frame.AnchorPoint = Vector2.new(0, 0.5)
    end

    local hit = Util.Create("TextButton", {
        Parent = row, BackgroundTransparency = 1, Text = "",
        Size = UDim2.new(1, -100, 1, 0), ZIndex = (z or 10) + 5,
    })
    hit.MouseEnter:Connect(function()
        Util.Tween(row, {BackgroundTransparency = 0.1}, 0.15)
        snd("Hover", 0.06)
    end)
    hit.MouseLeave:Connect(function()
        if not item._Active then
            Util.Tween(row, {BackgroundTransparency = 0.35}, 0.15)
        end
    end)
    hit.MouseButton1Click:Connect(function()
        snd("Click", 0.25)
        ripple(row, accent)
        safeCb(opts.OnSelect, item)
    end)

    local api = {Frame = row, Item = item}
    function api:SetActive(on)
        item._Active = on and true or false
        row.BackgroundTransparency = on and 0.05 or 0.35
        titleL.TextColor3 = on and accent or themeColor(self, "Text")
        if on then
            local bar = row:FindFirstChild("QActiveBar")
            if not bar then
                bar = Util.Create("Frame", {
                    Name = "QActiveBar", Parent = row,
                    BackgroundColor3 = accent, BorderSizePixel = 0,
                    Size = UDim2.new(0, 3, 1, -10),
                    Position = UDim2.new(0, 0, 0, 5),
                    ZIndex = (z or 10) + 6,
                })
            end
            bar.Visible = true
        else
            local bar = row:FindFirstChild("QActiveBar")
            if bar then bar.Visible = false end
        end
    end
    function api:SetFav(on)
        item.Fav = on and true or false
        if favBtn then
            favBtn:SetIcon(on and "HeartOn" or "Heart")
            favBtn:SetColor(on and accent or themeColor(self, "TextFaint"))
            favBtn:SetActive(on)
        end
    end
    function api:SetSub(t) subL.Text = tostring(t or "") end
    function api:SetDuration(d)
        if durL then
            durL.Text = (type(d) == "number") and fmtTime(d) or tostring(d or "")
        end
    end
    if item.Fav then api:SetFav(true) end
    return api
end

-- ═══════════════════════════════════════════════════════════════════
--  音乐页构建器（同时供 AddMusicTab 与 CreateMusicWindow 使用）
-- ═══════════════════════════════════════════════════════════════════
local function buildMusicPage(win, page, opts)
    opts = opts or {}
    local accent = themeColor(win, "Accent")

    local header = Util.Create("Frame", {
        Parent = page, Name = "MusicHeader",
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.new(0, 0, 0, 0),
        ZIndex = 7,
    }, {
        Util.Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8)}),
    })
    local headerLayout = header:FindFirstChildOfClass("UIListLayout")

    local body = Util.Create("Frame", {
        Parent = page, Name = "MusicBody",
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        ClipsDescendants = true,
        ZIndex = 7,
    })

    local bgImage = nil
    if type(MusicUI.Assets.Bg) == "string" and MusicUI.Assets.Bg ~= "" then
        bgImage = Util.Create("ImageLabel", {
            Parent = page, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 1, 0), Image = MusicUI.Assets.Bg,
            ImageTransparency = 0.85, ScaleType = Enum.ScaleType.Crop, ZIndex = 6,
        })
    end

    local mt = {}
    mt.Page   = page
    mt.Header = header
    mt.Body   = body
    mt.Panels = {}
    mt.PanelOrder = {}
    mt._Current = nil

    local function relayout()
        local h = (headerLayout and headerLayout.AbsoluteContentSize.Y) or 0
        local gap = (h > 0) and 10 or 0
        body.Position = UDim2.new(0, 0, 0, h + gap)
        body.Size = UDim2.new(1, 0, 1, -(h + gap))
    end
    if headerLayout then
        headerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(relayout)
    end
    relayout()

    -- ── 面板 ────────────────────────────────────────────────────
    function mt:AddPanel(name)
        local p = newPanel(win, body, name)
        mt.Panels[name] = p
        mt.PanelOrder[#mt.PanelOrder + 1] = name
        if not mt._Current then
            mt._Current = name
            p:Show()
        end
        return p
    end
    function mt:ShowPanel(name)
        local p = mt.Panels[name]
        if not p then return end
        mt._Current = name
        p:Show()
    end
    function mt:CurrentPanel() return mt._Current end
    function mt:GetPanel(name) return mt.Panels[name] end

    local function targetPanel(name)
        if name and mt.Panels[name] then return mt.Panels[name].Frame end
        if mt._Current and mt.Panels[mt._Current] then return mt.Panels[mt._Current].Frame end
        local p = mt:AddPanel("Main")
        return p.Frame
    end

    -- ── 播放卡片 ────────────────────────────────────────────────
    function mt:AddMusicPlayer(o)
        o = o or {}
        local H = o.Height or 132
        local card = Util.Create("Frame", {
            Parent = header,
            BackgroundColor3 = themeColor(win, "Section"),
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, H),
            LayoutOrder = o.LayoutOrder or 1,
            ZIndex = 8,
        })
        Util.Create("UIGradient", {
            Parent = card,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, C(45, 35, 80)),
                ColorSequenceKeypoint.new(1, C(22, 22, 40)),
            }),
            Rotation = 90,
        })

        local coverSize = H - 32
        local cover = makeCover(card, coverSize, 9)
        cover.Frame.Position = UDim2.new(0, 14, 0, 16)

        local tx = coverSize + 28
        local titleL = Util.Create("TextLabel", {
            Parent = card, BackgroundTransparency = 1,
            Position = UDim2.new(0, tx, 0, 12),
            Size = UDim2.new(1, -(tx + 16), 0, 22),
            Font = Enum.Font.GothamBold, Text = "未播放",
            TextColor3 = themeColor(win, "Text"), TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9,
        })
        local artistL = Util.Create("TextLabel", {
            Parent = card, BackgroundTransparency = 1,
            Position = UDim2.new(0, tx, 0, 33),
            Size = UDim2.new(1, -(tx + 16), 0, 18),
            Font = Enum.Font.Gotham, Text = "—",
            TextColor3 = themeColor(win, "TextDim"), TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9,
        })

        -- 控制条
        local cy = 58
        local btnY = UDim2.new(0, tx, 0, cy)
        local cur = 0
        local dur = 0
        local playing = false
        local volume = o.Volume or 0.7
        local shuffleOn = false
        local repeatMode = o.RepeatMode or "off"   -- off / all / one

        local likeBtn = iconButton(card, {
            Size = 24, Icon = "Heart", Color = themeColor(win, "TextFaint"),
            Accent = C(255, 80, 110), IconScale = 0.62,
            Position = UDim2.new(0, tx, 0, cy + 2), ZIndex = 10,
            Callback = function()
                local on = not (likeBtn._on == true)
                likeBtn._on = on
                likeBtn:SetIcon(on and "HeartOn" or "Heart")
                likeBtn:SetColor(on and C(255, 80, 110) or themeColor(win, "TextFaint"))
                likeBtn:SetActive(on)
                safeCb(o.OnLike, on)
            end,
        })

        local prevBtn = iconButton(card, {
            Size = 26, Icon = "Prev", Color = themeColor(win, "TextBright"),
            Accent = accent, IconScale = 0.60,
            Position = UDim2.new(0, tx + 32, 0, cy + 1), ZIndex = 10,
            Callback = function() safeCb(o.OnPrev) end,
        })

        local playBtn = iconButton(card, {
            Size = 32, Icon = "Play", Color = themeColor(win, "Text"),
            Accent = accent, IconScale = 0.62, Bg = accent, BgTransparency = 0.85,
            Position = UDim2.new(0, tx + 66, 0, cy - 2), ZIndex = 10,
            Callback = function()
                safeCb(o.OnPlayPause, not playing)
            end,
        })

        local nextBtn = iconButton(card, {
            Size = 26, Icon = "Next", Color = themeColor(win, "TextBright"),
            Accent = accent, IconScale = 0.60,
            Position = UDim2.new(0, tx + 106, 0, cy + 1), ZIndex = 10,
            Callback = function() safeCb(o.OnNext) end,
        })

        local shuffleBtn = nil
        if o.ShowShuffle ~= false then
            shuffleBtn = iconButton(card, {
                Size = 22, Icon = "Shuffle", Color = themeColor(win, "TextFaint"),
                Accent = accent, IconScale = 0.66,
                Position = UDim2.new(0, tx + 142, 0, cy + 3), ZIndex = 10,
                Callback = function()
                    shuffleOn = not shuffleOn
                    shuffleBtn:SetActive(shuffleOn)
                    safeCb(o.OnShuffle, shuffleOn)
                end,
            })
        end

        local repeatBtn = nil
        if o.ShowRepeat ~= false then
            repeatBtn = iconButton(card, {
                Size = 22, Icon = "Repeat", Color = themeColor(win, "TextFaint"),
                Accent = accent, IconScale = 0.66,
                Position = UDim2.new(0, tx + 170, 0, cy + 3), ZIndex = 10,
                Callback = function()
                    if repeatMode == "off" then repeatMode = "all"
                    elseif repeatMode == "all" then repeatMode = "one"
                    else repeatMode = "off" end
                    repeatBtn:SetIcon(repeatMode == "one" and "RepeatOne" or "Repeat")
                    repeatBtn:SetActive(repeatMode ~= "off")
                    safeCb(o.OnRepeat, repeatMode)
                end,
            })
        end

        -- 音量
        local volIcon = makeIcon(card, "Volume", 16, themeColor(win, "TextFaint"), 10)
        volIcon.AnchorPoint = Vector2.new(1, 0.5)
        volIcon.Position = UDim2.new(1, -92, 0, cy + 13)
        local volSlider = makeSlider(card, {
            Position = UDim2.new(1, -86, 0, cy + 13),
            Size = nil, Height = 4, Value = volume,
            Color = accent, Knob = true, KnobSize = 10,
            ZIndex = 10,
            OnChange = function(v)
                volume = v
                safeCb(o.OnVolume, v)
            end,
        })
        volSlider.Frame.Size = UDim2.new(0, 78, 0, 4)
        volSlider.Frame.AnchorPoint = Vector2.new(0, 0.5)

        -- 进度
        local progY = H - 34
        local prog = makeSlider(card, {
            Position = UDim2.new(0, 14, 0, progY),
            Height = 6, Value = 0, Color = accent,
            Knob = true, KnobSize = 12, ShowBuffer = true, ZIndex = 10,
            OnCommit = function(v)
                if dur > 0 then safeCb(o.OnSeek, v * dur) end
            end,
        })
        prog.Frame.Size = UDim2.new(1, -128, 0, 6)

        local timeL = Util.Create("TextLabel", {
            Parent = card, BackgroundTransparency = 1,
            Position = UDim2.new(1, -110, 0, progY - 8),
            Size = UDim2.new(0, 100, 0, 22),
            Font = Enum.Font.Gotham, Text = "00:00 / 00:00",
            TextColor3 = themeColor(win, "TextDim"), TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 10,
        })

        local statusL = Util.Create("TextLabel", {
            Parent = card, BackgroundTransparency = 1,
            Position = UDim2.new(0, 14, 0, H - 18),
            Size = UDim2.new(1, -28, 0, 14),
            Font = Enum.Font.Gotham, Text = "",
            TextColor3 = accent, TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10,
        })

        local api = {}
        api.Frame = card
        function api:SetSong(song)
            if type(song) ~= "table" then return end
            titleL.Text = tostring(song.Title or song.Name or "未知标题")
            artistL.Text = tostring(song.Artist or song.Sub or "未知歌手")
            cover:Set(song.Cover)
            dur = tonumber(song.Duration) or 0
            cur = 0
            prog:Set(0, true)
            timeL.Text = "00:00 / " .. fmtTime(dur)
            api:SetLiked(song.Fav == true)
        end
        function api:SetPlaying(on)
            playing = on and true or false
            playBtn:SetIcon(playing and "Pause" or "Play")
        end
        function api:IsPlaying() return playing end
        function api:SetProgress(c, d)
            cur = tonumber(c) or 0
            if d then dur = tonumber(d) or dur end
            if dur <= 0 then
                prog:Set(0, true)
                timeL.Text = fmtTime(cur) .. " / 00:00"
                return
            end
            prog:Set(cur / dur, true)
            timeL.Text = fmtTime(cur) .. " / " .. fmtTime(dur)
        end
        function api:SetBuffered(v) prog:SetBuffer(v) end
        function api:SetStatus(t) statusL.Text = tostring(t or "") end
        function api:SetLiked(on)
            likeBtn._on = on and true or false
            likeBtn:SetIcon(on and "HeartOn" or "Heart")
            likeBtn:SetColor(on and C(255, 80, 110) or themeColor(win, "TextFaint"))
            likeBtn:SetActive(on)
        end
        function api:SetVolume(v)
            volume = clamp01(v)
            volSlider:Set(volume, true)
        end
        function api:GetVolume() return volume end
        function api:SetShuffle(on)
            shuffleOn = on and true or false
            if shuffleBtn then shuffleBtn:SetActive(shuffleOn) end
        end
        function api:SetRepeatMode(mode)
            repeatMode = mode or "off"
            if repeatBtn then
                repeatBtn:SetIcon(repeatMode == "one" and "RepeatOne" or "Repeat")
                repeatBtn:SetActive(repeatMode ~= "off")
            end
        end
        function api:SetCover(url) cover:Set(url) end
        function api:Duration() return dur end
        function api:Position() return cur end
        return api
    end

    -- ── 搜索框 ──────────────────────────────────────────────────
    function mt:AddSearchBox(o)
        o = o or {}
        local H = o.Height or 36
        local box = Util.Create("Frame", {
            Parent = header,
            BackgroundColor3 = themeColor(win, "Control"),
            BackgroundTransparency = 0.25,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, H),
            LayoutOrder = o.LayoutOrder or 2,
            ZIndex = 8,
        })
        local sIcon = makeIcon(box, "Search", 18, themeColor(win, "TextFaint"), 9)
        sIcon.AnchorPoint = Vector2.new(0, 0.5)
        sIcon.Position = UDim2.new(0, 10, 0.5, 0)

        local input = Util.Create("TextBox", {
            Parent = box, BackgroundTransparency = 1,
            Position = UDim2.new(0, 36, 0, 0),
            Size = UDim2.new(1, -76, 1, 0),
            Font = Enum.Font.Gotham,
            PlaceholderText = o.Placeholder or "搜索歌曲 / 歌手 / 专辑",
            PlaceholderColor3 = themeColor(win, "TextFaint"),
            Text = o.Default or "",
            TextColor3 = themeColor(win, "Text"),
            TextSize = 13, ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 9,
        })

        local clearBtn = iconButton(box, {
            Size = 22, Icon = "Clear", Color = themeColor(win, "TextFaint"),
            Accent = accent, IconScale = 0.52, BgTransparency = 1,
            Position = UDim2.new(1, -28, 0.5, 0), ZIndex = 10,
            Callback = function()
                input.Text = ""
                safeCb(o.OnClear)
                safeCb(o.OnSearch, "")
            end,
        })
        clearBtn.Frame.AnchorPoint = Vector2.new(0, 0.5)
        clearBtn:SetVisible(false)

        local timer = 0
        local api = {}
        api.Frame = box
        function api:Get() return input.Text end
        function api:Set(t)
            input.Text = tostring(t or "")
            clearBtn:SetVisible(input.Text ~= "")
        end
        function api:Focus() input:CaptureFocus() end
        function api:SetPlaceholder(t) input.PlaceholderText = tostring(t or "") end

        input:GetPropertyChangedSignal("Text"):Connect(function()
            clearBtn:SetVisible(input.Text ~= "")
            local delay = tonumber(o.Debounce) or 0.35
            if delay <= 0 then
                safeCb(o.OnSearch, input.Text)
                return
            end
            local stamp = tick()
            timer = stamp
            task.delay(delay, function()
                if timer == stamp then safeCb(o.OnSearch, input.Text) end
            end)
        end)
        input.FocusLost:Connect(function(enter)
            if enter then safeCb(o.OnSearch, input.Text) end
        end)
        return api
    end

    -- ── 二级分类条 ──────────────────────────────────────────────
    function mt:AddSubTabs(list, callback, o)
        o = o or {}
        local H = o.Height or 34
        local bar = Util.Create("Frame", {
            Parent = header,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, H),
            LayoutOrder = o.LayoutOrder or 3,
            ZIndex = 8,
        })
        local layout = Util.Create("UIListLayout", {
            Parent = bar, FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8),
        })
        local btns = {}
        local active = nil

        local function select(name, silent)
            for _, b in ipairs(btns) do
                local on = (b.Name == name)
                b.Label.TextColor3 = on and themeColor(win, "Text") or themeColor(win, "TextFaint")
                Util.Tween(b.Frame, {BackgroundTransparency = on and 0.05 or 0.6}, 0.18)
                b.Bar.Visible = on
            end
            active = name
            if not silent then safeCb(callback, name) end
        end

        for i, name in ipairs(list or {}) do
            local f = Util.Create("Frame", {
                Parent = bar,
                BackgroundColor3 = themeColor(win, "Control"),
                BackgroundTransparency = 0.6,
                BorderSizePixel = 0,
                Size = UDim2.new(0, math.max(58, #tostring(name) * 14 + 28), 1, 0),
                ZIndex = 9,
            })
            local lbl = Util.Create("TextLabel", {
                Parent = f, BackgroundTransparency = 1,
                Size = UDim2.new(1, -18, 1, 0), Position = UDim2.new(0, 9, 0, 0),
                Font = Enum.Font.GothamSemibold, Text = tostring(name),
                TextColor3 = themeColor(win, "TextFaint"), TextSize = 13,
                ZIndex = 10,
            })
            local bar2 = Util.Create("Frame", {
                Parent = f, BackgroundColor3 = accent, BorderSizePixel = 0,
                Size = UDim2.new(0.7, 0, 0, 2),
                Position = UDim2.new(0.15, 0, 1, -3), Visible = false, ZIndex = 10,
            })
            local badge = Util.Create("TextLabel", {
                Parent = f, BackgroundColor3 = accent, BorderSizePixel = 0,
                Size = UDim2.new(0, 18, 0, 16),
                Position = UDim2.new(1, -20, 0, 3),
                Font = Enum.Font.GothamBold, Text = "", TextColor3 = C(255, 255, 255),
                TextSize = 10, Visible = false, ZIndex = 11,
            })
            local hit = Util.Create("TextButton", {
                Parent = f, BackgroundTransparency = 1, Text = "",
                Size = UDim2.new(1, 0, 1, 0), ZIndex = 12,
            })
            local entry = {Name = tostring(name), Frame = f, Label = lbl, Bar = bar2, Badge = badge}
            hit.MouseButton1Click:Connect(function()
                snd("Click", 0.2)
                ripple(f, accent)
                select(entry.Name)
            end)
            btns[#btns + 1] = entry
        end

        local api = {}
        api.Frame = bar
        function api:Select(name) select(name) end
        function api:SelectSilent(name) select(name, true) end
        function api:Get() return active end
        function api:SetBadge(name, n)
            for _, b in ipairs(btns) do
                if b.Name == tostring(name) then
                    n = tonumber(n)
                    b.Badge.Visible = (n ~= nil and n > 0)
                    if n and n > 0 then
                        b.Badge.Text = (n > 99) and "99+" or tostring(n)
                    end
                end
            end
        end
        if list and #list > 0 then select(tostring(list[1]), true) end
        return api
    end

    -- ── 标签条（分类筛选） ──────────────────────────────────────
    function mt:AddChipBar(o)
        o = o or {}
        local items = o.Items or {}
        local bar = Util.Create("ScrollingFrame", {
            Parent = header,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, o.Height or 32),
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 0,
            ScrollingDirection = Enum.ScrollingDirection.X,
            LayoutOrder = o.LayoutOrder or 4,
            ZIndex = 8,
        }, {
            Util.Create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
            }),
        })
        local chips = {}
        local activeSet = {}
        local api = {}
        api.Frame = bar
        function api:Set(list)
            for _, c in ipairs(chips) do c.Frame:Destroy() end
            chips = {}
            for _, name in ipairs(list or {}) do
                local f = Util.Create("Frame", {
                    Parent = bar,
                    BackgroundColor3 = themeColor(win, "Control"),
                    BackgroundTransparency = 0.55, BorderSizePixel = 0,
                    Size = UDim2.new(0, #tostring(name) * 12 + 24, 0, 26),
                    ZIndex = 9,
                })
                local lbl = Util.Create("TextLabel", {
                    Parent = f, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
                    Font = Enum.Font.Gotham, Text = tostring(name),
                    TextColor3 = themeColor(win, "TextDim"), TextSize = 12, ZIndex = 10,
                })
                local hit = Util.Create("TextButton", {
                    Parent = f, BackgroundTransparency = 1, Text = "",
                    Size = UDim2.new(1, 0, 1, 0), ZIndex = 11,
                })
                local chip = {Name = tostring(name), Frame = f, Label = lbl, On = false}
                hit.MouseButton1Click:Connect(function()
                    chip.On = not chip.On
                    activeSet[chip.Name] = chip.On and true or nil
                    Util.Tween(f, {BackgroundTransparency = chip.On and 0.05 or 0.55}, 0.15)
                    lbl.TextColor3 = chip.On and accent or themeColor(win, "TextDim")
                    snd("Click", 0.15)
                    local picked = {}
                    for k in pairs(activeSet) do picked[#picked + 1] = k end
                    safeCb(o.OnChange, picked, chip.Name, chip.On)
                end)
                chips[#chips + 1] = chip
            end
            task.defer(function()
                local l = bar:FindFirstChildOfClass("UIListLayout")
                if l then bar.CanvasSize = UDim2.new(0, l.AbsoluteContentSize.X + 8, 0, 0) end
            end)
        end
        function api:GetActive()
            local picked = {}
            for k in pairs(activeSet) do picked[#picked + 1] = k end
            return picked
        end
        function api:Clear()
            for _, c in ipairs(chips) do
                c.On = false
                c.Frame.BackgroundTransparency = 0.55
                c.Label.TextColor3 = themeColor(win, "TextDim")
            end
            activeSet = {}
        end
        api:Set(items)
        return api
    end

    -- ── 歌曲列表 ────────────────────────────────────────────────
    function mt:AddSongList(o)
        o = o or {}
        local panel = mt.Panels[o.Panel] or mt:AddPanel(o.Panel or o.Name or "Songs")
        local host = panel.Frame
        local rows = {}
        local active = nil
        local emptyText = o.EmptyText or "暂无歌曲"

        panel:Clear()

        local loading = Util.Create("TextLabel", {
            Parent = host, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 30),
            Font = Enum.Font.Gotham, Text = "加载中…",
            TextColor3 = themeColor(win, "TextFaint"), TextSize = 13,
            Visible = false, ZIndex = 9,
        })
        local empty = Util.Create("TextLabel", {
            Parent = host, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 60),
            Font = Enum.Font.Gotham, Text = emptyText,
            TextColor3 = themeColor(win, "TextFaint"), TextSize = 13,
            Visible = true, ZIndex = 9,
        })

        local function syncEmpty()
            empty.Visible = (#rows == 0) and not loading.Visible
        end

        local api = {}
        api.Panel = panel
        api.Frame = host

        function api:Clear()
            for _, r in ipairs(rows) do r.Frame:Destroy() end
            rows = {}
            active = nil
            syncEmpty()
        end
        function api:Add(item, index)
            local pos = index or (#rows + 1)
            local row = makeSongRow(win, host, item, {
                RowHeight = o.RowHeight, ShowFav = o.ShowFav,
                ShowDuration = o.ShowDuration, OnMenu = o.OnMenu,
                OnSelect = function(it) safeCb(o.OnSelect, it) end,
                OnFav = function(it, on) safeCb(o.OnFav, it, on) end,
            }, 10)
            row.Frame.LayoutOrder = pos
            table.insert(rows, pos, row)
            if active and item.Id == active then row:SetActive(true) end
            syncEmpty()
            return row
        end
        function api:Set(list)
            api:Clear()
            for i, it in ipairs(list or {}) do api:Add(it, i) end
        end
        function api:Remove(id)
            for i = #rows, 1, -1 do
                if rows[i].Item.Id == id then
                    rows[i].Frame:Destroy()
                    table.remove(rows, i)
                end
            end
            syncEmpty()
        end
        function api:SetActive(id)
            active = id
            for _, r in ipairs(rows) do
                r:SetActive(r.Item.Id == id)
            end
        end
        function api:SetFav(id, on)
            for _, r in ipairs(rows) do
                if r.Item.Id == id then r:SetFav(on) end
            end
        end
        function api:SetSub(id, t)
            for _, r in ipairs(rows) do
                if r.Item.Id == id then r:SetSub(t) end
            end
        end
        function api:SetLoading(on)
            loading.Visible = on and true or false
            syncEmpty()
            if on then loading.Text = o.LoadingText or "加载中…" end
        end
        function api:SetEmptyText(t)
            emptyText = tostring(t or "")
            empty.Text = emptyText
        end
        function api:Count() return #rows end
        function api:Items()
            local out = {}
            for _, r in ipairs(rows) do out[#out + 1] = r.Item end
            return out
        end
        function api:Show() mt:ShowPanel(panel.Name) end
        syncEmpty()
        return api
    end

    -- ── 歌词面板 ────────────────────────────────────────────────
    function mt:AddLyricPanel(o)
        o = o or {}
        local panel = mt.Panels[o.Panel] or mt:AddPanel(o.Panel or "Lyrics")
        panel:Clear()
        local host = panel.Frame
        local lines = {}
        local curIdx = 0
        local api = {}
        api.Panel = panel

        function api:Clear()
            for _, l in ipairs(host:GetChildren()) do
                if not l:IsA("UIListLayout") and not l:IsA("UIPadding") then l:Destroy() end
            end
            lines = {}
            curIdx = 0
        end
        function api:Set(list)
            api:Clear()
            for _, ln in ipairs(list or {}) do
                local t = tonumber(ln.t) or 0
                local lbl = Util.Create("TextLabel", {
                    Parent = host, BackgroundTransparency = 1,
                    Size = UDim2.new(1, -20, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    Font = Enum.Font.Gotham, Text = tostring(ln.text or ""),
                    TextColor3 = themeColor(win, "TextFaint"),
                    TextSize = o.TextSize or 14,
                    TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center,
                    ZIndex = 9,
                })
                if o.OnLineClick then
                    local b = Util.Create("TextButton", {
                        Parent = lbl, BackgroundTransparency = 1, Text = "",
                        Size = UDim2.new(1, 0, 1, 0), ZIndex = 10,
                    })
                    b.MouseButton1Click:Connect(function() safeCb(o.OnLineClick, t, ln) end)
                end
                lines[#lines + 1] = {t = t, Label = lbl}
            end
        end
        function api:Seek(sec)
            sec = tonumber(sec) or 0
            local idx = 0
            for i, ln in ipairs(lines) do
                if ln.t <= sec then idx = i else break end
            end
            if idx == curIdx then return end
            curIdx = idx
            for i, ln in ipairs(lines) do
                if i == idx then
                    ln.Label.TextColor3 = accent
                    ln.Label.Font = Enum.Font.GothamBold
                    ln.Label.TextSize = (o.TextSize or 14) + 2
                else
                    ln.Label.TextColor3 = themeColor(win, "TextFaint")
                    ln.Label.Font = Enum.Font.Gotham
                    ln.Label.TextSize = (o.TextSize or 14)
                end
            end
            if o.AutoScroll ~= false and idx > 0 then
                local target = lines[idx].Label
                task.defer(function()
                    if host and host.Parent then
                        host.CanvasPosition = Vector2.new(0, math.max(0, target.AbsolutePosition.Y - host.AbsolutePosition.Y - host.AbsoluteSize.Y / 2 + 20))
                    end
                end)
            end
        end
        function api:Show() mt:ShowPanel(panel.Name) end
        return api
    end

    -- ── 播放队列 ────────────────────────────────────────────────
    function mt:AddQueue(o)
        o = o or {}
        local panel = mt.Panels[o.Panel] or mt:AddPanel(o.Panel or "Queue")
        panel:Clear()
        local host = panel.Frame
        local rows = {}
        local api = {}
        api.Panel = panel

        local function rebuild()
            for _, r in ipairs(rows) do r:Destroy() end
            rows = {}
            for i, it in ipairs(api._items or {}) do
                local row = Util.Create("Frame", {
                    Parent = host,
                    BackgroundColor3 = themeColor(win, "Control"),
                    BackgroundTransparency = 0.35, BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, ZIndex = 9,
                })
                local lbl = Util.Create("TextLabel", {
                    Parent = row, BackgroundTransparency = 1,
                    Position = UDim2.new(0, 12, 0, 0),
                    Size = UDim2.new(1, -140, 1, 0),
                    Font = Enum.Font.Gotham, Text = tostring(i) .. ". " .. tostring(it.Title or ""),
                    TextColor3 = themeColor(win, "Text"), TextSize = 13,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 10,
                })
                local hit = Util.Create("TextButton", {
                    Parent = row, BackgroundTransparency = 1, Text = "",
                    Size = UDim2.new(1, -100, 1, 0), ZIndex = 11,
                })
                hit.MouseButton1Click:Connect(function() safeCb(o.OnSelect, it, i) end)
                iconButton(row, {
                    Size = 20, Icon = "Up", Color = themeColor(win, "TextFaint"),
                    Accent = accent, IconScale = 0.6, BgTransparency = 1,
                    Position = UDim2.new(1, -84, 0.5, 0), ZIndex = 12,
                    Callback = function() safeCb(o.OnMove, i, -1) end,
                }).Frame.AnchorPoint = Vector2.new(0, 0.5)
                iconButton(row, {
                    Size = 20, Icon = "Down", Color = themeColor(win, "TextFaint"),
                    Accent = accent, IconScale = 0.6, BgTransparency = 1,
                    Position = UDim2.new(1, -60, 0.5, 0), ZIndex = 12,
                    Callback = function() safeCb(o.OnMove, i, 1) end,
                }).Frame.AnchorPoint = Vector2.new(0, 0.5)
                iconButton(row, {
                    Size = 20, Icon = "Trash", Color = themeColor(win, "TextFaint"),
                    Accent = C(255, 90, 90), IconScale = 0.6, BgTransparency = 1,
                    Position = UDim2.new(1, -30, 0.5, 0), ZIndex = 12,
                    Callback = function() safeCb(o.OnRemove, it, i) end,
                }).Frame.AnchorPoint = Vector2.new(0, 0.5)
                if it.Id and it.Id == api._active then
                    row.BackgroundTransparency = 0.05
                    lbl.TextColor3 = accent
                end
                rows[#rows + 1] = row
            end
            if #rows == 0 then
                local e = Util.Create("TextLabel", {
                    Parent = host, BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 50),
                    Font = Enum.Font.Gotham, Text = o.EmptyText or "队列为空",
                    TextColor3 = themeColor(win, "TextFaint"), TextSize = 13, ZIndex = 9,
                })
                rows[#rows + 1] = e
            end
        end

        api._items = {}
        function api:Set(list)
            api._items = list or {}
            rebuild()
        end
        function api:Add(item)
            api._items[#api._items + 1] = item
            rebuild()
        end
        function api:Remove(id)
            local out = {}
            for _, it in ipairs(api._items) do
                if it.Id ~= id then out[#out + 1] = it end
            end
            api._items = out
            rebuild()
        end
        function api:Clear()
            api._items = {}
            rebuild()
        end
        function api:SetActive(id)
            api._active = id
            rebuild()
        end
        function api:Items() return api._items end
        function api:Show() mt:ShowPanel(panel.Name) end
        rebuild()
        return api
    end

    -- ── 封面宫格 ────────────────────────────────────────────────
    function mt:AddAlbumGrid(o)
        o = o or {}
        local panel = mt.Panels[o.Panel] or mt:AddPanel(o.Panel or "Albums")
        panel:Clear()
        local host = panel.Frame
        local grid = Util.Create("Frame", {
            Parent = host, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 9,
        })
        local gl = Util.Create("UIGridLayout", {
            Parent = grid,
            CellSize = UDim2.new(0, o.CellSize or 96, 0, (o.CellSize or 96) + 34),
            CellPadding = UDim2.new(0, 8, 0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        if type(o.Columns) == "number" and o.Columns > 0 then
            pcall(function() gl.FillDirectionMaxCells = o.Columns end)
        end
        local api = {}
        api.Panel = panel
        function api:Clear()
            for _, c in ipairs(grid:GetChildren()) do
                if not c:IsA("UIGridLayout") then c:Destroy() end
            end
        end
        function api:Add(item)
            local size = o.CellSize or 96
            local card = Util.Create("Frame", {
                Parent = grid, BackgroundTransparency = 1,
                Size = UDim2.new(0, size, 0, size + 34), ZIndex = 10,
            })
            local cv = makeCover(card, size, 11)
            if item.Cover then cv:Set(item.Cover) end
            Util.Create("TextLabel", {
                Parent = card, BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, size + 3), Size = UDim2.new(1, 0, 0, 16),
                Font = Enum.Font.GothamSemibold, Text = tostring(item.Title or ""),
                TextColor3 = themeColor(win, "Text"), TextSize = 12,
                TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11,
            })
            Util.Create("TextLabel", {
                Parent = card, BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, size + 18), Size = UDim2.new(1, 0, 0, 14),
                Font = Enum.Font.Gotham, Text = tostring(item.Sub or ""),
                TextColor3 = themeColor(win, "TextFaint"), TextSize = 11,
                TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11,
            })
            local hit = Util.Create("TextButton", {
                Parent = card, BackgroundTransparency = 1, Text = "",
                Size = UDim2.new(1, 0, 1, 0), ZIndex = 12,
            })
            hit.MouseButton1Click:Connect(function() safeCb(o.OnSelect, item) end)
            return card
        end
        function api:Set(list)
            api:Clear()
            for _, it in ipairs(list or {}) do api:Add(it) end
        end
        function api:Show() mt:ShowPanel(panel.Name) end
        return api
    end

    -- ── 标准控件直通 ────────────────────────────────────────────
    local function passthrough(method)
        return function(_, o2)
            o2 = o2 or {}
            local parent = targetPanel(o2.Panel)
            if type(win[method]) == "function" then
                return win[method](win, parent, o2)
            end
            return nil
        end
    end
    mt.AddSection    = passthrough("CreateSection")
    mt.AddButton     = passthrough("CreateButton")
    mt.AddToggle     = passthrough("CreateToggle")
    mt.AddDangerToggle = passthrough("CreateDangerToggle")
    mt.AddSlider     = passthrough("CreateSlider")
    mt.AddDropdown   = passthrough("CreateDropdown")
    mt.AddTextbox    = passthrough("CreateTextbox")
    mt.AddColorPicker= passthrough("CreateColorPicker")
    mt.AddKeybind    = passthrough("CreateKeybind")
    mt.AddLabel      = passthrough("CreateLabel")
    mt.AddParagraph  = passthrough("CreateParagraph")

    function mt:SetBackground(assetId, transparency)
        if bgImage then bgImage:Destroy() bgImage = nil end
        if type(assetId) == "string" and assetId ~= "" then
            bgImage = Util.Create("ImageLabel", {
                Parent = page, BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 1, 0), Image = assetId,
                ImageTransparency = transparency or 0.85,
                ScaleType = Enum.ScaleType.Crop, ZIndex = 6,
            })
        end
    end

    function mt:Relayout() relayout() end

    return mt
end

-- ═══════════════════════════════════════════════════════════════════
--  弹出式音乐窗口：选中 MUSIC 分支 → 隐藏主窗口 + 显示音乐窗口
--  关闭音乐窗口 / 切到其它页签 → 恢复主窗口（二者不并存）
-- ═══════════════════════════════════════════════════════════════════
local function showMainWindow(win, on)
    if win and win.MainFrame then
        pcall(function() win.MainFrame.Visible = on and true or false end)
    end
end

local function musicSelectHook(cls)
    if cls._MusicSelectHooked then return end
    local orig = cls.SelectTab
    if type(orig) ~= "function" then return end
    cls._MusicSelectHooked = true
    cls._MusicOrigSelectTab = orig

    -- 关闭音乐窗口 → 回到上一个普通页签并恢复主窗口
    function cls:_MusicRestore()
        if self._MusicOpenWindow then
            pcall(function() self._MusicOpenWindow:Hide() end)
            self._MusicOpenWindow = nil
        end
        showMainWindow(self, true)
        local back = self._MusicPrevTab
        if not (back and back.Page and back.Page.Parent) then
            for _, t in ipairs(self.Tabs or {}) do
                if not t.IsMusicTab then back = t break end
            end
        end
        if back and back.Page and back.Page.Parent then
            pcall(orig, self, back)
        end
        return true
    end

    function cls:SelectTab(tab)
        local prev = self.SelectedTab
        local res = orig(self, tab)
        if type(tab) == "table" and tab.IsMusicTab and tab._MusicWindow then
            if prev and not prev.IsMusicTab then self._MusicPrevTab = prev end
            showMainWindow(self, false)
            tab._MusicWindow:Show()
            self._MusicOpenWindow = tab._MusicWindow
        else
            showMainWindow(self, true)
            if self._MusicOpenWindow then
                pcall(function() self._MusicOpenWindow:Hide() end)
                self._MusicOpenWindow = nil
            end
        end
        return res
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  Window:AddMusicTab(opts)
-- ═══════════════════════════════════════════════════════════════════
local function installAddMusicTab(cls)
    function cls:AddMusicTab(options)
        options = options or {}
        local tabName = options.Name or "MUSIC"
        local tabIcon = options.Icon or "rbxassetid://6031280882"

        local tab = {Name = tabName, IconAsset = tabIcon, Elements = {}}

        local page = Util.Create("Frame", {
            Parent = self.ContentContainer,
            Name = "MusicPage_" .. tostring(tabName),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -20, 1, -20),
            Position = UDim2.new(0, 10, 0, 10),
            ClipsDescendants = true,
            Visible = false,
            ZIndex = 6,
        })

        tab.Page = page
        if type(self.CreateTabButton) == "function" then
            self:CreateTabButton(tab, {Name = tabName, Icon = tabIcon})
        end
        table.insert(self.Tabs, tab)

        -- 默认「弹出式」：内容构建进独立音乐窗口，主窗口不并存
        local popup = options.Popup ~= false
        local mt = nil
        if popup and type(self.CreateMusicWindow) == "function" then
            local okMw, mw = pcall(function()
                return self:CreateMusicWindow({
                    Title = options.Title or ("♪ " .. tostring(tabName)),
                    Size = options.WindowSize or UDim2.new(0, 390, 0, 560),
                    Position = options.WindowPosition,
                    OnClose = function()
                        if type(self._MusicRestore) == "function" then
                            pcall(self._MusicRestore, self)
                        else
                            showMainWindow(self, true)
                        end
                    end,
                })
            end)
            if okMw and mw then
                mw:Hide()
                tab._MusicWindow = mw
                mt = mw
            end
        end

        if not mt then
            popup = false
            mt = buildMusicPage(self, page, options)
        end

        -- 合并音乐 API 到 tab
        for k, v in pairs(mt) do
            if type(v) == "function" then tab[k] = v end
        end
        tab.Music = mt
        tab.IsMusicTab = true
        tab.IsPopupMusic = popup

        -- 手动开关（不经过页签点击）
        local musicWinRef = tab._MusicWindow
        local winSelf = self
        function tab:OpenMusic()
            if musicWinRef then
                showMainWindow(winSelf, false)
                musicWinRef:Show()
                winSelf._MusicOpenWindow = musicWinRef
            elseif tab.Page then
                tab.Page.Visible = true
            end
        end
        function tab:CloseMusic()
            if musicWinRef then
                musicWinRef:Hide()
                winSelf._MusicOpenWindow = nil
                if type(winSelf._MusicRestore) == "function" then
                    pcall(winSelf._MusicRestore, winSelf)
                else
                    showMainWindow(winSelf, true)
                end
            end
        end
        function tab:GetMusicWindow() return musicWinRef end

        -- 内联模式下沿用原有自动选中逻辑；弹出模式下不抢占首屏
        if not popup and #self.Tabs == 1
            and self.CurrentLayout ~= "Grid" and self.CurrentLayout ~= "Float" then
            if type(self.SelectTab) == "function" then self:SelectTab(tab) end
        end

        return tab
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  Window:CreateMusicWindow(opts) —— 独立浮动音乐窗口
-- ══════════════════════════════════════════════════════════════════
--  悬浮式音乐主窗口（v1.3）
--    与迷你播放条同一套视觉语言：半透明圆角面板 + 细描边 + 小尺寸图标键
--    + GothamMedium 13 / Gotham 11 字号 + 2~3px 细进度条。
--    自带 播放控制 / 搜索 / 分类 / 歌曲列表 / 队列 / 歌词，可直接 :Bind(engine)。
-- ══════════════════════════════════════════════════════════════════

-- 通用细滑块（进度条 / 音量条共用）
local function mkSlider(parent, o)
    o = o or {}
    local accent = themeColor(Q, "Accent")
    local track = Util.Create("Frame", {
        Parent = parent, BackgroundColor3 = themeColor(Q, "ControlHover"),
        BackgroundTransparency = 0.3, BorderSizePixel = 0,
        Size = o.Size or UDim2.new(1, 0, 0, 3),
        Position = o.Position or UDim2.new(0, 0, 0, 0),
        ZIndex = o.ZIndex or 20,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local fill = Util.Create("Frame", {
        Parent = track, BackgroundColor3 = accent, BorderSizePixel = 0,
        Size = UDim2.new(o.Ratio or 0, 0, 1, 0), ZIndex = (o.ZIndex or 20) + 1,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    -- 加宽热区，细条也好点
    local hit = Util.Create("TextButton", {
        Parent = parent, BackgroundTransparency = 1, Text = "",
        Size = o.HitSize or UDim2.new(1, 0, 0, 14),
        Position = o.Position and UDim2.new(o.Position.X.Scale, o.Position.X.Offset,
                                            o.Position.Y.Scale, o.Position.Y.Offset - 6)
                                or UDim2.new(0, 0, 0, -6),
        ZIndex = (o.ZIndex or 20) + 2, AutoButtonColor = false,
    })
    local api = { track = track, fill = fill, hit = hit, ratio = o.Ratio or 0 }
    function api:SetRatio(r)
        r = math.clamp(r or 0, 0, 1)
        self.ratio = r
        fill.Size = UDim2.new(r, 0, 1, 0)
    end
    local dragging = false
    local function fromX(px)
        local w = math.max(1, track.AbsoluteSize.X)
        local r = math.clamp((px - track.AbsolutePosition.X) / w, 0, 1)
        api:SetRatio(r)
        if o.OnChange then o.OnChange(r) end
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true fromX(i.Position.X)
        end
    end)
    hit.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            fromX(i.Position.X)
        end
    end)
    return api
end

-- 小图标键：anchor 右侧时 off 表示「右边缘距父级右边多少」
local function mkIconButton(parent, size, off, iconKey, iconSize, anchorRight, z)
    local accent = themeColor(Q, "Accent")
    local b = Util.Create("TextButton", {
        Parent = parent, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
        Size = UDim2.new(0, size, 0, size),
        Position = anchorRight and UDim2.new(1, off, 0.5, 0) or UDim2.new(0, off, 0.5, 0),
        AnchorPoint = anchorRight and Vector2.new(1, 0.5) or Vector2.new(0, 0.5),
        ZIndex = z or 30, AutoButtonColor = false,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    local ic = makeIcon(b, iconKey, iconSize or (size - 10), themeColor(Q, "TextDim"), (z or 30) + 1)
    b.MouseEnter:Connect(function()
        snd("Hover", 0.08)
        Util.Tween(b, { BackgroundTransparency = 0.85 }, 0.12)
        paintIcon(ic, accent)
    end)
    b.MouseLeave:Connect(function()
        Util.Tween(b, { BackgroundTransparency = 1 }, 0.12)
        paintIcon(ic, themeColor(Q, "TextDim"))
    end)
    return b, ic
end

-- ── 主构建 ──────────────────────────────────────────────────────
local function buildMusicPanel(host, opts)
    opts = opts or {}
    local accent = themeColor(Q, "Accent")
    local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local W = math.min(opts.Size and opts.Size.X.Offset or 380, math.max(300, math.floor(vp.X * 0.92)))
    local H = math.min(opts.Size and opts.Size.Y.Offset or 520, math.max(320, math.floor(vp.Y * 0.86)))

    local panel = Util.Create("Frame", {
        Parent = host, Name = "MusicPanel",
        BackgroundColor3 = themeColor(Q, "MainBg"),
        BackgroundTransparency = opts.Transparency or 0.10,
        BorderSizePixel = 0,
        Size = UDim2.new(0, W, 0, H),
        Position = opts.Position or UDim2.new(0.5, -W / 2, 0.5, -H / 2),
        Active = true, ZIndex = 40,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 12) }) })
    Util.Create("UIStroke", {
        Parent = panel, Color = accent, Thickness = 1,
        Transparency = opts.StrokeTransparency or 0.55,
    })

    local self = { panel = panel, engine = nil, alive = true, items = {}, liked = {},
                   volume = 0.6, current = nil, len = 0, playing = false, tab = "搜索" }

    -- ── 头部：封面 + 歌名/歌手 + 最小化/关闭 ─────────────────────
    local HEAD = 52
    local cover = Util.Create("Frame", {
        Parent = panel, BackgroundColor3 = themeColor(Q, "ControlAlt"),
        BackgroundTransparency = 0.15, BorderSizePixel = 0,
        Size = UDim2.new(0, 36, 0, 36), Position = UDim2.new(0, 12, 0, 8), ZIndex = 42,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 8) }) })
    local coverImg = Util.Create("ImageLabel", {
        Parent = cover, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), Image = "", Visible = false,
        ScaleType = Enum.ScaleType.Crop, ZIndex = 43,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 8) }) })
    local coverIcon = makeIcon(cover, "Note", 18, accent, 44)

    local title = Util.Create("TextLabel", {
        Parent = panel, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -116, 0, 16), Position = UDim2.new(0, 58, 0, 10),
        Font = Enum.Font.GothamMedium, Text = opts.EmptyText or "未在播放",
        TextColor3 = themeColor(Q, "TextBright"), TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 42,
    })
    local artist = Util.Create("TextLabel", {
        Parent = panel, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -116, 0, 14), Position = UDim2.new(0, 58, 0, 28),
        Font = Enum.Font.Gotham, Text = "",
        TextColor3 = themeColor(Q, "TextDim"), TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 42,
    })
    self.title, self.artist, self.coverImg, self.coverIcon = title, artist, coverImg, coverIcon

    local btnClose = mkIconButton(panel, 22, -6, "Close", 12, true, 44)
    local btnMin = mkIconButton(panel, 22, -32, "Down", 12, true, 44)
    btnMin.Position = UDim2.new(1, -32, 0, 20)
    btnMin.AnchorPoint = Vector2.new(1, 0.5)
    btnClose.Position = UDim2.new(1, -6, 0, 20)

    Util.Create("Frame", {
        Parent = panel, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.9, BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 1), Position = UDim2.new(0, 10, 0, HEAD), ZIndex = 42,
    })

    -- ── 传输区：上一首/播放/下一首 + 音量 ────────────────────────
    local TRAN = HEAD + 8
    local btnPrev = mkIconButton(panel, 26, 12, "Prev", 15, false, 44)
    local btnPlay = mkIconButton(panel, 34, 44, "Play", 18, false, 44)
    local btnNext = mkIconButton(panel, 26, 84, "Next", 15, false, 44)
    for _, b in ipairs({ btnPrev, btnPlay, btnNext }) do
        b.Position = UDim2.new(0, b.Position.X.Offset, 0, TRAN + 20)
    end
    local btnVolIcon = mkIconButton(panel, 22, -12, "Volume", 13, true, 44)
    btnVolIcon.Position = UDim2.new(1, -12, 0, TRAN + 20)

    local volSlider = mkSlider(panel, {
        Size = UDim2.new(0, 76, 0, 3),
        Position = UDim2.new(1, -112, 0, TRAN + 20),
        Ratio = self.volume, ZIndex = 44,
        OnChange = function(r)
            self.volume = r
            if self.engine then self.engine.SetVolume(r) end
        end,
    })
    self.volSlider, self.btnVolIcon = volSlider, btnVolIcon

    -- 进度条
    local PROG = TRAN + 42
    local prog = mkSlider(panel, {
        Size = UDim2.new(1, -24, 0, 3),
        Position = UDim2.new(0, 12, 0, PROG),
        ZIndex = 44,
        OnChange = function(r)
            if self.engine and self.len > 0 then self.engine.Seek(r * self.len) end
        end,
    })
    self.prog = prog
    local timeCur = Util.Create("TextLabel", {
        Parent = panel, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, 60, 0, 12), Position = UDim2.new(0, 12, 0, PROG + 6),
        Font = Enum.Font.Gotham, Text = "0:00",
        TextColor3 = themeColor(Q, "TextFaint"), TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 44,
    })
    local timeTot = Util.Create("TextLabel", {
        Parent = panel, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, 60, 0, 12), Position = UDim2.new(1, -72, 0, PROG + 6),
        Font = Enum.Font.Gotham, Text = "0:00",
        TextColor3 = themeColor(Q, "TextFaint"), TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 44,
    })
    self.timeCur, self.timeTot = timeCur, timeTot

    -- ── 搜索框 ──────────────────────────────────────────────────
    local SEARCH_Y = PROG + 24
    local searchBox = Util.Create("Frame", {
        Parent = panel, BackgroundColor3 = themeColor(Q, "Control"),
        BackgroundTransparency = 0.25, BorderSizePixel = 0,
        Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 0, SEARCH_Y), ZIndex = 42,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 8) }) })
    makeIcon(searchBox, "Search", 13, themeColor(Q, "TextFaint"), 44)
    local searchIcon = searchBox:GetChildren()[#searchBox:GetChildren()]
    searchIcon.Position = UDim2.new(0, 16, 0.5, 0)
    local tb = Util.Create("TextBox", {
        Parent = searchBox, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -46, 1, 0), Position = UDim2.new(0, 30, 0, 0),
        Font = Enum.Font.Gotham, Text = "", PlaceholderText = opts.Placeholder or "搜索歌曲 / 歌手",
        PlaceholderColor3 = themeColor(Q, "TextFaint"),
        TextColor3 = themeColor(Q, "TextBright"), TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 44,
    })
    self.searchBox = tb
    local debounce = nil
    tb:GetPropertyChangedSignal("Text"):Connect(function()
        if debounce then task.cancel(debounce) end
        local txt = tb.Text
        debounce = task.delay(0.5, function()
            if txt ~= "" then self:Search(txt) end
        end)
    end)
    tb.FocusLost:Connect(function() if tb.Text ~= "" then self:Search(tb.Text) end end)

    -- ── 分类条 ──────────────────────────────────────────────────
    local TABS_Y = SEARCH_Y + 38
    local TABS = { "搜索", "我喜欢的", "播放列表", "歌词" }
    local tabButtons = {}
    local tabUnderline = Util.Create("Frame", {
        Parent = panel, BackgroundColor3 = accent, BorderSizePixel = 0,
        Size = UDim2.new(0, 40, 0, 2), Position = UDim2.new(0, 12, 0, TABS_Y + 24),
        ZIndex = 44,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local function selectTab(name)
        self.tab = name
        -- 首次打开「我喜欢的」自动拉云端红心
        if name == "我喜欢的" and #self.liked == 0 and not self._likedLoading then
            self._likedLoading = true
            task.spawn(function()
                if self.LoadLiked then self:LoadLiked() end
                self._likedLoading = false
            end)
        end
        for i, n in ipairs(TABS) do
            local b = tabButtons[i]
            if b then
                b.TextColor3 = (n == name) and themeColor(Q, "TextBright") or themeColor(Q, "TextFaint")
            end
        end
        self:Refresh()
        local idx = 1
        for i, n in ipairs(TABS) do if n == name then idx = i end end
        Util.Tween(tabUnderline, {
            Position = UDim2.new(0, 12 + (idx - 1) * 62, 0, TABS_Y + 24),
            Size = UDim2.new(0, 44, 0, 2),
        }, 0.15)
    end
    for i, name in ipairs(TABS) do
        local b = Util.Create("TextButton", {
            Parent = panel, BackgroundTransparency = 1, BorderSizePixel = 0, Text = name,
            Size = UDim2.new(0, 56, 0, 24), Position = UDim2.new(0, 10 + (i - 1) * 62, 0, TABS_Y),
            Font = Enum.Font.GothamMedium, TextSize = 12,
            TextColor3 = themeColor(Q, "TextFaint"), ZIndex = 44, AutoButtonColor = false,
        })
        b.MouseButton1Click:Connect(function() snd("Click", 0.1) selectTab(name) end)
        tabButtons[i] = b
    end
    self.tabButtons, self.selectTab = tabButtons, selectTab

    -- ── 内容区 ──────────────────────────────────────────────────
    local BODY_Y = TABS_Y + 30
    local scroll = Util.Create("ScrollingFrame", {
        Parent = panel, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 1, -(BODY_Y + 10)), Position = UDim2.new(0, 10, 0, BODY_Y),
        CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 3,
        ScrollBarImageColor3 = accent, ScrollBarImageTransparency = 0.4,
        ZIndex = 42,
    }, {
        Util.Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
        }),
        Util.Create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6) }),
    })
    self.scroll = scroll
    scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, scroll.AbsoluteCanvasSize.Y)
    end)
    local layout = scroll:FindFirstChildOfClass("UIListLayout")
    if layout then
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
        end)
    end

    local emptyLabel = Util.Create("TextLabel", {
        Parent = scroll, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1,
        Font = Enum.Font.Gotham, Text = "输入关键词搜索，或打开「我喜欢的」",
        TextColor3 = themeColor(Q, "TextFaint"), TextSize = 12, ZIndex = 43,
    })
    self.emptyLabel = emptyLabel

    -- ── 行 / 歌词的构建与刷新 ───────────────────────────────────
    self.rowHeight = opts.RowHeight or 44
    self.rows = {}
    self.lyricLines = {}

    -- ── 对外方法（Refresh 在下面装配） ──────────────────────────
    function self:SetSong(song)
        song = song or {}
        title.Text = song.Title or opts.EmptyText or "未在播放"
        artist.Text = song.Artist or ""
        if type(song.Cover) == "string" and song.Cover ~= "" then
            coverImg.Image = song.Cover coverImg.Visible = true coverIcon.Visible = false
        else
            coverImg.Visible = false coverIcon.Visible = true
        end
    end
    function self:SetPlaying(on)
        self.playing = on and true or false
        btnPlay:ClearAllChildren()
        Util.Create("UICorner", { Parent = btnPlay, CornerRadius = UDim.new(0, 6) })
        makeIcon(btnPlay, self.playing and "Pause" or "Play", 18, themeColor(Q, "TextBright"), 45)
    end
    function self:SetProgress(pos, len)
        self.pos, self.len = pos or 0, len or 0
        local r = (self.len > 0) and math.clamp(self.pos / self.len, 0, 1) or 0
        prog:SetRatio(r)
        timeCur.Text = fmtTime(self.pos)
        timeTot.Text = fmtTime(self.len)
    end
    function self:SetVolume(v)
        self.volume = math.clamp(v or 0, 0, 1)
        volSlider:SetRatio(self.volume)
    end
    function self:Show() panel.Visible = true end
    function self:Hide() panel.Visible = false end
    function self:Toggle() panel.Visible = not panel.Visible end
    function self:IsVisible() return panel.Visible end
    function self:GetFrame() return panel end
    function self:Destroy() self.alive = false pcall(function() panel:Destroy() end) end
    function self:SetMiniBar(bar) self.miniBar = bar end

    btnPlay.MouseButton1Click:Connect(function()
        snd("Click", 0.12)
        if self.engine then self.engine.Toggle() end
    end)
    btnPrev.MouseButton1Click:Connect(function() snd("Click", 0.12) if self.engine then self.engine.Prev() end end)
    btnNext.MouseButton1Click:Connect(function() snd("Click", 0.12) if self.engine then self.engine.Next() end end)
    btnVolIcon.MouseButton1Click:Connect(function()
        snd("Click", 0.1)
        local v = (self.volume > 0.01) and 0 or 0.6
        self:SetVolume(v)
        if self.engine then self.engine.SetVolume(v) end
    end)
    btnMin.MouseButton1Click:Connect(function()
        snd("Click", 0.1)
        self:Hide()
        if self.miniBar then self.miniBar:Show() self.miniBar:Wake(8) end
        if opts.OnMinimize then opts.OnMinimize(self) end
    end)
    btnClose.MouseButton1Click:Connect(function()
        snd("Click", 0.1)
        self:Hide()
        if opts.OnClose then opts.OnClose(self) end
    end)

    -- 拖拽移动
    local dragStart, startPos = nil, nil
    panel.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart = i.Position
            startPos = Vector2.new(panel.AbsolutePosition.X, panel.AbsolutePosition.Y)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragStart then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - dragStart
        if math.abs(d.X) + math.abs(d.Y) < 5 then return end
        panel.AnchorPoint = Vector2.new(0, 0)
        panel.Position = UDim2.new(0, startPos.X + d.X, 0, startPos.Y + d.Y)
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart = nil
        end
    end)

    -- ── 内容渲染：歌曲行 ────────────────────────────────────────
    local function clearRows()
        for _, r in ipairs(self.rows) do pcall(function() r:Destroy() end) end
        self.rows = {}
    end

    local function makeRow(item, order)
        local RH = self.rowHeight
        local row = Util.Create("TextButton", {
            Parent = scroll, BackgroundColor3 = themeColor(Q, "Control"),
            BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
            Size = UDim2.new(1, 0, 0, RH), LayoutOrder = order,
            ZIndex = 43, AutoButtonColor = false,
        }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 8) }) })

        local cov = Util.Create("Frame", {
            Parent = row, BackgroundColor3 = themeColor(Q, "ControlAlt"),
            BackgroundTransparency = 0.2, BorderSizePixel = 0,
            Size = UDim2.new(0, RH - 16, 0, RH - 16),
            Position = UDim2.new(0, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 44,
        }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
        local cImg = Util.Create("ImageLabel", {
            Parent = cov, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 1, 0), Image = "", Visible = false,
            ScaleType = Enum.ScaleType.Crop, ZIndex = 45,
        }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
        local cIcon = makeIcon(cov, "Note", 13, accent, 45)
        if type(item.Cover) == "string" and item.Cover ~= "" then
            cImg.Image = item.Cover cImg.Visible = true cIcon.Visible = false
        end

        local t = Util.Create("TextLabel", {
            Parent = row, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, -130, 0, 14), Position = UDim2.new(0, RH - 6, 0, RH / 2 - 15),
            Font = Enum.Font.GothamMedium, Text = item.Title or "未知",
            TextColor3 = themeColor(Q, "TextBright"), TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 44,
        })
        local s = Util.Create("TextLabel", {
            Parent = row, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, -130, 0, 12), Position = UDim2.new(0, RH - 6, 0, RH / 2 + 1),
            Font = Enum.Font.Gotham, Text = item.Sub or "",
            TextColor3 = themeColor(Q, "TextDim"), TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 44,
        })
        local dur = Util.Create("TextLabel", {
            Parent = row, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0, 42, 0, 12), Position = UDim2.new(1, -76, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Font = Enum.Font.Gotham, Text = fmtTime(item.Duration or 0),
            TextColor3 = themeColor(Q, "TextFaint"), TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 44,
        })
        local fav = mkIconButton(row, 24, -6, item.Fav and "HeartOn" or "Heart", 13, true, 44)
        local activeMark = Util.Create("Frame", {
            Parent = row, BackgroundColor3 = accent, BorderSizePixel = 0,
            Size = UDim2.new(0, 2, 0, RH - 16), Position = UDim2.new(0, 2, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5), Visible = false, ZIndex = 45,
        }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

        local api = { frame = row, item = item }
        function api:SetActive(on)
            activeMark.Visible = on and true or false
            row.BackgroundTransparency = on and 0.72 or 1
        end
        function api:SetFav(on)
            fav:ClearAllChildren()
            Util.Create("UICorner", { Parent = fav, CornerRadius = UDim.new(0, 6) })
            makeIcon(fav, on and "HeartOn" or "Heart", 13,
                on and C(255, 80, 110) or themeColor(Q, "TextDim"), 45)
        end

        row.MouseEnter:Connect(function() Util.Tween(row, { BackgroundTransparency = 0.86 }, 0.12) end)
        row.MouseLeave:Connect(function()
            Util.Tween(row, { BackgroundTransparency = activeMark.Visible and 0.72 or 1 }, 0.12)
        end)
        row.MouseButton1Click:Connect(function()
            snd("Click", 0.12)
            if self.onSelect then self.onSelect(item) end
        end)
        fav.MouseButton1Click:Connect(function()
            snd("Click", 0.12)
            if self.engine and self.engine.ToggleFav then
                local now = self.engine.ToggleFav(item)
                api:SetFav(now == true)
                item.Fav = now == true
            end
        end)
        return api
    end

    local function renderRows(list, emptyText)
        clearRows()
        if #list == 0 then
            emptyLabel.Text = emptyText or "暂无歌曲"
            emptyLabel.Visible = true
            emptyLabel.LayoutOrder = 1
            return
        end
        emptyLabel.Visible = false
        for i, item in ipairs(list) do
            local r = makeRow(item, i)
            if self.current and item.Id == self.current.Id then r:SetActive(true) end
            self.rows[#self.rows + 1] = r.frame
            self.rowApis = self.rowApis or {}
            self.rowApis[#self.rowApis + 1] = r
        end
    end

    local function renderLyrics()
        clearRows()
        self.rowApis = {}
        local lines = self.lyricLines
        if not lines or #lines == 0 then
            emptyLabel.Text = "暂无歌词"
            emptyLabel.Visible = true
            emptyLabel.LayoutOrder = 1
            return
        end
        emptyLabel.Visible = false
        self.lyricLabels = {}
        for i, l in ipairs(lines) do
            local lab = Util.Create("TextLabel", {
                Parent = scroll, BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, -16, 0, 26), LayoutOrder = i,
                Font = Enum.Font.GothamMedium, Text = l.text or "",
                TextColor3 = themeColor(Q, "TextFaint"), TextSize = 12,
                TextWrapped = true, ZIndex = 43,
            })
            lab.MouseButton1Click:Connect(function()
                if self.engine then self.engine.Seek(l.t or 0) end
            end)
            self.lyricLabels[i] = lab
            self.rows[#self.rows + 1] = lab
        end
    end

    function self:Refresh()
        self.rowApis = {}
        local t = self.tab
        if t == "搜索" then
            renderRows(self.items, "输入关键词搜索")
        elseif t == "我喜欢的" then
            renderRows(self.liked, "还没有红心歌曲")
        elseif t == "播放列表" then
            local q = {}
            local ok, st = pcall(function() return self.engine and self.engine.GetState() end)
            if ok and st and st.queue then q = st.queue end
            renderRows(q, "播放队列是空的")
        else
            renderLyrics()
        end
    end

    function self:Search(kw)
        if not self.engine then return end
        local ok, list = pcall(function() return self.engine.Search(kw, opts.SearchLimit or 30) end)
        self.items = (ok and type(list) == "table") and list or {}
        if self.tab ~= "搜索" then selectTab("搜索") else self:Refresh() end
    end

    function self:LoadLiked()
        if not self.engine then return end
        task.spawn(function()
            local list = self.engine.Liked(false)
            self.liked = type(list) == "table" and list or {}
            if self.tab == "我喜欢的" then self:Refresh() end
        end)
    end

    -- ── 接标准后端 ──────────────────────────────────────────────
    function self:Bind(engine, bopts)
        self.engine = engine
        bopts = bopts or {}
        self.onSelect = function(item)
            self.current = item
            local list = (self.tab == "我喜欢的") and self.liked or self.items
            engine.SetQueue(list, 1)
            engine.Play(item)
            self:SetSong({ Title = item.Title, Artist = item.Sub, Cover = item.Cover })
            for _, r in ipairs(self.rowApis or {}) do
                if r.item and r.item.Id == item.Id then r:SetActive(true) end
            end
        end
        if bopts.Volume then self:SetVolume(bopts.Volume) engine.SetVolume(self.volume) end
        task.spawn(function()
            local lastId, lastTab, lyricMiss = nil, nil, nil
            while self.alive do
                task.wait(bopts.PollInterval or 0.25)
                local ok, st = pcall(function() return engine.GetState() end)
                if ok and st then
                    self:SetPlaying(st.playing)
                    self:SetProgress(st.pos, st.len)
                    local song = st.song
                    if song and song.id ~= lastId then
                        lastId = song.id
                        self.current = { Id = song.id, Title = song.name, Sub = song.artist }
                        self:SetSong({ Title = song.name, Artist = song.artist, Cover = song.cover })
                        -- 歌词是「下载完才开始拉」的，此刻多半还没回来，标记待补拉
                        self.lyricLines = engine.Lyric and engine.Lyric() or nil
                        lyricMiss = self.lyricLines and nil or 0
                        if self.tab == "歌词" then self:Refresh() end
                        if self.miniBar then self.miniBar:Wake() end
                    elseif song and not self.lyricLines and (lyricMiss or 0) < 200    -- 约 50s：下载一首歌可能就要 17s，歌词要等下载完才拉 then
                        -- 补拉歌词（最多 30 次 ≈ 7.5s，够下载+解析了）
                        lyricMiss = (lyricMiss or 0) + 1
                        self.lyricLines = engine.Lyric and engine.Lyric() or nil
                        if self.lyricLines and self.tab == "歌词" then self:Refresh() end
                    end
                    -- 歌词高亮
                    if self.tab == "歌词" and self.lyricLabels and engine.LyricAt then
                        local _, idx = engine.LyricAt(st.pos or 0)
                        if idx and idx ~= lastTab then
                            lastTab = idx
                            for i, lab in ipairs(self.lyricLabels) do
                                lab.TextColor3 = (i == idx) and accent or themeColor(Q, "TextFaint")
                            end
                        end
                    end
                end
            end
        end)
        return self
    end

    function self:BindNetease(bopts)
        local g = (getgenv and getgenv()) or _G
        local ncm = g and g.NCM
        if not ncm then return nil, "getgenv().NCM 不存在：先加载 netease-engine.lua" end
        local eng, err = MusicUI.neteaseEngine(ncm)
        if not eng then return nil, err end
        return self:Bind(eng, bopts)
    end

    self:SetPlaying(false)
    self:SetVolume(self.volume)
    self.rowApis = {}
    selectTab("搜索")
    return self
end

-- 用法：MusicUI.CreateWindow(QuantumUI, { Size = UDim2.new(0, 380, 0, 520) })
function MusicUI.CreateWindow(a, b)
    local cls, opts
    if type(a) == "table" and (a.ScreenGui or a.MainFrame) then cls, opts = a, (b or {})
    else cls, opts = Q, (a or {}) end
    local host = opts.Parent or (cls and cls.ScreenGui)
    if not host then return nil, "找不到宿主 ScreenGui：先创建 QuantumUI 窗口，或用 opts.Parent 指定" end
    if cls and cls ~= Q then bindInternals(cls) end
    return buildMusicPanel(host, opts)
end

-- ── 装到类表上 ──────────────────────────────────────────────────
-- v1.3 起 CreateMusicWindow 返回悬浮式面板；旧实现保留为 Legacy 不再使用
local function installCreateMusicWindow(cls)
    function cls:CreateMusicPanel(options)
        options = options or {}
        local host = self.ScreenGui
        if not host then return nil end
        local panel = buildMusicPanel(host, options)
        if options.MiniBar then panel:SetMiniBar(options.MiniBar) end
        return panel
    end

    function cls:CreateMusicWindow(options)
        return self:CreateMusicPanel(options)
    end
end

-- ═══════════════════════════════════════════════════════════════════
local function installCreateMusicWindowLegacy(cls)   -- v1.2 及以前的旧窗口，保留但不再使用
    function cls:CreateMusicWindow(options)
        options = options or {}
        local host = self.ScreenGui
        if not host then return nil end

        local accent = themeColor(self, "Accent")
        local w = options.Size or UDim2.new(0, 380, 0, 560)

        -- 未指定位置时：叠在主窗口正上方（视觉上「替换」而非并存）
        local pos = options.Position
        if not pos and self.MainFrame then
            local okMf, mf = pcall(function()
                return {
                    X = self.MainFrame.AbsolutePosition.X + self.MainFrame.AbsoluteSize.X / 2,
                    Y = self.MainFrame.AbsolutePosition.Y + self.MainFrame.AbsoluteSize.Y / 2,
                }
            end)
            if okMf and mf and mf.X > 0 then
                pos = UDim2.new(0, mf.X - w.X.Offset / 2, 0, mf.Y - w.Y.Offset / 2)
            end
        end

        local win = Util.Create("Frame", {
            Parent = host,
            Name = "MusicWindow",
            BackgroundColor3 = themeColor(self, "MainBg"),
            BackgroundTransparency = 0.06,
            BorderSizePixel = 0,
            Size = w,
            Position = pos or UDim2.new(0.5, -w.X.Offset / 2, 0.5, -w.Y.Offset / 2),
            Active = true,
            ZIndex = 40,
        })
        local stroke = Util.Create("UIStroke", {Parent = win, Color = accent, Thickness = 1, Transparency = 0.6})

        local topbar = Util.Create("Frame", {
            Parent = win, BackgroundColor3 = themeColor(self, "TopBar"),
            BackgroundTransparency = 0.1, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 32), ZIndex = 41,
        })
        local titleL = Util.Create("TextLabel", {
            Parent = topbar, BackgroundTransparency = 1,
            Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -80, 1, 0),
            Font = Enum.Font.GothamBold, Text = options.Title or "♪ MUSIC",
            TextColor3 = accent, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 42,
        })

        local page = Util.Create("Frame", {
            Parent = win, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, -20, 1, -42), Position = UDim2.new(0, 10, 0, 36),
            ClipsDescendants = true, ZIndex = 41,
        })

        local mt = buildMusicPage(self, page, options)

        -- 关闭 / 折叠
        local closed = false
        local closeBtn = iconButton(topbar, {
            Size = 20, Icon = "Close", Color = C(230, 120, 120),
            Accent = C(255, 90, 90), IconScale = 0.55, BgTransparency = 1,
            Position = UDim2.new(1, -26, 0.5, 0), ZIndex = 43,
            Callback = function()
                safeCb(options.OnClose)
                win.Visible = false
            end,
        })
        closeBtn.Frame.AnchorPoint = Vector2.new(0, 0.5)

        -- 拖拽
        do
            local dragging, dragStart, startPos = false, nil, nil
            topbar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    dragStart = input.Position
                    startPos = win.Position
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if not dragging then return end
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    local d = input.Position - dragStart
                    win.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + d.X,
                        startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = false
                end
            end)
        end

        mt.Window = win
        mt.TitleLabel = titleL
        function mt:SetTitle(t) titleL.Text = tostring(t or "") end
        function mt:Show() win.Visible = true end
        function mt:Hide() win.Visible = false end
        function mt:Toggle() win.Visible = not win.Visible end
        function mt:IsVisible() return win.Visible end
        function mt:SetSize(s) win.Size = s end
        function mt:SetPosition(p) win.Position = p end
        function mt:Destroy() win:Destroy() end
        return mt
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  挂载
-- ═══════════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════════
--  引擎绑定层（v1.1）
--    music.lua 对音频后端零依赖，只认下面这组「标准后端接口」：
--      Search(kw, limit) -> items[]     items: {Id,Title,Sub,Duration,Cover,Fav}
--      Play(item)  Toggle()  Next()  Prev()
--      Seek(sec)  SetVolume(v)  SetQueue(items, index)
--      GetState() -> {playing,pos,len,volume,index,count,status,song}
--      Lyric() -> {{t=秒,text=…}} | nil      Login() -> ok, account
--    任何实现这组接口的对象都能接进来；BindNetease() 是内置的网易云适配器
--    （配合同目录的 netease-engine.lua 使用）。
-- ══════════════════════════════════════════════════════════════════

local RunService = game:GetService("RunService")

-- 把网易云引擎（getgenv().NCM）适配成标准后端
local function neteaseEngine(ncm)
    if type(ncm) ~= "table" then return nil, "getgenv().NCM 不存在，netease-engine.lua 没加载？" end
    local E = { raw = ncm, name = "netease" }

    local function toItem(s)
        if not s then return nil end
        return {
            Id = s.id, Title = s.name or "未知", Sub = s.artist or "",
            Duration = s.dur or 0, Cover = s.cover or "",
            Fav = (ncm.FavHas and ncm.FavHas(s.id)) or false,
            _raw = s,
        }
    end
    local function toRaw(item)
        if not item then return nil end
        return item._raw or { id = item.Id, name = item.Title, artist = item.Sub, dur = item.Duration }
    end

    function E.Search(kw, limit)
        local list = ncm.Search(kw, limit or 30) or {}
        local out = {}
        for i, s in ipairs(list) do out[i] = toItem(s) end
        return out
    end

    function E.Liked(force)
        local list, err = ncm.SearchLiked(force)
        if type(list) ~= "table" then return {}, err or "取红心失败" end
        local out = {}
        for i, s in ipairs(list) do out[i] = toItem(s) end
        return out, err
    end

    function E.Play(item) local r = toRaw(item) if not r then return false, "无歌曲" end return ncm.Play(r) end
    function E.Toggle() ncm.Toggle() end
    function E.Next() ncm.Next() end
    function E.Prev() ncm.Prev() end
    function E.Seek(sec) ncm.Seek(sec) end
    function E.SetVolume(v) ncm.SetVolume(v) end
    function E.GetState() return ncm.GetState() end
    function E.Lyric() return ncm.LyricLines() end
    function E.LyricAt(pos) return ncm.LyricAt(pos) end
    function E.Login() return ncm.IsLoggedIn() end
    function E.SetQueue(items, index)
        local raw = {}
        for i, it in ipairs(items or {}) do raw[i] = toRaw(it) end
        return ncm.SetQueue(raw, index)
    end
    function E.ToggleFav(item)
        local r = toRaw(item)
        if not r then return false end
        return ncm.FavToggle(r)
    end
    return E
end
MusicUI.neteaseEngine = neteaseEngine

-- ── 一键绑定：自动建好播放卡片 / 搜索框 / 分类条 / 列表 / 队列 / 歌词 ──
-- target 可以是 Tab（AddMusicTab 的返回值）或 MusicWindow
-- opts = {Panels={Songs,Likes,Queue,Lyrics}, SearchLimit, PollInterval,
--         PlayerHeight, SearchPlaceholder, OnLog, AutoLiked}
function MusicUI.BindEngine(target, engine, opts)
    if type(target) ~= "table" then return nil, "BindEngine(target, engine): target 必填" end
    if type(engine) ~= "table" or type(engine.GetState) ~= "function" then
        return nil, "engine 必须实现标准后端接口（至少 GetState）"
    end
    opts = opts or {}
    local PN = opts.Panels or {}
    local P_SONG, P_LIKE = PN.Songs or "Songs", PN.Likes or "Likes"
    local P_QUEUE, P_LYRIC = PN.Queue or "Queue", PN.Lyrics or "Lyrics"
    local LIMIT  = opts.SearchLimit or 30
    local POLL   = opts.PollInterval or 0.25
    local log    = opts.OnLog or function() end

    for _, name in ipairs({ P_SONG, P_LIKE, P_QUEUE, P_LYRIC }) do target:AddPanel(name) end

    local Ctl = { engine = engine, target = target, volume = 0.6, playing = false }
    Ctl.current, Ctl.items, Ctl.liked = nil, {}, {}

    -- ── 播放卡片 ──────────────────────────────────────────────
    local P = target:AddMusicPlayer({
        Height = opts.PlayerHeight or 132,
        OnPlayPause = function() engine.Toggle() end,
        OnPrev      = function() engine.Prev() end,
        OnNext      = function() engine.Next() end,
        OnSeek      = function(sec) engine.Seek(sec) end,
        OnVolume    = function(v) Ctl.volume = v engine.SetVolume(v) end,
        OnLike      = function(on)
            if not Ctl.current then return end
            local now = engine.ToggleFav and engine.ToggleFav(Ctl.current)
            if on ~= nil then P:SetLiked(now == true) end
            if Ctl.songList then Ctl.songList:SetFav(Ctl.current.Id, now == true) end
        end,
    })
    P:SetVolume(Ctl.volume)
    Ctl.player = P

    -- ── 搜索框 ────────────────────────────────────────────────
    local S = target:AddSearchBox({
        Placeholder = opts.SearchPlaceholder or "搜索歌曲 / 歌手",
        Debounce = 0.45,
        OnSearch = function(text)
            if text == "" then return end
            Ctl.search(text)
        end,
    })
    Ctl.searchBox = S

    -- ── 分类条 ────────────────────────────────────────────────
    local Tabs = target:AddSubTabs({ "搜索", "我喜欢的", "播放列表", "歌词" }, function(name)
        if name == "播放列表" then target:ShowPanel(P_QUEUE)
        elseif name == "我喜欢的" then target:ShowPanel(P_LIKE) Ctl.loadLiked()
        elseif name == "歌词" then target:ShowPanel(P_LYRIC)
        else target:ShowPanel(P_SONG) end
    end)
    Ctl.subTabs = Tabs

    -- ── 列表 / 队列 / 歌词 ────────────────────────────────────
    Ctl.songList = target:AddSongList({
        Panel = P_SONG, RowHeight = 58, ShowFav = true, ShowDuration = true,
        EmptyText = "输入关键词搜索，或打开「我喜欢的」",
        OnSelect = function(item) Ctl.playItem(item, Ctl.items) end,
    })
    Ctl.likeList = target:AddSongList({
        Panel = P_LIKE, RowHeight = 58, ShowFav = true, ShowDuration = true,
        EmptyText = "还没有红心歌曲",
        OnSelect = function(item) Ctl.playItem(item, Ctl.liked) end,
    })
    Ctl.queue = target:AddQueue({
        Panel = P_QUEUE,
        OnSelect = function(item, i)
            if engine.PlayAt then engine.PlayAt(i) else engine.Play(item) end
        end,
        OnRemove = function(item, i)
            table.remove(Ctl.items, i)
            engine.SetQueue(Ctl.items)
            Ctl.queue:Set(Ctl.items)
        end,
    })
    Ctl.lyric = target:AddLyricPanel({
        Panel = P_LYRIC, TextSize = 14, AutoScroll = true,
        OnLineClick = function(t) engine.Seek(t) end,
    })

    -- ── 行为 ──────────────────────────────────────────────────
    function Ctl.playItem(item, list)
        if not item then return end
        Ctl.current = item
        engine.SetQueue(list or { item }, 1)
        local ok, err = engine.Play(item)
        if not ok then P:SetStatus(tostring(err or "播放失败")) end
        P:SetSong({ Id = item.Id, Title = item.Title, Artist = item.Sub,
                    Duration = item.Duration, Cover = item.Cover })
        if Ctl.songList then Ctl.songList:SetActive(item.Id) end
        if Ctl.likeList then Ctl.likeList:SetActive(item.Id) end
        Ctl.lyric:Clear()
        log("play: " .. tostring(item.Title))
    end

    function Ctl.search(kw)
        local ok, list = pcall(function() return engine.Search(kw, LIMIT) end)
        if not ok or type(list) ~= "table" then
            Ctl.songList:SetEmptyText("搜索失败")
            return
        end
        Ctl.items = list
        Ctl.songList:Set(list)
        target:ShowPanel(P_SONG)
        log("search: " .. kw .. " -> " .. #list)
    end

    function Ctl.loadLiked()
        Ctl.likeList:SetLoading(true)
        task.spawn(function()
            local list, err = engine.Liked(false)
            Ctl.liked = list or {}
            Ctl.likeList:Set(Ctl.liked)
            if err then Ctl.likeList:SetEmptyText(tostring(err)) end
            log("liked: " .. #Ctl.liked .. " " .. tostring(err or ""))
        end)
    end

    -- ── 轮询同步 ──────────────────────────────────────────────
    Ctl.alive = true
    task.spawn(function()
        local lastStatus, lastSongId, lastLyricIdx = nil, nil, nil
        while Ctl.alive do
            task.wait(POLL)
            local ok, st = pcall(function() return engine.GetState() end)
            if ok and st then
                Ctl.playing = st.playing and true or false
                P:SetPlaying(Ctl.playing)
                P:SetProgress(st.pos or 0, st.len or 0)
                if st.status ~= lastStatus then
                    lastStatus = st.status
                    P:SetStatus(st.status or "")
                end
                local song = st.song
                local sid = song and song.id
                if sid and sid ~= lastSongId then
                    lastSongId = sid
                    Ctl.current = { Id = sid, Title = song.name or "未知", Sub = song.artist or "",
                                    Duration = song.dur or 0 }
                    P:SetSong(Ctl.current)
                    P:SetLiked(engine.raw and engine.raw.FavHas and engine.raw.FavHas(sid) or false)
                    if Ctl.songList then Ctl.songList:SetActive(sid) end
                    if Ctl.likeList then Ctl.likeList:SetActive(sid) end
                    local lines = engine.Lyric()
                    Ctl.lyric:Set(lines or {})
                    lastLyricIdx = nil
                end
                local _, idx = engine.LyricAt and engine.LyricAt(st.pos or 0)
                if idx and idx ~= lastLyricIdx then
                    lastLyricIdx = idx
                    Ctl.lyric:Seek(st.pos or 0)
                end
            end
        end
    end)

    function Ctl.destroy()
        Ctl.alive = false
    end
    function Ctl.setVolume(v) Ctl.volume = v engine.SetVolume(v) P:SetVolume(v) end

    if opts.AutoLiked then Ctl.loadLiked() end
    target:ShowPanel(P_SONG)
    log("bind ok: " .. tostring(engine.name or "engine"))
    return Ctl
end

-- ── 网易云快捷绑定：BindNetease(target, opts) ────────────────────
-- 引擎不存在时返回 nil + 原因，不会报错
function MusicUI.BindNetease(target, opts)
    local g = (getgenv and getgenv()) or _G
    local ncm = g and g.NCM
    if not ncm then
        return nil, "getgenv().NCM 不存在：先加载 netease-engine.lua（可设 NCM_OPTIONS={Headless=true} 只跑引擎）"
    end
    local engine, err = MusicUI.neteaseEngine(ncm)
    if not engine then return nil, err end
    return MusicUI.BindEngine(target, engine, opts)
end
-- ══════════════════════════════════════════════════════════════════
--  迷你播放条（v1.2）
--    贴在屏幕边缘的细条播放器：默认半透明，鼠标悬停才变实，
--    离开几秒后自动淡到几乎看不见 —— 保持在前台，但不挡视野/准星。
--    拖拽可换位置，松手自动吸附到最近的边缘或角落。
-- ══════════════════════════════════════════════════════════════════

local DOCK_ANCHORS = {
    Top         = { ax = 0.5, ay = 0, ox = 0,   oy = 46 },
    Bottom      = { ax = 0.5, ay = 1, ox = 0,   oy = -16 },
    TopLeft     = { ax = 0,   ay = 0, ox = 14,  oy = 46 },
    TopRight    = { ax = 1,   ay = 0, ox = -14, oy = 46 },
    BottomLeft  = { ax = 0,   ay = 1, ox = 14,  oy = -16 },
    BottomRight = { ax = 1,   ay = 1, ox = -14, oy = -16 },
}

-- 按当前屏幕位置吸附到最近的锚点
local function nearestDock(absPos, absSize)
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local cx = absPos.X + absSize.X / 2
    local cy = absPos.Y + absSize.Y / 2
    local nearLeft = cx < vp.X * 0.33
    local nearRight = cx > vp.X * 0.67
    local nearTop = cy < vp.Y * 0.5
    if nearTop then
        if nearLeft then return "TopLeft" elseif nearRight then return "TopRight" else return "Top" end
    end
    if nearLeft then return "BottomLeft" elseif nearRight then return "BottomRight" else return "Bottom" end
end

local function buildMiniBar(host, opts)
    opts = opts or {}
    local self = {}
    self.opts = opts
    self.engine = nil
    self.alive = true
    self.dock = DOCK_ANCHORS[opts.Dock or "Top"] and (opts.Dock or "Top") or "Top"
    self.idleAlpha = opts.IdleAlpha or 0.35      -- 常态透明度
    self.hoverAlpha = opts.HoverAlpha or 0.02    -- 悬停透明度
    self.awayAlpha = opts.AwayAlpha or 0.62      -- 长时间不用时的透明度（还要能看清歌名）
    self.awayDelay = opts.AwayDelay or 5
    self.volume = 0.6
    self.len, self.pos = 0, 0
    self.artist, self.status = "", nil
    self.expanded = false
    -- 初始化时先按「常态」显示一个 awayDelay，不要一创建就淡到最淡
    self._hoverUntil = os.clock() + self.awayDelay

    local H = opts.Height or 38
    -- 宽度自适应：默认不超过视口的 45%，避免在窄窗口/手机上盖住半个屏幕
    local vp0 = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local W = math.min(opts.Width or 400, math.max(240, math.floor(vp0.X * 0.45)))
    local accent = themeColor(Q, "Accent")

    local root = Util.Create("Frame", {
        Parent = host, Name = "MusicMiniBar",
        BackgroundColor3 = themeColor(Q, "MainBg"),
        BackgroundTransparency = self.idleAlpha,
        BorderSizePixel = 0,
        Size = UDim2.new(0, W, 0, H),
        Active = true, ClipsDescendants = false, ZIndex = 60,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 10) }) })
    self.frame = root

    local stroke = Util.Create("UIStroke", {
        Parent = root, Color = accent, Thickness = 1, Transparency = 0.55,
    })
    self.stroke = stroke

    -- ── 封面 ────────────────────────────────────────────────────
    local cover = Util.Create("Frame", {
        Parent = root, BackgroundColor3 = themeColor(Q, "ControlAlt"),
        BackgroundTransparency = 0.15, BorderSizePixel = 0,
        Size = UDim2.new(0, H - 12, 0, H - 12),
        Position = UDim2.new(0, 6, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5), ZIndex = 62,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    self.cover = cover
    local coverImg = Util.Create("ImageLabel", {
        Parent = cover, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), Image = "", ZIndex = 63,
        ImageTransparency = 0, ScaleType = Enum.ScaleType.Crop,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
    self.coverImg = coverImg
    self.coverIcon = makeIcon(cover, "Note", 16, accent, 64)

    -- ── 文字 ────────────────────────────────────────────────────
    local title = Util.Create("TextLabel", {
        Parent = root, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -200, 0, 15),
        Position = UDim2.new(0, H - 2, 0, 6),
        Font = Enum.Font.GothamMedium, Text = opts.EmptyText or "未在播放",
        TextColor3 = themeColor(Q, "TextBright"), TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62,
    })
    local sub = Util.Create("TextLabel", {
        Parent = root, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -200, 0, 13),
        Position = UDim2.new(0, H - 2, 0, 20),
        Font = Enum.Font.Gotham, Text = "",
        TextColor3 = themeColor(Q, "TextDim"), TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62,
    })
    self.title, self.sub = title, sub

    -- ── 进度线（贴底，可点/拖跳转） ──────────────────────────────
    local track = Util.Create("Frame", {
        Parent = root, BackgroundColor3 = themeColor(Q, "ControlHover"),
        BackgroundTransparency = 0.35, BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 3),
        Position = UDim2.new(0, 10, 1, -5),
        ZIndex = 63,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local fill = Util.Create("Frame", {
        Parent = track, BackgroundColor3 = accent,
        BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0), ZIndex = 64,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    self.track, self.fill = track, fill

    -- ── 控制按钮 ────────────────────────────────────────────────
    local function mkBtn(size, rightOffset, iconKey, iconSize)
        local b = Util.Create("TextButton", {
            Parent = root, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
            Size = UDim2.new(0, size, 0, size),
            Position = UDim2.new(1, rightOffset, 0.5, 0),
            -- 锚在右边缘：rightOffset 是「右边缘距条右边多少」，否则整排会溢出被裁
            AnchorPoint = Vector2.new(1, 0.5), ZIndex = 64, AutoButtonColor = false,
        }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
        local ic = makeIcon(b, iconKey, iconSize or (size - 12), themeColor(Q, "TextDim"), 65)
        b.MouseEnter:Connect(function()
            snd("Hover", 0.08)
            Util.Tween(b, { BackgroundTransparency = 0.85 }, 0.12)
            paintIcon(ic, accent)
        end)
        b.MouseLeave:Connect(function()
            Util.Tween(b, { BackgroundTransparency = 1 }, 0.12)
            paintIcon(ic, themeColor(Q, "TextDim"))
        end)
        return b, ic
    end

    -- 右边缘锚点：offset = 该键右边缘到条右边的距离（逐键累加宽度 + 间隔）
    local btnClose  = mkBtn(22, -6,   "Close", 12)
    local btnExpand = mkBtn(22, -32,  "Queue", 12)
    local btnVol    = mkBtn(22, -58,  "Volume", 13)
    local btnNext   = mkBtn(24, -86,  "Next", 13)
    local btnPlay   = mkBtn(28, -116, "Play", 14)
    local btnPrev   = mkBtn(24, -148, "Prev", 13)
    self.btnPlay, self.btnPlayIcon = btnPlay, nil

    -- ── 交互：悬停变实 / 闲置淡出 ────────────────────────────────
    local function wake()
        self._hoverUntil = os.clock() + self.awayDelay
        Util.Tween(root, { BackgroundTransparency = self.hoverAlpha }, 0.18)
        Util.Tween(stroke, { Transparency = 0.15 }, 0.18)
    end
    local function settle()
        self._hoverUntil = os.clock() + self.awayDelay
        Util.Tween(root, { BackgroundTransparency = self.idleAlpha }, 0.25)
        Util.Tween(stroke, { Transparency = 0.55 }, 0.25)
    end
    root.MouseEnter:Connect(wake)
    root.MouseLeave:Connect(settle)

    task.spawn(function()
        while self.alive do
            task.wait(0.5)
            if os.clock() > self._hoverUntil and root.BackgroundTransparency < self.awayAlpha - 0.01 then
                Util.Tween(root, { BackgroundTransparency = self.awayAlpha }, 0.6)
                Util.Tween(stroke, { Transparency = 0.85 }, 0.6)
            end
        end
    end)

    -- ── 进度跳转 ────────────────────────────────────────────────
    local dragging = false
    local function seekFromInput(px)
        if not self.engine or self.len <= 0 then return end
        local abs = track.AbsolutePosition.X
        local w = math.max(1, track.AbsoluteSize.X)
        local r = math.clamp((px - abs) / w, 0, 1)
        self.engine.Seek(r * self.len)
        fill.Size = UDim2.new(r, 0, 1, 0)
    end
    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            seekFromInput(i.Position.X)
        end
    end)
    track.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            seekFromInput(i.Position.X)
        end
    end)
    self._seekFromInput = seekFromInput

    -- ── 滚轮调音量（不占任何 UI） ────────────────────────────────
    local function onWheel(i)
        if i.UserInputType ~= Enum.UserInputType.MouseWheel then return end
        local v = math.clamp(self.volume + (i.Position.Z > 0 and 0.05 or -0.05), 0, 1)
        self:SetVolume(v)
        if self.engine then self.engine.SetVolume(v) end
    end
    root.InputChanged:Connect(onWheel)
    for _, b in ipairs({ btnPlay, btnPrev, btnNext, btnVol, btnExpand, btnClose }) do
        b.InputChanged:Connect(onWheel)
    end

    -- ── 拖拽 + 吸附 ─────────────────────────────────────────────
    local dragStart, startPos = nil, nil
    root.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart = i.Position
            startPos = Vector2.new(root.AbsolutePosition.X, root.AbsolutePosition.Y)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragStart then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - dragStart
        if math.abs(d.X) + math.abs(d.Y) < 4 then return end
        root.AnchorPoint = Vector2.new(0, 0)
        root.Position = UDim2.new(0, startPos.X + d.X, 0, startPos.Y + d.Y)
        self.dock = nil
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 and i.UserInputType ~= Enum.UserInputType.Touch then return end
        if dragStart and self.dock == nil then
            local d = i.Position - dragStart
            if math.abs(d.X) + math.abs(d.Y) > 4 then
                self:SetDock(nearestDock(root.AbsolutePosition, root.AbsoluteSize))
            end
        end
        dragStart = nil
    end)

    -- ── 按钮接线 ────────────────────────────────────────────────
    btnPlay.MouseButton1Click:Connect(function()
        snd("Click", 0.12)
        if self.engine then self.engine.Toggle() end
    end)
    btnPrev.MouseButton1Click:Connect(function() snd("Click", 0.12) if self.engine then self.engine.Prev() end end)
    btnNext.MouseButton1Click:Connect(function() snd("Click", 0.12) if self.engine then self.engine.Next() end end)
    btnVol.MouseButton1Click:Connect(function()
        snd("Click", 0.12)
        self.volume = (self.volume > 0.01) and 0 or 0.6
        if self.engine then self.engine.SetVolume(self.volume) end
        btnVol:ClearAllChildren()
        Util.Create("UICorner", { Parent = btnVol, CornerRadius = UDim.new(0, 6) })
        makeIcon(btnVol, self.volume > 0.01 and "Volume" or "Mute", 13, themeColor(Q, "TextDim"), 65)
    end)
    btnExpand.MouseButton1Click:Connect(function()
        snd("Click", 0.12)
        if opts.OnExpand then opts.OnExpand(self) end
    end)
    btnClose.MouseButton1Click:Connect(function()
        snd("Click", 0.12)
        self:Hide()
        if opts.OnClose then opts.OnClose(self) end
    end)

    -- ── 对外方法 ────────────────────────────────────────────────
    function self:SetDock(name)
        local a = DOCK_ANCHORS[name]
        if not a then return end
        self.dock = name
        root.AnchorPoint = Vector2.new(a.ax, a.ay)
        Util.Tween(root, { Position = UDim2.new(a.ax, a.ox, a.ay, a.oy) }, 0.22)
    end

    function self:SetWidth(w)
        W = w
        root.Size = UDim2.new(0, w, 0, H)
        title.Size = UDim2.new(1, -200, 0, 15)
        sub.Size = UDim2.new(1, -200, 0, 13)
    end

    -- 状态文案（缓冲中/取直链失败…）单独走，不覆盖歌手名
    function self:SetStatus(s)
        self.status = s
        if type(s) == "string" and s ~= "" then
            sub.Text = s
            sub.TextColor3 = themeColor(Q, "Accent")
        else
            sub.Text = self.artist or ""
            sub.TextColor3 = themeColor(Q, "TextDim")
        end
    end

    function self:SetSong(song)
        song = song or {}
        title.Text = song.Title or song.title or opts.EmptyText or "未在播放"
        self.artist = song.Artist or song.artist or ""
        if not (type(self.status) == "string" and self.status ~= "") then
            sub.Text = self.artist
        end
        local coverSrc = song.Cover or song.cover
        if type(coverSrc) == "string" and coverSrc ~= "" then
            coverImg.Image = coverSrc
            coverImg.Visible = true
            self.coverIcon.Visible = false
        else
            coverImg.Visible = false
            self.coverIcon.Visible = true
        end
    end

    function self:SetPlaying(on)
        self.playing = on and true or false
        btnPlay:ClearAllChildren()
        Util.Create("UICorner", { Parent = btnPlay, CornerRadius = UDim.new(0, 6) })
        makeIcon(btnPlay, self.playing and "Pause" or "Play", 14, themeColor(Q, "TextBright"), 65)
        fill.BackgroundColor3 = self.playing and themeColor(Q, "Accent") or themeColor(Q, "TextFaint")
    end

    function self:SetProgress(pos, len)
        self.pos, self.len = pos or 0, len or 0
        local r = (self.len > 0) and math.clamp(self.pos / self.len, 0, 1) or 0
        if not dragging then fill.Size = UDim2.new(r, 0, 1, 0) end
    end

    function self:SetVolume(v)
        self.volume = math.clamp(v or 0, 0, 1)
    end

    -- 唤醒：从「淡出档」恢复到常态档（切歌、刚展开、外部想提示用户时调）
    function self:Wake(hold)
        self._hoverUntil = os.clock() + (hold or self.awayDelay)
        Util.Tween(root, { BackgroundTransparency = self.idleAlpha }, 0.25)
        Util.Tween(stroke, { Transparency = 0.55 }, 0.25)
    end

    function self:Show() root.Visible = true end
    function self:Hide() root.Visible = false end
    function self:IsVisible() return root.Visible end
    function self:Toggle() root.Visible = not root.Visible end
    function self:GetFrame() return root end

    function self:Destroy()
        self.alive = false
        pcall(function() root:Destroy() end)
    end

    -- ── 接标准后端 ──────────────────────────────────────────────
    function self:Bind(engine, bopts)
        self.engine = engine
        bopts = bopts or {}
        if bopts.Volume then self:SetVolume(bopts.Volume) engine.SetVolume(self.volume) end
        self:SetDock(self.dock or "Top")
        task.spawn(function()
            local lastId, lastStatus = nil, nil
            while self.alive do
                task.wait(bopts.PollInterval or 0.25)
                local ok, st = pcall(function() return engine.GetState() end)
                if ok and st then
                    self:SetPlaying(st.playing)
                    self:SetProgress(st.pos, st.len)
                    local song = st.song
                    if song and song.id ~= lastId then
                        lastId = song.id
                        self:SetSong({ Title = song.name, Artist = song.artist,
                                       Cover = song.cover })
                        self:Wake()   -- 换歌时闪一下，让用户知道切了
                    elseif not song and lastId ~= "none" then
                        lastId = "none"
                        self:SetSong({})
                    end
                    if st.status ~= lastStatus then
                        lastStatus = st.status
                        self:SetStatus(st.status)
                    end
                end
            end
        end)
        return self
    end

    function self:BindNetease(bopts)
        local g = (getgenv and getgenv()) or _G
        local ncm = g and g.NCM
        if not ncm then return nil, "getgenv().NCM 不存在：先加载 netease-engine.lua" end
        local eng, err = MusicUI.neteaseEngine(ncm)
        if not eng then return nil, err end
        return self:Bind(eng, bopts)
    end

    self:SetPlaying(false)
    self:SetDock(self.dock)
    root.Visible = (opts.Visible ~= false)
    return self
end

-- 用法：MusicUI.CreateMiniBar(QuantumUI, { Dock = "Top", Width = 400 })
--       MusicUI.CreateMiniBar({ Dock = "Bottom" })   -- 不传实例则用 Q.ScreenGui
function MusicUI.CreateMiniBar(a, b)
    local cls, opts
    if type(a) == "table" and (a.ScreenGui or a.MainFrame) then cls, opts = a, (b or {})
    else cls, opts = Q, (a or {}) end
    local host = opts.Parent or (cls and cls.ScreenGui)
    if not host then return nil, "找不到宿主 ScreenGui：先创建 QuantumUI 窗口，或用 opts.Parent 指定" end
    if cls and cls ~= Q then bindInternals(cls) end
    return buildMiniBar(host, opts)
end
-- ══════════════════════════════════════════════════════════════════
--  右侧歌词浮层（v1.4）
--    贴屏幕右侧竖排显示歌词，逐行高亮 + 自动滚动。
--    两个关键开关：
--      · Transparency —— 背景与文字的整体透明度
--      · BlockInput   —— 关（默认）= 全部元素 Active=false，鼠标事件穿透，
--                        完全不挡操作；开 = 可拖动、可点歌词行跳转
-- ══════════════════════════════════════════════════════════════════

local function buildLyricsOverlay(host, opts)
    opts = opts or {}
    local accent = themeColor(Q, "Accent")
    local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local W = opts.Width or 320
    local H = math.min(opts.Height or math.floor(vp.Y * 0.6), vp.Y - 120)
    local side = opts.Side or "Right"
    local xPos = (side == "Left") and UDim2.new(0, 12, 0.5, 0)
                              or UDim2.new(1, -W - 12, 0.5, 0)

    local self = {
        alive = true, lines = {}, index = nil,
        transparency = opts.Transparency or 0.35,
        blockInput = opts.BlockInput == true,
        fadeIdle = opts.FadeIdle ~= false,
        idleAlpha = opts.IdleAlpha or 0.75,
        fadeDelay = opts.FadeDelay or 6,
        _activeUntil = os.clock() + (opts.FadeDelay or 6),
    }

    local root = Util.Create("Frame", {
        Parent = host, Name = "LyricsOverlay",
        BackgroundColor3 = themeColor(Q, "MainBg"),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(0, W, 0, H),
        Position = xPos,
        AnchorPoint = Vector2.new(0, 0.5),
        Active = false, ClipsDescendants = false, ZIndex = 30,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 12) }) })
    self.frame = root
    local bg = Util.Create("Frame", {
        Parent = root, BackgroundColor3 = themeColor(Q, "MainBg"),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), ZIndex = 30, Active = false,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 12) }) })
    self.bg = bg
    local stroke = Util.Create("UIStroke", {
        Parent = bg, Color = accent, Thickness = 1, Transparency = 0.75,
    })
    self.stroke = stroke

    local scroll = Util.Create("ScrollingFrame", {
        Parent = root, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -16, 1, -16), Position = UDim2.new(0, 8, 0, 8),
        CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 0,
        ScrollingEnabled = opts.Scrollable ~= false, ZIndex = 31, Active = false,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, {
        Util.Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            Padding = UDim.new(0, 10),
        }),
        Util.Create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 40) }),
    })
    self.scroll = scroll
    local layout = scroll:FindFirstChildOfClass("UIListLayout")
    if layout then
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 60)
        end)
    end

    local empty = Util.Create("TextLabel", {
        Parent = root, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.5, -15),
        Font = Enum.Font.Gotham, Text = opts.EmptyText or "暂无歌词",
        TextColor3 = themeColor(Q, "TextFaint"), TextSize = 12, ZIndex = 32, Active = false,
    })
    self.empty = empty

    -- ── 透明度 / 穿透 ───────────────────────────────────────────
    local function applyAlpha()
        local t = self.transparency
        bg.BackgroundTransparency = math.clamp(t + 0.15, 0, 1)
        stroke.Transparency = math.clamp(t + 0.5, 0, 1)
        for _, lab in ipairs(self.labels or {}) do
            local isCur = (lab.LayoutOrder == self.index)
            lab.TextTransparency = isCur and math.clamp(t, 0, 1) or math.clamp(t + 0.18, 0, 1)
        end
        empty.TextTransparency = math.clamp(t + 0.15, 0, 1)
    end
    self._applyAlpha = applyAlpha

    local function applyInput()
        local blk = self.blockInput
        root.Active = blk
        bg.Active = false
        scroll.Active = blk
        scroll.ScrollingEnabled = blk and opts.Scrollable ~= false
        empty.Active = false
        for _, lab in ipairs(self.labels or {}) do
            lab.Active = blk
        end
    end
    self._applyInput = applyInput

    -- ── 渲染歌词 ────────────────────────────────────────────────
    function self:SetLines(lines)
        self.lines = type(lines) == "table" and lines or {}
        for _, lab in ipairs(self.labels or {}) do pcall(function() lab:Destroy() end) end
        self.labels = {}
        self.index = nil
        empty.Visible = (#self.lines == 0)
        for i, l in ipairs(self.lines) do
            local lab = Util.Create("TextLabel", {
                Parent = scroll, BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, -8, 0, 20), LayoutOrder = i,
                Font = Enum.Font.GothamMedium, Text = l.text or "",
                TextColor3 = themeColor(Q, "TextBright"), TextSize = 13,
                TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center,
                ZIndex = 32, Active = false,
            })
            lab.MouseButton1Click:Connect(function()
                if self.blockInput and self.engine then self.engine.Seek(l.t or 0) end
            end)
            self.labels[i] = lab
        end
        applyAlpha()
        applyInput()
    end

    function self:Seek(pos)
        if #self.labels == 0 then return end
        local idx = nil
        for i, l in ipairs(self.lines) do
            if (l.t or 0) <= (pos or 0) then idx = i else break end
        end
        if idx == self.index then return end
        self.index = idx
        for i, lab in ipairs(self.labels) do
            local isCur = (i == idx)
            lab.Font = isCur and Enum.Font.GothamBold or Enum.Font.GothamMedium
            lab.TextSize = isCur and 15 or 13
            lab.TextColor3 = isCur and accent or themeColor(Q, "TextBright")
            lab.TextTransparency = isCur and math.clamp(self.transparency, 0, 1)
                                           or math.clamp(self.transparency + 0.18, 0, 1)
        end
        -- 自动把当前行滚到中间
        if idx and self.labels[idx] and opts.AutoScroll ~= false then
            local lab = self.labels[idx]
            local target = lab.AbsolutePosition.Y - root.AbsolutePosition.Y
                - (root.AbsoluteSize.Y / 2 - lab.AbsoluteSize.Y / 2)
            Util.Tween(scroll, { CanvasPosition = Vector2.new(0, math.max(0, scroll.CanvasPosition.Y + target)) }, 0.35)
        end
    end

    -- ── 对外方法 ────────────────────────────────────────────────
    function self:SetTransparency(t)
        self.transparency = math.clamp(t or 0, 0, 1)
        applyAlpha()
    end
    function self:SetBlockInput(b)
        self.blockInput = b == true
        applyInput()
    end
    function self:IsBlockingInput() return self.blockInput end
    function self:SetSide(s)
        side = (s == "Left") and "Left" or "Right"
        root.Position = (side == "Left") and UDim2.new(0, 12, 0.5, 0)
                                            or UDim2.new(1, -W - 12, 0.5, 0)
    end
    function self:Show() root.Visible = true end
    function self:Hide() root.Visible = false end
    function self:Toggle() root.Visible = not root.Visible end
    function self:IsVisible() return root.Visible end
    function self:GetFrame() return root end
    function self:Destroy() self.alive = false pcall(function() root:Destroy() end) end

    -- 闲置淡出（只在开启 blockInput 时才有意义：不挡操作时本来就无感）
    task.spawn(function()
        while self.alive do
            task.wait(0.5)
            if self.fadeIdle and not self.blockInput then
                if os.clock() > self._activeUntil and self.transparency < self.idleAlpha - 0.01 then
                    self:SetTransparency(self.idleAlpha)
                end
            end
        end
    end)

    -- 拖动（仅在 blockInput = true 时可拖）
    local dragStart, startPos = nil, nil
    root.InputBegan:Connect(function(i)
        if not self.blockInput then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart = i.Position
            startPos = Vector2.new(root.AbsolutePosition.X, root.AbsolutePosition.Y)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragStart or not self.blockInput then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - dragStart
        if math.abs(d.X) + math.abs(d.Y) < 6 then return end
        root.AnchorPoint = Vector2.new(0, 0)
        root.Position = UDim2.new(0, startPos.X + d.X, 0, startPos.Y + d.Y)
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart = nil
        end
    end)

    -- ── 接后端：自动跟随歌词 ────────────────────────────────────
    function self:Bind(engine, bopts)
        self.engine = engine
        bopts = bopts or {}
        task.spawn(function()
            local lastId, lastIdx, miss = nil, nil, nil
            while self.alive do
                task.wait(bopts.PollInterval or 0.25)
                local ok, st = pcall(function() return engine.GetState() end)
                if ok and st then
                    local song = st.song
                    if song and song.id ~= lastId then
                        lastId = song.id
                        local lines = engine.Lyric and engine.Lyric() or nil
                        self:SetLines(lines)
                        miss = lines and nil or 0
                        lastIdx = nil
                    elseif song and #self.lines == 0 and (miss or 0) < 200        -- 约 50s：下载一首歌可能就要 17s then
                        miss = (miss or 0) + 1
                        self:SetLines(engine.Lyric and engine.Lyric() or nil)
                    end
                    local _, idx = engine.LyricAt and engine.LyricAt(st.pos or 0)
                    if idx and idx ~= lastIdx then
                        lastIdx = idx
                        self:Seek(st.pos or 0)
                    end
                end
            end
        end)
        return self
    end

    function self:BindNetease(bopts)
        local g = (getgenv and getgenv()) or _G
        local ncm = g and g.NCM
        if not ncm then return nil, "getgenv().NCM 不存在" end
        local eng, err = MusicUI.neteaseEngine(ncm)
        if not eng then return nil, err end
        return self:Bind(eng, bopts)
    end

    self:SetTransparency(self.transparency)
    self:SetBlockInput(self.blockInput)
    root.Visible = (opts.Visible ~= false)
    return self
end

-- 用法：MusicUI.CreateLyricsOverlay(QuantumUI, { Side="Right", Transparency=0.35,
--                                              BlockInput=false })
function MusicUI.CreateLyricsOverlay(a, b)
    local cls, opts
    if type(a) == "table" and (a.ScreenGui or a.MainFrame) then cls, opts = a, (b or {})
    else cls, opts = Q, (a or {}) end
    local host = opts.Parent or (cls and cls.ScreenGui)
    if not host then return nil, "找不到宿主 ScreenGui" end
    if cls and cls ~= Q then bindInternals(cls) end
    return buildLyricsOverlay(host, opts)
end

-- ══════════════════════════════════════════════════════════════════
--  中央调配菜单（v1.4）
--    屏幕正中央展开的面板，左侧导航「界面 / 音乐」。
--    界面页驱动 source.lua 的主题/风格/布局/边框/窗口透明度；
--    音乐页管播放、音量、歌词浮层、迷你条。
--    控件是轻量自绘：步进器(◀ 值 ▶) / 胶囊开关 / 细滑块 —— 与悬浮窗同款语言。
-- ══════════════════════════════════════════════════════════════════

local function cmRow(parent, order, h)
    return Util.Create("Frame", {
        Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, h or 34), LayoutOrder = order, Active = false,
    })
end

local function cmLabel(parent, text, w)
    return Util.Create("TextLabel", {
        Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, w or 104, 1, 0), Position = UDim2.new(0, 0, 0, 0),
        Font = Enum.Font.Gotham, Text = text,
        TextColor3 = themeColor(Q, "TextDim"), TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 62,
    })
end

local function cmSection(parent, order, text)
    local row = cmRow(parent, order, 26)
    Util.Create("TextLabel", {
        Parent = row, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, Text = text,
        TextColor3 = themeColor(Q, "TextFaint"), TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 62,
    })
    Util.Create("Frame", {
        Parent = row, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.9, BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 0, 1), Position = UDim2.new(0, 0, 1, -2), ZIndex = 62,
    })
    return row
end

-- 步进器：◀ 当前值 ▶
local function cmStepper(parent, order, label, values, getIndex, onPick)
    local row = cmRow(parent, order, 34)
    cmLabel(row, label)
    local accent = themeColor(Q, "Accent")
    local val = Util.Create("TextLabel", {
        Parent = row, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, 110, 1, 0), Position = UDim2.new(1, -128, 0, 0),
        Font = Enum.Font.GothamMedium, Text = "",
        TextColor3 = themeColor(Q, "TextBright"), TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62,
    })
    local btnR = mkIconButton(row, 22, -6, "Next", 11, true, 62)
    local btnL = mkIconButton(row, 22, -140, "Prev", 11, true, 62)
    local function sync()
        local i = math.clamp(getIndex() or 1, 1, math.max(1, #values))
        val.Text = values[i] or "—"
    end
    local function step(d)
        local n = #values
        if n == 0 then return end
        local i = ((math.clamp(getIndex() or 1, 1, n) - 1 + d) % n) + 1
        onPick(i, values[i])
        sync()
    end
    btnL.MouseButton1Click:Connect(function() snd("Click", 0.1) step(-1) end)
    btnR.MouseButton1Click:Connect(function() snd("Click", 0.1) step(1) end)
    sync()
    return { row = row, sync = sync, value = val, accent = accent }
end

-- 胶囊开关
local function cmSwitch(parent, order, label, get, onSet)
    local row = cmRow(parent, order, 34)
    cmLabel(row, label)
    local accent = themeColor(Q, "Accent")
    local pill = Util.Create("TextButton", {
        Parent = row, BackgroundColor3 = themeColor(Q, "ControlAlt"),
        BackgroundTransparency = 0.1, BorderSizePixel = 0, Text = "",
        Size = UDim2.new(0, 36, 0, 20), Position = UDim2.new(1, -6, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5), ZIndex = 62, AutoButtonColor = false,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local knob = Util.Create("Frame", {
        Parent = pill, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0, Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 63,
    }, { Util.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local on = false
    local function paint()
        pill.BackgroundColor3 = on and accent or themeColor(Q, "ControlAlt")
        Util.Tween(knob, { Position = on and UDim2.new(1, -2, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) }, 0.15)
    end
    local function sync() on = get() and true or false paint() end
    pill.MouseButton1Click:Connect(function()
        snd("Click", 0.1)
        on = not on
        paint()
        onSet(on)
    end)
    sync()
    return { row = row, sync = sync, set = function(v) on = v and true or false paint() end }
end

-- 细滑块 + 数值
local function cmSlider(parent, order, label, minV, maxV, get, onSet, fmt)
    local row = cmRow(parent, order, 34)
    cmLabel(row, label)
    local val = Util.Create("TextLabel", {
        Parent = row, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, 54, 1, 0), Position = UDim2.new(1, -60, 0, 0),
        Font = Enum.Font.Gotham, Text = "", TextColor3 = themeColor(Q, "TextBright"),
        TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 62,
    })
    local function ratio(v)
        return math.clamp(((v or minV) - minV) / math.max(0.0001, maxV - minV), 0, 1)
    end
    local sl = mkSlider(row, {
        Size = UDim2.new(1, -230, 0, 3),
        Position = UDim2.new(0, 110, 0.5, 0),
        ZIndex = 62, Ratio = ratio(get()),
        OnChange = function(r)
            local v = minV + (maxV - minV) * r
            val.Text = fmt and fmt(v) or string.format("%.2f", v)
            onSet(v)
        end,
    })
    local function sync()
        local v = get()
        sl:SetRatio(ratio(v))
        val.Text = fmt and fmt(v) or string.format("%.2f", v or 0)
    end
    sync()
    return { row = row, sync = sync }
end

-- ── 主构建 ──────────────────────────────────────────────────────
local function buildControlMenu(host, cls, opts)
    opts = opts or {}
    local accent = themeColor(Q, "Accent")
    local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local W = math.min(opts.Width or 560, math.floor(vp.X * 0.94))
    local H = math.min(opts.Height or 400, math.floor(vp.Y * 0.86))

    local self = { alive = true, open = false, page = "界面", refs = {} }

    local backdrop = Util.Create("TextButton", {
        Parent = host, Name = "ControlMenuBackdrop", Text = "",
        BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 70, Visible = false, AutoButtonColor = false,
    })
    self.backdrop = backdrop

    local root = Util.Create("Frame", {
        Parent = host, Name = "ControlMenu",
        BackgroundColor3 = themeColor(Q, "MainBg"),
        BackgroundTransparency = 0.08, BorderSizePixel = 0,
        Size = UDim2.new(0, W, 0, H),
        Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
        Active = true, ZIndex = 72, Visible = false,
    }, {
        Util.Create("UICorner", { CornerRadius = UDim.new(0, 12) }),
        Util.Create("UIScale", { Scale = 1 }),
    })
    self.frame = root
    local scale = root:FindFirstChildOfClass("UIScale")
    self.scale = scale
    Util.Create("UIStroke", {
        Parent = root, Color = accent, Thickness = 1, Transparency = 0.5,
    })

    -- 标题
    Util.Create("TextLabel", {
        Parent = root, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -80, 0, 18), Position = UDim2.new(0, 16, 0, 12),
        Font = Enum.Font.GothamBold, Text = opts.Title or "调配菜单",
        TextColor3 = themeColor(Q, "TextBright"), TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 74,
    })
    local btnClose = mkIconButton(root, 22, -12, "Close", 12, true, 74)
    btnClose.Position = UDim2.new(1, -12, 0, 21)

    Util.Create("Frame", {
        Parent = root, BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.9, BorderSizePixel = 0,
        Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 0, 40), ZIndex = 74,
    })

    -- 左侧导航
    local NAV_W = 92
    local navHost = Util.Create("Frame", {
        Parent = root, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(0, NAV_W, 1, -56), Position = UDim2.new(0, 12, 0, 48), ZIndex = 74,
    })
    local content = Util.Create("ScrollingFrame", {
        Parent = root, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, -(NAV_W + 34), 1, -58), Position = UDim2.new(0, NAV_W + 22, 0, 48),
        CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 3,
        ScrollBarImageColor3 = accent, ScrollBarImageTransparency = 0.4, ZIndex = 74,
    }, {
        Util.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
    })
    self.content = content
    local clayout = content:FindFirstChildOfClass("UIListLayout")
    if clayout then
        clayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            content.CanvasSize = UDim2.new(0, 0, 0, clayout.AbsoluteContentSize.Y)
        end)
    end

    local navButtons = {}
    local PAGES = { "界面", "音乐" }
    local function selectPage(name)
        self.page = name
        for n, b in pairs(navButtons) do
            b.BackgroundTransparency = (n == name) and 0.75 or 1
            b.TextColor3 = (n == name) and themeColor(Q, "TextBright") or themeColor(Q, "TextFaint")
        end
        if self.buildPage then self:buildPage(name) end   -- 必须用冒号，否则 name 会被当成 self
    end
    for i, name in ipairs(PAGES) do
        local b = Util.Create("TextButton", {
            Parent = navHost, BackgroundColor3 = accent, BackgroundTransparency = 1,
            BorderSizePixel = 0, Text = name,
            Size = UDim2.new(1, 0, 0, 32), Position = UDim2.new(0, 0, 0, (i - 1) * 36),
            Font = Enum.Font.GothamMedium, TextSize = 12,
            TextColor3 = themeColor(Q, "TextFaint"), ZIndex = 75, AutoButtonColor = false,
        }, { Util.Create("UICorner", { CornerRadius = UDim.new(0, 8) }) })
        b.MouseButton1Click:Connect(function() snd("Click", 0.1) selectPage(name) end)
        navButtons[name] = b
    end
    self.navButtons = navButtons

    -- ── 界面页 ──────────────────────────────────────────────────
    local function buildUIPage()
        local I = (cls and cls.Internals) or {}
        local themes, styles, layouts = cls.ThemeOrder or {}, cls.StyleOrder or {}, cls.LayoutOrder or {}
        local borders, bmodes = I.BorderOrder or {}, I.BorderModes or {}
        local function names(list, disp)
            local out = {}
            for i, k in ipairs(list) do
                out[i] = disp and disp(k) or tostring(k)
            end
            return out
        end
        local themeNames = names(themes, function(k)
            local t = cls.Themes and cls.Themes[k]
            return t and t.DisplayName or k
        end)
        local styleNames = names(styles, function(k)
            local d = cls.StyleDisplay
            return d and d[k] or k
        end)
        local layoutNames = names(layouts, function(k)
            local d = cls.LayoutDisplay
            return d and d[k] or k
        end)
        local borderNames = names(borders, function(k)
            local m = bmodes[k]
            return m and m.DisplayName or k
        end)
        local function idxOf(list, key)
            for i, k in ipairs(list) do if k == key then return i end end
            return 1
        end

        local o = 0
        local function next()
            o = o + 1
            return o
        end

        -- 当前主题：Themes[k].Accent 与实例的 ThemeColor 比对（source.lua 不存主题名）
        -- 索引都「实时读当前值」，这样外部改了设置菜单也能跟着显示
        self.refs.theme = cmStepper(content, next(), "主题", themeNames,
            function()
                for i, k in ipairs(themes) do
                    local t = cls.Themes and cls.Themes[k]
                    if t and t.Accent == cls.ThemeColor then return i end
                end
                return 1
            end,
            function(i) cls:SwitchTheme(themes[i]) end)

        self.refs.style = cmStepper(content, next(), "风格", styleNames,
            function() return idxOf(styles, cls.StyleName or styles[1]) end,
            function(i) cls:SwitchStyle(styles[i]) end)
        self.refs.layout = cmStepper(content, next(), "布局", layoutNames,
            function() return idxOf(layouts, cls.CurrentLayout or layouts[1]) end,
            function(i) cls:SwitchLayout(layouts[i]) end)

        cmSection(content, next(), "边框")
        self.refs.border = cmStepper(content, next(), "边框风格", borderNames,
            function() return idxOf(borders, cls.BorderMode) end,
            function(i) cls:SetBorderMode(borders[i]) end)
        self.refs.borderOn = cmSwitch(content, next(), "动态边框",
            function()
                if cls.BorderEnabled ~= nil then return cls.BorderEnabled end
                return cls.RainbowEnabled ~= false
            end,
            function(v) cls:SetBorderEnabled(v) end)
        self.refs.borderSpeed = cmSlider(content, next(), "边框速度", 0.1, 5,
            function() return cls.RainbowSpeed or 1 end,
            function(v) cls:SetBorderSpeed(v) end,
            function(v) return string.format("%.1f", v) end)
        self.refs.borderThick = cmSlider(content, next(), "边框粗细", 1, 6,
            function() return cls.BorderThickness or 2 end,
            function(v) cls:SetBorderThickness(math.floor(v + 0.5)) end,
            function(v) return string.format("%d", math.floor(v + 0.5)) end)

        cmSection(content, next(), "窗口")
        self.refs.winAlpha = cmSlider(content, next(), "窗口透明度", 0, 1,
            function() return cls.Transparency or 0 end,
            function(v) if cls.SetTransparency then cls:SetTransparency(v) end end,
            function(v) return string.format("%.0f%%", v * 100) end)
    end

    -- ── 音乐页 ──────────────────────────────────────────────────
    local function buildMusicPage()
        local o = 0
        local function next()
            o = o + 1
            return o
        end
        local eng = opts.Engine
        local ly = opts.Lyrics
        local mini = opts.MiniBar

        -- 账号（只读）
        local accRow = cmRow(content, next(), 34)
        cmLabel(accRow, "账号")
        local accVal = Util.Create("TextLabel", {
            Parent = accRow, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0, 200, 1, 0), Position = UDim2.new(1, -6, 0, 0),
            Font = Enum.Font.Gotham, Text = "…", TextColor3 = themeColor(Q, "TextBright"),
            TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62,
        })
        task.spawn(function()
            if eng and eng.Login then
                local ok, a = pcall(function() return eng.Login() end)
                accVal.Text = (ok and a) and (tostring(a.nickname) .. " · " .. tostring(a.vipName)) or "未登录"
            else
                accVal.Text = "无引擎"
            end
        end)

        self.refs.playing = cmSwitch(content, next(), "播放 / 暂停",
            function() return opts.GetPlaying and opts.GetPlaying() or false end,
            function() if eng then eng.Toggle() end end)

        self.refs.volume = cmSlider(content, next(), "音量", 0, 1,
            function() return opts.GetVolume and opts.GetVolume() or 0.6 end,
            function(v) if eng then eng.SetVolume(v) end if opts.OnVolume then opts.OnVolume(v) end end,
            function(v) return string.format("%.0f%%", v * 100) end)

        cmSection(content, next(), "歌词浮层")
        self.refs.lyShow = cmSwitch(content, next(), "显示歌词",
            function() return ly and ly:IsVisible() or false end,
            function(v) if not ly then return end if v then ly:Show() else ly:Hide() end end)
        self.refs.lyAlpha = cmSlider(content, next(), "歌词透明度", 0, 1,
            function() return ly and ly.transparency or 0.35 end,
            function(v) if ly then ly:SetTransparency(v) end end,
            function(v) return string.format("%.0f%%", v * 100) end)
        self.refs.lyBlock = cmSwitch(content, next(), "歌词挡操作",
            function() return ly and ly:IsBlockingInput() or false end,
            function(v) if ly then ly:SetBlockInput(v) end end)
        Util.Create("TextLabel", {
            Parent = content, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 26), LayoutOrder = next(),
            Font = Enum.Font.Gotham, Text = "关闭后歌词只是浮层，鼠标点击会穿透到游戏",
            TextColor3 = themeColor(Q, "TextFaint"), TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 62,
        })

        cmSection(content, next(), "悬浮窗")
        self.refs.miniShow = cmSwitch(content, next(), "迷你播放条",
            function() return mini and mini:IsVisible() or false end,
            function(v) if not mini then return end if v then mini:Show() mini:Wake(8) else mini:Hide() end end)
        self.refs.panelShow = cmSwitch(content, next(), "完整音乐窗口",
            function() return opts.Panel and opts.Panel:IsVisible() or false end,
            function(v)
                local p = opts.Panel
                if not p then return end
                if v then p:Show() else p:Hide() end
            end)
    end

    function self:buildPage(name)
        for _, d in ipairs(content:GetChildren()) do
            if not d:IsA("UIListLayout") then pcall(function() d:Destroy() end) end
        end
        self.refs = {}
        if name == "界面" then buildUIPage() else buildMusicPage() end
    end

    -- ── 开 / 关 ─────────────────────────────────────────────────
    local function refresh()
        for _, r in pairs(self.refs) do
            if type(r) == "table" and r.sync then pcall(r.sync) end
        end
    end
    self.refresh = refresh

    function self:Open()
        if self.open then return end
        self.open = true
        self:buildPage(self.page)
        backdrop.Visible = true
        root.Visible = true
        scale.Scale = 0.92
        root.BackgroundTransparency = 1
        Util.Tween(scale, { Scale = 1 }, 0.22)
        Util.Tween(root, { BackgroundTransparency = 0.08 }, 0.22)
        Util.Tween(backdrop, { BackgroundTransparency = 0.55 }, 0.22)
    end

    function self:Close()
        if not self.open then return end
        self.open = false
        Util.Tween(scale, { Scale = 0.92 }, 0.16)
        Util.Tween(root, { BackgroundTransparency = 1 }, 0.16)
        Util.Tween(backdrop, { BackgroundTransparency = 1 }, 0.16)
        task.delay(0.18, function()
            if not self.open then root.Visible = false backdrop.Visible = false end
        end)
    end

    function self:Toggle()
        if self.open then self:Close() else self:Open() end
    end
    function self:IsOpen() return self.open end
    function self:GetFrame() return root end
    function self:SetPage(name) selectPage(name) end
    function self:Destroy() self.alive = false pcall(function() root:Destroy() backdrop:Destroy() end) end

    btnClose.MouseButton1Click:Connect(function() snd("Click", 0.1) self:Close() end)
    backdrop.MouseButton1Click:Connect(function() self:Close() end)

    -- 标题栏拖动
    local dragStart, startPos = nil, nil
    root.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if i.Position.Y - root.AbsolutePosition.Y > 44 then return end   -- 只在标题栏拖
            dragStart = i.Position
            startPos = Vector2.new(root.AbsolutePosition.X, root.AbsolutePosition.Y)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if not dragStart then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = i.Position - dragStart
        if math.abs(d.X) + math.abs(d.Y) < 6 then return end
        root.AnchorPoint = Vector2.new(0, 0)
        root.Position = UDim2.new(0, startPos.X + d.X, 0, startPos.Y + d.Y)
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart = nil
        end
    end)

    -- 热键
    local key = opts.Key or Enum.KeyCode.RightShift
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == key then self:Toggle() end
    end)
    self.key = key

    selectPage(self.page)
    return self
end

-- 用法：MusicUI.CreateControlMenu(QuantumUI, { Engine=..., Lyrics=..., MiniBar=..., Panel=... })
function MusicUI.CreateControlMenu(a, b)
    local cls, opts
    if type(a) == "table" and (a.ScreenGui or a.MainFrame) then cls, opts = a, (b or {})
    else cls, opts = Q, (a or {}) end
    local host = opts.Parent or (cls and cls.ScreenGui)
    if not host then return nil, "找不到宿主 ScreenGui" end
    if cls and cls ~= Q then bindInternals(cls) end
    return buildControlMenu(host, cls, opts)
end

function MusicUI.Attach(cls)
    if type(cls) ~= "table" then
        error("[MusicUI] Attach(QuantumUI) 需要传入 QuantumUI 类表")
    end
    bindInternals(cls)
    installCreateMusicWindow(cls)
    installAddMusicTab(cls)
    musicSelectHook(cls)
    cls.MusicUI = MusicUI
    return MusicUI
end

-- 便捷：local MusicUI = loadstring(src)()(QuantumUI)
setmetatable(MusicUI, {
    __call = function(_, cls)
        return MusicUI.Attach(cls)
    end,
})

MusicUI.Draw   = Draw
MusicUI.Icons  = IconBuilders
MusicUI.Util   = function() return Util end
MusicUI.fmtTime = fmtTime

return MusicUI
