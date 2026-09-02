# exoskeleton volume → 外接盘(ext2) 每周自动同步

由 launchd 任务 `local.exoskeleton-volume-sync` 每周日 03:40 触发（pebble volume_sync
03:15 之后错峰）。ext2 常驻 Mac mini；当日未挂载则记日志跳过（exit 4）。

设计（两阶段 plan→apply、owner 元数据、严格单向、盘上归档保留）**与 pebble_space
`products/volume_sync/` 完全同源**——本目录的 `volume_sync` 即该脚本的适配副本，
仅改目标子目录名（`exoskeleton_volume`）。策略全文与多机工作流见
`~/pebble_space/products/volume_sync/README.md`，此处只记本仓差异：

- 源：`~/exoskeleton/volume/`（.gitignore 忽略，媒体成品与原始文件）
- 目标：`/Volumes/ext2/exoskeleton_volume/`（与 pebble_volume 平行，互不干扰）
- `syncignore`：只排除同步自身日志（volume-sync*，自反馈权，同 pebble）
- 自动化授权：用户明确授权的「常设确认」（同 pebble 模式），自动运行不再逐次看报告；
  想人工把关就手动 `./volume_sync plan /Volumes/ext2` 看报告再 apply。

## volume/ 目录约定（决策十二）

| 子目录 | 放什么 |
|---|---|
| `小红书/` | 图文成品（成图卡片、发布副本） |
| `视频/` | B站 / YouTube 成片、工程文件 |
| `录屏/` | OBS 原始录屏（S-001 等） |
| `截图/` | 素材截图（Bark、网站、viewer 等） |
| `文章/` | site posts 发布前的文章备份（`YYYYMMDD.{主题}.md`，决策十三） |

多机注意：首台运行同步的机器自动成为各子目录 owner（`.volume_meta`）。MBP 侧要写入
某子目录前，先在其中放 `.volume_meta`（`{"owner": "<mbp主机名>"}`）声明，否则 mini
同步会跳过 MBP 新建的目录（plan 报告会高亮）。

## 用法

```bash
scripts/volume_sync/sync-weekly.sh          # 手动触发一次完整两阶段同步
launchctl start local.exoskeleton-volume-sync
```

安装（新机器）：拷贝 `launchd/local.exoskeleton-volume-sync.plist` 到
`~/Library/LaunchAgents/`，核对 plist 内脚本绝对路径后 `launchctl load`。
日志：`volume/logs/volume-sync.log`。
