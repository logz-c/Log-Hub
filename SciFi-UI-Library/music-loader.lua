--[[
    ╔══════════════════════════════════════════════════════════════════╗
    ║  SciFi-UI-Library · MUSIC 加载器                                  ║
    ║  一行 loadstring 起全套：网易云引擎 + 迷你条 + 完整窗口            ║
    ║  + 右侧歌词浮层 + 中央调配菜单                                    ║
    ╚══════════════════════════════════════════════════════════════════╝

    用法（执行器里直接跑）：

        loadstring(game:HttpGet(
          "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/music-loader.lua"
        ))()

    想改默认行为，就复制整份到本地改 CONFIG，或先设覆盖：
        getgenv().MUSIC_LOADER_CONFIG = { MiniBar = { Dock = "Bottom" } }
        loadstring(...)()
]]

-- ══════════════════════════════════════════════════════════════════
--  配置
-- ══════════════════════════════════════════════════════════════════
local DEFAULTS = {
    Base = "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/",

    -- 主窗口（QuantumUI 的宿主窗口）。ShowHub = false 时只当容器用，不显示出来
    Window = { Title = "Log-Hub", ShowHub = false, Size = UDim2.new(0, 320, 0, 220) },

    -- 网易云引擎（Headless = 不建它自带的 UI，只提供播放能力）
    Engine = { Enable = true, Headless = true },

    -- 迷你播放条：一直在前台、半透明、不挡游玩
    MiniBar = { Enable = true, Dock = "Top" },

    -- 完整音乐窗口：搜索 / 列表 / 队列 / 歌词（默认不自动打开）
    Panel = { Enable = true, AutoOpen = false },

    -- 右侧歌词浮层
    Lyrics = {
        Enable = true, Side = "Right", Transparency = 0.30,
        BlockInput = false,   -- false = 鼠标穿透，不影响操作
        Width = 300,
    },

    -- 中央调配菜单（界面 + 音乐设置）
    Menu = { Enable = true, Key = "RightShift" },

    -- 启动后自动搜索并播第一首（留空 = 不自动播）
    AutoPlay = "",
}

-- 合并外部覆盖（只覆盖一层，够用了）
local CONFIG = {}
local override = (getgenv and getgenv().MUSIC_LOADER_CONFIG) or nil
for k, v in pairs(DEFAULTS) do
    if type(v) == "table" and type(override) == "table" and type(override[k]) == "table" then
        local merged = {}
        for kk, vv in pairs(v) do merged[kk] = vv end
        for kk, vv in pairs(override[k]) do merged[kk] = vv end
        CONFIG[k] = merged
    else
        CONFIG[k] = (type(override) == "table" and override[k] ~= nil) and override[k] or v
    end
end

local BASE = CONFIG.Base
local function LOG(...) print("[Music]", ...) end
local function WARN(...) warn("[Music]", ...) end
local g = (getgenv and getgenv()) or _G

-- 缓存破坏：保证每次拉到最新（raw.githubusercontent 会缓存）
local CB = "?v=" .. tostring(os.time())

local function fetch(name)
    local ok, txt = pcall(function() return game:HttpGet(BASE .. name .. CB) end)
    if not ok or type(txt) ~= "string" or #txt < 100 then
        return nil, "拉取 " .. name .. " 失败: " .. tostring(txt)
    end
    local fn, err = loadstring(txt)
    if not fn then return nil, "编译 " .. name .. " 失败: " .. tostring(err) end
    return fn
end

-- ══════════════════════════════════════════════════════════════════
--  1. 引擎
-- ══════════════════════════════════════════════════════════════════
local ncm = nil
if CONFIG.Engine.Enable then
    g.NCM_OPTIONS = { Headless = CONFIG.Engine.Headless }
    local fn, err = fetch("netease-engine.lua")
    if not fn then
        WARN(err)
    else
        local ok, e = pcall(fn)
        if not ok then WARN("引擎启动失败: " .. tostring(e)) end
        ncm = g.NCM
        if ncm then
            LOG("引擎就绪", ncm.version, CONFIG.Engine.Headless and "(Headless)" or "")
            local ok2, acc = pcall(function() return ncm.IsLoggedIn() end)
            if ok2 and acc then
                LOG("已登录:", acc.nickname, "·", acc.vipName)
            else
                LOG("未登录（只有免费歌能播，VIP 歌取不到直链）")
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════
--  2. UI 库 + 音乐模块
-- ══════════════════════════════════════════════════════════════════
local fSrc, errSrc = fetch("source.lua")
if not fSrc then WARN(errSrc) return end
local fMus, errMus = fetch("music.lua")
if not fMus then WARN(errMus) return end

