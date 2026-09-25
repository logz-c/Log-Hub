--[[
    music-loader.lua —— 一行 loadstring 拉起整套音乐界面

        loadstring(game:HttpGet("https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/music-loader.lua"))()

    做的事：
      1. 以 Headless 模式启动网易云引擎（不建它自带的老 UI）
      2. 加载 source.lua（QuantumUI）与 music.lua（MusicUI）
      3. 建主窗口 + 迷你播放条 + 完整音乐窗口 + 右侧歌词浮层 + 中央调配菜单
      4. 把三者都接到引擎上（自动同步播放态 / 进度 / 歌词）

    加载前可以先设配置（都是可选的）：
        getgenv().MusicLoader = {
            Title        = "Log-Hub",              -- 主窗口标题
            Size         = UDim2.new(0, 520, 0, 600),
            MiniBar      = true,                   -- 迷你播放条
            MiniDock     = "Top",                  -- Top/Bottom/TopLeft/TopRight/BottomLeft/BottomRight
            Panel        = true,                   -- 完整音乐窗口（默认建好但隐藏）
            Lyrics       = true,                   -- 右侧歌词浮层
            LyricsSide   = "Right",
            LyricsAlpha  = 0.30,                   -- 歌词透明度 0..1
            LyricsBlock  = false,                  -- false = 不挡操作（鼠标穿透）
            Menu         = true,                   -- 中央调配菜单
            MenuKey      = Enum.KeyCode.RightShift,
            ShowHub      = true,                   -- 是否显示主窗口
        }

    加载后可以拿到所有对象：
        getgenv().MusicHub = { Win, MusicUI, Engine, Mini, Panel, Lyrics, Menu }
]]

local BASE = "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/"
local CFG  = (getgenv and getgenv().MusicLoader) or {}
local function opt(k, d) local v = CFG[k] if v == nil then return d end return v end

-- ── 1. 引擎（Headless：只跑引擎，不建自带 UI）────────────────────
local g = (getgenv and getgenv()) or _G
g.NCM_OPTIONS = { Headless = true }
local engineErr = nil
local okE, eE = pcall(function()
    return loadstring(game:HttpGet(BASE .. "netease-engine.lua"))()
end)
if not okE then engineErr = tostring(eE) end
if not g.NCM and not engineErr then engineErr = "引擎未导出 getgenv().NCM" end

-- ── 2. UI 库 ────────────────────────────────────────────────────
local QuantumUI = loadstring(game:HttpGet(BASE .. "source.lua"))()
local MusicUI   = loadstring(game:HttpGet(BASE .. "music.lua"))()(QuantumUI)

-- ── 3. 主窗口 ───────────────────────────────────────────────────
local Win = QuantumUI.new({
    Title = opt("Title", "Log-Hub"),
    Size  = opt("Size", UDim2.new(0, 520, 0, 600)),
})

local Hub = { Win = Win, MusicUI = MusicUI, Engine = nil }

-- 引擎适配器（标准后端接口）
if g.NCM then
    local eng, err = MusicUI.neteaseEngine(g.NCM)
    if eng then Hub.Engine = eng else engineErr = err end
end
local eng = Hub.Engine

-- ── 4. 各形态 ───────────────────────────────────────────────────
local Mini, Panel, Lyrics, Menu

if opt("MiniBar", true) then
    Mini = MusicUI.CreateMiniBar(Win, { Dock = opt("MiniDock", "Top") })
    Hub.Mini = Mini
end

if opt("Panel", true) then
    Panel = MusicUI.CreateWindow(Win, {})
    Panel:Hide()
    Hub.Panel = Panel
end

if opt("Lyrics", true) then
    Lyrics = MusicUI.CreateLyricsOverlay(Win, {
        Side         = opt("LyricsSide", "Right"),
        Transparency = opt("LyricsAlpha", 0.30),
        BlockInput   = opt("LyricsBlock", false),
    })
    Hub.Lyrics = Lyrics
end

if opt("Menu", true) then
    Menu = MusicUI.CreateControlMenu(Win, {
        Title      = "调配菜单",
        Key        = opt("MenuKey", Enum.KeyCode.RightShift),
        Engine     = eng,
        Lyrics     = Lyrics,
        MiniBar    = Mini,
        Panel      = Panel,
        GetPlaying = function()
            if not eng then return false end
            local ok, st = pcall(function() return eng.GetState() end)
            return ok and st and st.playing or false
        end,
        GetVolume = function()
            if not eng then return 0.6 end
            local ok, st = pcall(function() return eng.GetState() end)
            return ok and st and st.volume or 0.6
        end,
        OnVolume = function(v)
            if eng then eng.SetVolume(v) end
            if Mini then Mini:SetVolume(v) end
            if Panel then Panel:SetVolume(v) end
        end,
    })
    Hub.Menu = Menu
end

-- ── 5. 全部接到引擎 ─────────────────────────────────────────────
if eng then
    if Mini   then Mini:Bind(eng)   end
    if Panel  then Panel:Bind(eng)  end
    if Lyrics then Lyrics:Bind(eng) end
end

-- ── 6. 收尾 ─────────────────────────────────────────────────────
if opt("ShowHub", true) == false and Win.MainFrame then
    Win.MainFrame.Visible = false
end

g.MusicHub = Hub

print(string.format("[MusicHub] 已加载  MusicUI v%s  迷你条=%s  窗口=%s  歌词=%s  菜单=%s%s",
    tostring(MusicUI.Version),
    Mini and "on" or "off", Panel and "on" or "off",
    Lyrics and "on" or "off", Menu and "on" or "off",
    engineErr and ("  引擎异常: " .. tostring(engineErr)) or ""))

return Hub
