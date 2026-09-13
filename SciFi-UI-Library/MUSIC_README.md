# Quantum UI — MUSIC 分支

`SciFi-UI-Library/music.lua` · v1.0.0 · 在原有 uilib 上扩展的音乐专用分支。

---

## 加载

```lua
local SRC = "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/source.lua"
local MUS = "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/music.lua"

local QuantumUI = loadstring(game:HttpGet(SRC))()
local MusicUI   = loadstring(game:HttpGet(MUS))()(QuantumUI)   -- 挂载到类表

local Win = QuantumUI.new({Title = "My Hub"})
```

> `MusicUI` 也可以事后挂：`MusicUI.Attach(QuantumUI)`。
> `source.lua` 里新增了 `QuantumUI.Internals`（Utility / Sounds / CustomAssets / Themes / Mouse），
> 分支模块直接复用，不用重复实现。

---

## 一、AddMusicTab —— 音乐分支（默认弹出式）

```lua
local Tab = Win:AddMusicTab({
    Name = "MUSIC",                       -- 页签名
    Icon = "rbxassetid://6034287594",     -- 页签图标
    Title = "♪ 音乐",                      -- 弹出窗口标题（默认 ♪ + 页签名）
    WindowSize = UDim2.new(0, 400, 0, 560),
    WindowPosition = nil,                 -- 默认叠放在主窗口正上方
    Popup = true,                         -- false = 内联进主窗口页面
})
```

### 弹出模式（`Popup = true`，默认）

| 操作 | 结果 |
|---|---|
| 点击 MUSIC 页签 | 主窗口隐藏 + 音乐窗口出现（**二者不并存**） |
| 点音乐窗口的 ✕ | 音乐窗口关闭 + 主窗口恢复 + 回到上一个普通页签 |
| 切到其它页签 | 音乐窗口隐藏 + 主窗口恢复 |
| `Tab:OpenMusic()` | 手动打开 |
| `Tab:CloseMusic()` | 手动关闭并恢复主窗口 |
| `Tab:GetMusicWindow()` | 拿到窗口对象（`Show/Hide/Toggle/SetTitle/SetSize/Destroy`） |

### 内联模式（`Popup = false`）

内容直接铺在主窗口的页面里，行为与普通页签一致。

---

## 二、控件 API

所有方法的返回值都带完整实例方法，随便组合。

### `Tab:AddMusicPlayer(opts)` — 播放卡片

```lua
local Player = Tab:AddMusicPlayer({
    Height = 132,
    OnPlayPause = function(playing) end,
    OnPrev      = function() end,
    OnNext      = function() end,
    OnSeek      = function(sec) end,     -- 进度条拖拽/点击
    OnVolume    = function(v) end,       -- 0..1
    OnLike      = function(on) end,
    OnShuffle   = function(on) end,
    OnRepeat    = function(mode) end,    -- "off" / "all" / "one"
})

Player:SetSong({Id=1, Title="晴天", Artist="周杰伦", Duration=269, Cover=""})
Player:SetPlaying(true)
Player:SetProgress(96, 269)     -- 当前 / 总长
Player:SetBuffered(0.55)        -- 缓冲进度 0..1
Player:SetStatus("缓冲中…")
Player:SetLiked(true)
Player:SetVolume(0.7)
Player:SetShuffle(true)
Player:SetRepeatMode("all")
Player:SetCover("rbxassetid://…")
Player:IsPlaying()  Player:Duration()  Player:Position()  Player:GetVolume()
```

### `Tab:AddSearchBox(opts)` — 搜索框

```lua
local S = Tab:AddSearchBox({
    Placeholder = "搜索歌曲 / 歌手",
    Debounce = 0.35,              -- 0 = 每次输入立即回调
    OnSearch = function(text) end,
    OnClear  = function() end,
})
S:Get()  S:Set("周杰伦")  S:Focus()  S:SetPlaceholder("…")
```

### `Tab:AddSubTabs(list, cb, opts)` — 二级分类条

```lua
local Subs = Tab:AddSubTabs({"搜索","我喜欢的","播放列表","歌词"}, function(name)
    if name == "播放列表" then Tab:ShowPanel("Queue") else Tab:ShowPanel("Songs") end
end)
Subs:Select("搜索")  Subs:SelectSilent("搜索")  Subs:Get()  Subs:SetBadge("我喜欢的", 12)
```

### `Tab:AddPanel(name)` / `ShowPanel(name)` — 面板（互斥显示）

```lua
local P = Tab:AddPanel("Songs")
Tab:ShowPanel("Songs")   Tab:CurrentPanel()   Tab:GetPanel("Songs")
P:Clear()   P:Show()
```

### `Tab:AddSongList(opts)` — 歌曲列表

