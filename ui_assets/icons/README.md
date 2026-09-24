# Quantum UI — 图标贴图包

20 张 256×256 PNG，**白色图形 + 透明底**，上传到 Roblox 后可以用
`ImageColor3` 任意染色（跟随主题/风格/hover 状态）。

由 `_gen_icons.py`（工作区）生成：64×64 设计网格，4× 超采样后缩到 256，边缘抗锯齿。
要改形状就改那个脚本再重跑，别手改 PNG。

## 文件 → MusicUI.Assets 槽位对照

| 文件 | 槽位 | 用途 |
|---|---|---|
| `play.png` | `MusicUI.Assets.Play` | 播放 |
| `pause.png` | `MusicUI.Assets.Pause` | 暂停 |
| `prev.png` | `MusicUI.Assets.Prev` | 上一首 |
| `next.png` | `MusicUI.Assets.Next` | 下一首 |
| `shuffle.png` | `MusicUI.Assets.Shuffle` | 随机播放 |
| `repeat.png` | `MusicUI.Assets.Repeat` | 列表循环 |
| `repeat_one.png` | `MusicUI.Assets.RepeatOne` | 单曲循环 |
| `heart.png` | `MusicUI.Assets.Heart` / `.HeartOn` | 收藏（选中态靠染色区分） |
| `search.png` | `MusicUI.Assets.Search` | 搜索 |
| `clear.png` | `MusicUI.Assets.Clear` | 清空输入（圆圈+叉） |
| `close.png` | `MusicUI.Assets.Close` | 关闭窗口（纯叉） |
| `volume.png` | `MusicUI.Assets.Volume` | 音量 |
| `mute.png` | `MusicUI.Assets.Mute` | 静音 |
| `queue.png` | `MusicUI.Assets.Queue` | 队列 / 列表 |
| `note.png` | `MusicUI.Assets.Note` | 音符占位 |
| `plus.png` | `MusicUI.Assets.Plus` | 添加 / 更多 |
| `trash.png` | `MusicUI.Assets.Trash` | 删除 |
| `arrow_up.png` | `MusicUI.Assets.Up` | 上移 |
| `arrow_down.png` | `MusicUI.Assets.Down` | 下移 |
| `cover_placeholder.png` | `MusicUI.Assets.Cover` | 默认封面（自带深紫渐变底，**不要染色**） |

## 上传后怎么用

把下面这段贴到加载 music.lua 之后（ID 换成真实上传结果）：

```lua
local ID = {
    Play = 0, Pause = 0, Prev = 0, Next = 0,
    Shuffle = 0, Repeat = 0, RepeatOne = 0,
    Heart = 0, HeartOn = 0, Search = 0, Clear = 0,
    Close = 0, Volume = 0, Mute = 0, Queue = 0,
    Note = 0, Plus = 0, Trash = 0, Up = 0, Down = 0,
    Cover = 0,
}
for k, v in pairs(ID) do
    if v ~= 0 then
        MusicUI.Assets[k] = "rbxassetid://" .. tostring(v)
    end
end
```

槽位一旦填了 `rbxassetid://…`，`makeIcon` 就会自动从「代码绘制」切换成 `ImageLabel`，
不需要改任何控件代码。留空则继续用内置绘制图标（零资源、离线可用）。

> 注意 `Cover` 是彩色图，`makeIcon` 之外由 `makeCover` 处理，**不会被 ImageColor3 染色**。