local QuantumUI = fSrc()
local MusicUI = fMus()(QuantumUI)
LOG("QuantumUI", QuantumUI.Version, "· MusicUI", MusicUI.Version)

local Win = QuantumUI.new(CONFIG.Window)
task.wait(5)   -- 等主窗口初始化完（它会自己建 ScreenGui / 悬浮球）
if not CONFIG.Window.ShowHub then
    pcall(function() Win.MainFrame.Visible = false end)
    if Win.FloatingButton then pcall(function() Win.FloatingButton.Visible = false end) end
end

-- ══════════════════════════════════════════════════════════════════
--  3. 组件
-- ══════════════════════════════════════════════════════════════════
local API = { Win = Win, MusicUI = MusicUI, Engine = ncm }

local engine = nil
if ncm then engine = MusicUI.neteaseEngine(ncm) end

if CONFIG.MiniBar.Enable then
    local ok, bar = pcall(MusicUI.CreateMiniBar, Win, { Dock = CONFIG.MiniBar.Dock })
    if ok and bar then
        API.MiniBar = bar
        if engine then bar:Bind(engine) end
        LOG("迷你播放条已创建（" .. tostring(CONFIG.MiniBar.Dock) .. "）")
    else
        WARN("迷你播放条创建失败: " .. tostring(bar))
    end
end

if CONFIG.Panel.Enable then
    local ok, panel = pcall(MusicUI.CreateWindow, Win, {})
    if ok and panel then
        API.Panel = panel
        if engine then panel:Bind(engine) end
        if API.MiniBar then panel:SetMiniBar(API.MiniBar) end
        panel:Hide()
        if CONFIG.Panel.AutoOpen then panel:Show() end
        LOG("完整音乐窗口已创建")
    else
        WARN("完整音乐窗口创建失败: " .. tostring(panel))
    end
end

if CONFIG.Lyrics.Enable then
    local ok, ly = pcall(MusicUI.CreateLyricsOverlay, Win, CONFIG.Lyrics)
    if ok and ly then
        API.Lyrics = ly
        if engine then ly:Bind(engine) end
        LOG("歌词浮层已创建（" .. CONFIG.Lyrics.Side
            .. " · 透明度 " .. string.format("%.0f%%", CONFIG.Lyrics.Transparency * 100)
            .. " · " .. (CONFIG.Lyrics.BlockInput and "挡操作" or "鼠标穿透") .. "）")
    else
        WARN("歌词浮层创建失败: " .. tostring(ly))
    end
end

if CONFIG.Menu.Enable then
    local key = Enum.KeyCode[CONFIG.Menu.Key] or Enum.KeyCode.RightShift
    local ok, menu = pcall(MusicUI.CreateControlMenu, Win, {
        Key = key,
        Engine = engine, Lyrics = API.Lyrics, MiniBar = API.MiniBar, Panel = API.Panel,
        GetPlaying = function() return ncm and ncm.GetState().playing or false end,
        GetVolume  = function() return ncm and ncm.GetState().volume or 0.6 end,
        OnVolume   = function(v)
            if not ncm then return end
            ncm.SetVolume(v)
            if API.MiniBar then API.MiniBar:SetVolume(v) end
            if API.Panel then API.Panel:SetVolume(v) end
        end,
    })
    if ok and menu then
        API.Menu = menu
        LOG("调配菜单已创建（热键 " .. tostring(key.Name) .. "）")
    else
        WARN("调配菜单创建失败: " .. tostring(menu))
    end
end

-- ══════════════════════════════════════════════════════════════════
--  4. 自动播放
-- ══════════════════════════════════════════════════════════════════
if ncm and CONFIG.AutoPlay ~= "" then
    task.spawn(function()
        local ok, list = pcall(function() return ncm.Search(CONFIG.AutoPlay, 10) end)
        if ok and type(list) == "table" and #list > 0 then
            ncm.SetQueue(list, 1)
            ncm.Play(list[1])
            LOG("自动播放:", list[1].name, "-", list[1].artist)
        else
            WARN("自动播放搜索失败: " .. tostring(CONFIG.AutoPlay))
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════
--  5. 出口：getgenv().Music 之后可以随时手动控制
-- ══════════════════════════════════════════════════════════════════
g.Music = API
LOG("加载完毕。getgenv().Music 可用：")
LOG("  .MiniBar / .Panel / .Lyrics / .Menu / .Engine")
LOG("  Music.Menu:Toggle()          开/关调配菜单")
LOG("  Music.Lyrics:SetBlockInput(t) 歌词是否挡操作")
LOG("  Music.Lyrics:SetTransparency(t)")
LOG("  Music.Panel:Show()            打开完整音乐窗口")

return API