```lua
local List = Tab:AddSongList({
    Panel = "Songs", RowHeight = 58,
    ShowFav = true, ShowDuration = true,
    EmptyText = "暂无歌曲", LoadingText = "加载中…",
    OnSelect = function(item) end,      -- 点整行
    OnFav    = function(item, on) end,  -- 点爱心
    OnMenu   = function(item) end,      -- 点右侧 + 号（不传则不显示）
})

List:Set(items)          -- items: {Id, Title, Sub, Duration, Cover, Fav}
List:Add(item, index)
List:Remove(id)
List:Clear()
List:SetActive(id)       -- 高亮正在播放的那一行
List:SetFav(id, true)
List:SetSub(id, "新副标题")
List:SetLoading(true)
List:SetEmptyText("…")
List:Count()  List:Items()  List:Show()
```

### `Tab:AddLyricPanel(opts)` — 歌词面板

```lua
local Lyric = Tab:AddLyricPanel({
    Panel = "Lyrics", TextSize = 14, AutoScroll = true,
    OnLineClick = function(t, line) end,   -- 点某行跳转
})
Lyric:Set({{t=0.0,text="..."},{t=12.5,text="..."}})
Lyric:Seek(63.2)   -- 自动高亮当前行并滚动居中
Lyric:Clear()  Lyric:Show()
```

### `Tab:AddQueue(opts)` — 播放队列（上移/下移/删除）

```lua
local Queue = Tab:AddQueue({
    Panel = "Queue",
    OnSelect = function(item, i) end,
    OnRemove = function(item, i) end,
    OnMove   = function(i, delta) end,   -- delta = -1 / 1
})
Queue:Set(items)  Queue:Add(item)  Queue:Remove(id)  Queue:Clear()
Queue:SetActive(id)  Queue:Items()  Queue:Show()
```

### `Tab:AddAlbumGrid(opts)` — 封面宫格

```lua
local Grid = Tab:AddAlbumGrid({Panel="Albums", CellSize=88, Columns=0,
    OnSelect = function(item) end})
Grid:Set({{Id=1, Title="歌单", Sub="12 首", Cover=""}})
Grid:Add(item)  Grid:Clear()  Grid:Show()
```

### `Tab:AddChipBar(opts)` — 标签筛选条

```lua
local Chip = Tab:AddChipBar({Items={"华语","粤语","ACG"},
    OnChange = function(picked, name, on) end})
Chip:Set({"华语","英语"})  Chip:GetActive()  Chip:Clear()
```

### 标准控件直通

`Tab:AddSection / AddButton / AddToggle / AddDangerToggle / AddSlider / AddDropdown /
AddTextbox / AddColorPicker / AddKeybind / AddLabel / AddParagraph`
全部可用，第二个参数里传 `Panel = "面板名"` 决定塞到哪个面板。

```lua
Tab:AddToggle({Name="自动播放", Default=true, Panel="Songs", Callback=function(v) end})
```

---

## 三、`Win:CreateMusicWindow(opts)` — 独立浮动音乐窗口

不需要页签、直接开一个可拖动/可关闭的音乐窗口：

```lua
local MW = Win:CreateMusicWindow({
    Title = "♪ 播放器",
    Size = UDim2.new(0, 360, 0, 520),
    Position = UDim2.new(0.1, 0, 0.1, 0),
    OnClose = function() end,
})
MW:AddMusicPlayer({})  MW:AddSongList({})  -- 与 Tab 完全相同的 API
MW:Show()  MW:Hide()  MW:Toggle()  MW:IsVisible()
MW:SetTitle("…")  MW:SetSize(…)  MW:SetPosition(…)  MW:Destroy()
```

---

## 四、美术资源

**默认零外部资源** —— 所有图标都是代码绘制：矩形 + 45° 旋转矩形被 `ClipsDescendants`
容器裁成三角，方角风格（`USE_SQUARE_CORNERS`）下同样好看，且能通过 `paintIcon` 跟随主题换色。
内置：`Play Pause Prev Next Shuffle Repeat RepeatOne Heart HeartOn Search Clear Volume Mute
Queue Note Close Plus Trash Up Down`。

想换成自己上传的贴图，改 `MusicUI.Assets` 即可（控件自动从绘制图标切换成 `ImageLabel`）：

```lua
MusicUI.Assets.Play    = "rbxassetid://123456789"
MusicUI.Assets.HeartOn = "rbxassetid://123456790"
MusicUI.Assets.Cover   = "rbxassetid://…"   -- 默认封面占位图
MusicUI.Assets.Bg      = "rbxassetid://…"   -- 音乐页背景（可用主库 ui_assets/bg_panel.jpg）
```

`MusicUI.Draw.Tri(parent, w, h, color, z, rot, cx, cy)` 也可单独调用来自绘三角。
