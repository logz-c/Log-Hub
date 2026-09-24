# Quantum UI — 图标贴图包

20 张 256×256 PNG，**白色图形 + 透明底**，已上传到 Roblox，可被 `ImageColor3`
任意染色（跟随主题 / 视觉风格 / hover 状态）。

由 `_gen_icons.py`（工作区）生成：64×64 设计网格 → 4× 超采样 → LANCZOS 缩到 256。
要改形状就改脚本再重跑、重传，别手改 PNG。

## 已上传的 Asset ID

`music.lua` 里的 `UPLOADED` 表就是这份清单（默认已启用，开箱即用）：

| 文件 | Asset ID | `MusicUI.Assets` 槽位 |
|---|---|---|
| `play.png` | `rbxassetid://114740604284026` | `Play` |
| `pause.png` | `rbxassetid://111792844682744` | `Pause` |
| `prev.png` | `rbxassetid://84496266493568` | `Prev` |
| `next.png` | `rbxassetid://84698543566466` | `Next` |
| `shuffle.png` | `rbxassetid://97719146198787` | `Shuffle` |
| `repeat.png` | `rbxassetid://104289200437812` | `Repeat` |
| `repeat_one.png` | `rbxassetid://105576549727493` | `RepeatOne` |
| `heart.png` | `rbxassetid://75603968806920` | `Heart` / `HeartOn` |
| `search.png` | `rbxassetid://80913948633532` | `Search` |
| `clear.png` | `rbxassetid://81810251029618` | `Clear`（圆圈+叉） |
| `close.png` | `rbxassetid://77309987267353` | `Close`（纯叉） |
| `volume.png` | `rbxassetid://102533846914077` | `Volume` |
| `mute.png` | `rbxassetid://105301103725420` | `Mute` |
| `queue.png` | `rbxassetid://72337420724977` | `Queue` |
| `note.png` | `rbxassetid://111780610859716` | `Note` |
| `plus.png` | `rbxassetid://122564974827162` | `Plus` |
| `trash.png` | `rbxassetid://109916746890494` | `Trash` |
| `arrow_up.png` | `rbxassetid://100978389702505` | `Up` |
| `arrow_down.png` | `rbxassetid://84206135890973` | `Down` |
| `cover_placeholder.png` | `rbxassetid://128130074289760` | `Cover`（彩色，**不染色**） |

## 用法

默认就走上传贴图，不用配任何东西：

```lua
local MusicUI = loadstring(game:HttpGet(MUSIC_URL))()(QuantumUI)
```

想切回内置「代码绘制」图标（零资源、离线可用）：

```lua
MusicUI.UseDrawnIcons()
```

切回来：

```lua
MusicUI.UseUploadedIcons()
```

单独换某一张：

```lua
MusicUI.Assets.Play = "rbxassetid://你的ID"
```

槽位一旦是 `rbxassetid://…`，`makeIcon` 就用 `ImageLabel`；留空则回退到绘制图标。
`Cover` 是彩色图，由 `makeCover` 处理，**不会被 `ImageColor3` 染色**。

## 重新上传

改完 `_gen_icons.py` 重跑后，用工作区的上传脚本（走 Roblox Studio 官方 MCP）：

```bash
# 1. 在 icons 目录起本地 HTTP 服务（StudioMCP 只能从 http 拉图）
cd Log-Hub/ui_assets/icons && python -m http.server 8731 --bind 127.0.0.1
# 2. 批量上传，结果写到 asset_id_map.json
python _upload_icons.py
```
