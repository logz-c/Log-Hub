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

| 操作                     | 结果                                                  |
| ---------------------- | --------------------------------------------------- |
| 点击 MUSIC 页签            | 主窗口隐藏 + 音乐窗口出现（**二者不并存**）                           |
| 点音乐窗口的 ✕               | 音乐窗口关闭 + 主窗口恢复 + 回到上一个普通页签                          |
| 切到其它页签                 | 音乐窗口隐藏 + 主窗口恢复                                      |
| `Tab:OpenMusic()`      | 手动打开                                                |
| `Tab:CloseMusic()`     | 手动关闭并恢复主窗口                                          |
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

**双轨：已上传贴图（默认）+ 代码绘制（兜底）**

20 张图标已上传到 Roblox（白色图形 + 透明底，可被 `ImageColor3` 染色跟随主题），  
ID 写在 `music.lua` 顶部的 `UPLOADED` 表里，**默认就生效**，不需要任何配置：

```lua
local MusicUI = loadstring(game:HttpGet(MUSIC_URL))()(QuantumUI)  -- 直接是贴图版
```

| 开关                                       | 作用                            |
| ---------------------------------------- | ----------------------------- |
| `MusicUI.UseDrawnIcons()`                | 切回**代码绘制**图标（零资源、离线可用、不怕资产被删） |
| `MusicUI.UseUploadedIcons()`             | 切回上传贴图                        |
| `MusicUI.Assets.Play = "rbxassetid://…"` | 单独换某一张                        |

槽位一旦是 `rbxassetid://…`，`makeIcon` 就用 `ImageLabel`；留空则回退到绘制图标。  
`Cover` 是彩色图（深紫渐变 + 音符），由 `makeCover` 处理，**不会被 `ImageColor3` 染色**。

代码绘制版的原理：矩形 + 45° 旋转矩形被 `ClipsDescendants` 容器裁成三角，  
方角风格下同样好看，`paintIcon` 递归改子 Frame 的 `BackgroundColor3` 实现换色。  
内置：`Play Pause Prev Next Shuffle Repeat RepeatOne Heart HeartOn Search Clear Volume Mute
Queue Note Close Plus Trash Up Down`。

`MusicUI.Draw.Tri(parent, w, h, color, z, rot, cx, cy)` 也可单独调用来自绘三角。

完整 Asset ID 清单与「改形状 → 重新上传」的流程见  
[`../ui_assets/icons/README.md`](../ui_assets/icons/README.md)。

---

## 五、引擎绑定 —— 让音乐窗口真的能播歌（v1.1）

`music.lua` 本身**对音频后端零依赖**：控件只发回调。要真正出声，把任意实现下面这组
「标准后端接口」的对象接进来即可。

### 标准后端接口

| 方法 | 说明 |
|---|---|
| `Search(kw, limit) -> items[]` | items: `{Id, Title, Sub, Duration, Cover, Fav}` |
| `Play(item)` / `Toggle()` / `Next()` / `Prev()` | 播放控制 |
| `Seek(sec)` / `SetVolume(v)` | 进度与音量 |
| `SetQueue(items, index)` | 设置播放队列 |
| `GetState() -> {playing,pos,len,volume,index,count,status,song}` | 供 UI 轮询 |
| `Lyric() -> {{t=秒,text=…}}` | 歌词行（可空） |
| `Liked(force)` / `ToggleFav(item)` / `Login()` | 红心与登录态（可选） |

### 网易云：三行接入

```lua
local BASE = "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/"

-- 1) 引擎（Headless：只跑引擎，不建它自己的 UI）
getgenv().NCM_OPTIONS = { Headless = true }
loadstring(game:HttpGet(BASE .. "netease-engine.lua"))()

-- 2) UI 库
local QuantumUI = loadstring(game:HttpGet(BASE .. "source.lua"))()
local MusicUI   = loadstring(game:HttpGet(BASE .. "music.lua"))()(QuantumUI)

-- 3) 建窗口 + 一键绑定
local Win = QuantumUI.new({ Title = "My Hub" })
local Tab = Win:AddMusicTab({ Name = "MUSIC", Title = "♪ 网易云音乐",
                              WindowSize = UDim2.new(0, 400, 0, 620) })

local Ctl = MusicUI.BindNetease(Tab, { AutoLiked = false, SearchLimit = 30 })
Tab:OpenMusic()
```

`BindNetease` 会自动建好**播放卡片 / 搜索框 / 分类条 / 歌曲列表 / 红心列表 / 播放队列 /
歌词面板**，并把它们全部接线，同时起一个轮询把引擎状态同步回 UI
（播放态、进度、状态文案、歌词高亮、列表 `SetActive`）。

### 返回的控制器

