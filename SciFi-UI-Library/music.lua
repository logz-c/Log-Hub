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
MusicUI.Version = "1.0.0"

-- ═══════════════════════════════════════════════════════════════════
--  美术资源槽位：填 "rbxassetid://…" 覆盖；留空 = 使用内置绘制图标
-- ═══════════════════════════════════════════════════════════════════
MusicUI.Assets = {
    Play      = "",
    Pause     = "",
    Prev      = "",
    Next      = "",
    Shuffle   = "",
    Repeat    = "",
    RepeatOne = "",
    Heart     = "",
    HeartOn   = "",
    Search    = "",
    Clear     = "",
    Volume    = "",
    Mute      = "",
    Queue     = "",
    Note      = "",
    Close     = "",
    Plus      = "",
    Trash     = "",
    Up        = "",
    Down      = "",
    Cover     = "",   -- 默认封面（留空 = 绘制音符占位）
    Bg        = "",   -- 音乐页背景图（留空 = 纯色）
}

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
        showMainWindow(self, true)
        self._MusicOpenWindow = nil
        local back = self._MusicPrevTab
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
                showMainWindow(winSelf, true)
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
-- ═══════════════════════════════════════════════════════════════════
local function installCreateMusicWindow(cls)
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