```lua
Ctl.search("周杰伦")            -- 手动搜索
Ctl.playItem(item, list)        -- 播放某一项（list 作为队列）
Ctl.loadLiked()                 -- 拉云端红心
Ctl.setVolume(0.5)
Ctl.destroy()                   -- 停掉轮询
```

### 换成别的后端

```lua
local myEngine = {                      -- 只要实现接口，来源随意（本地文件 / 别的 API）
    Search = function(kw, n) return myItems end,
    Play   = function(item) ... end,
    Toggle = function() ... end,
    GetState = function() return { playing = true, pos = 12, len = 200 } end,
}
MusicUI.BindEngine(Tab, myEngine, {})
```

### 说明

- 引擎未加载时 `BindNetease` 返回 `nil, 原因`，不会报错。
- 网易云引擎未登录时只有免费歌能播（搜索结果的 ~17%）；登录后 100%。
  引擎启动会自动读 `NetMusicCfg/cookie.json` 恢复登录态。
- 本地收藏（`FavToggle` / `FavHas`）与云端红心是两套，互不影响。

---

## 六、迷你播放条 —— 保持在前台但不挡游玩（v1.2）

整块音乐窗口会盖住屏幕中央。如果你想让音乐控件**一直在前台、又不影响正常游玩**，
用迷你播放条：一条贴在屏幕边缘的细条，默认半透明，鼠标悬停才变实，
离开几秒后自动淡到几乎只剩轮廓。

```lua
local Bar = MusicUI.CreateMiniBar(Win, {
    Dock      = "Top",        -- Top/Bottom/TopLeft/TopRight/BottomLeft/BottomRight
    Width     = 400,          -- 实际会被夹到「视口 45%」以内（下限 240）
    Height    = 38,
    IdleAlpha = 0.35,         -- 常态透明度
    HoverAlpha= 0.02,         -- 鼠标移上去
    AwayAlpha = 0.62,         -- 闲置 N 秒后（还要能看清歌名，别调太高）
    AwayDelay = 5,
    OnExpand  = function(bar) end,   -- 点「展开」按钮
    OnClose   = function(bar) end,   -- 点「关闭」按钮
})

Bar:BindNetease()            -- 或 Bar:Bind(engine) 接任意标准后端
```

### 交互

| 操作 | 效果 |
|---|---|
| 鼠标移上去 | 变实（HoverAlpha），离开后回到常态，再闲置则淡出 |
| 拖整条 | 自由移动，松手**自动吸附**到最近的边缘/角落 |
| 点进度线 / 拖动 | 跳转播放位置 |
| **滚轮** | 直接调音量（不占任何 UI） |
| 点音量图标 | 静音 / 恢复 |
| 点展开 | 触发 `OnExpand`（可以在这里打开完整音乐窗口） |
| 换歌时 | 自动 `Wake()` 闪一下，提示用户切歌了 |

### 方法

```lua
Bar:SetDock("BottomRight")     -- 换停靠位（带动画）
Bar:SetWidth(360)
Bar:Wake(10)                   -- 从淡出档恢复到常态档，保持 10 秒
Bar:SetSong({Title=, Artist=, Cover=})
Bar:SetPlaying(true)  Bar:SetProgress(pos, len)  Bar:SetStatus("缓冲中…")
Bar:SetVolume(0.5)
Bar:Show()  Bar:Hide()  Bar:Toggle()  Bar:IsVisible()
Bar:GetFrame()  Bar:Destroy()
```

### 为什么「不影响游玩」

- **贴边不贴中心** —— 默认 Top 且下移 46px 避开 Roblox 顶栏，不挡准星
- **半透明** —— 常态 0.35，闲置 0.62，背后场景始终可见
- **占地小** —— 高度只有 38px，宽度自动夹在视口 45% 以内
- **不抢焦点** —— 没有输入框，滚轮调音量不弹面板

### 完整示例：只有迷你条在跑

```lua
local BASE = "https://raw.githubusercontent.com/logz-c/Log-Hub/main/SciFi-UI-Library/"

getgenv().NCM_OPTIONS = { Headless = true }
loadstring(game:HttpGet(BASE .. "netease-engine.lua"))()

local QuantumUI = loadstring(game:HttpGet(BASE .. "source.lua"))()
local MusicUI   = loadstring(game:HttpGet(BASE .. "music.lua"))()(QuantumUI)

local Win = QuantumUI.new({ Title = "My Hub" })
Win.MainFrame.Visible = false        -- 藏掉主窗口，只留迷你条

local Bar = MusicUI.CreateMiniBar(Win, { Dock = "Top" })
Bar:BindNetease()

-- 想播歌：直接用引擎，条会自动同步
local NCM = getgenv().NCM
local list = NCM.Search("周杰伦", 10)
NCM.SetQueue(list, 1)
NCM.Play(list[1])
```
