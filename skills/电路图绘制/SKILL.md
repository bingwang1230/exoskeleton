---
name: draw-circuits
description: 用 schemdraw（Python 文本→PNG）画电路原理图、布局式对照图、芯片引脚地图的完整工作流：中文字体配置、已知渲染坑（.toy() 偏移/Ic 引脚反向/标签碰撞）、泛洪填充连通性程序化验收、http 服务交付。用户要「画电路图/原理图/引脚图/接线图」或 AI 需要向用户解释电路时用本技能。
---

# 电路图绘制（schemdraw 工作流）

用户看不懂 ASCII 电路图（明令禁止）；面包板实物图无成熟文本方案（用 HTML/SVG 手写）；
时序图留待 wavedrom（L4）。**原理图一律 schemdraw**：Python 代码即图，AI 可写、可迭代、可程序化验收。

## 环境（两机）

| 机 | venv | uv |
|---|---|---|
| mini | `~/code/exo-fsr/.venv`（已有 schemdraw 0.23 + matplotlib） | `/opt/homebrew/bin/uv` |
| MBP | `~/code/exo-fsr/.venv` | `~/.local/bin/uv` |

缺环境时：`cd ~/code/exo-fsr && <uv> venv --allow-existing && <uv> pip install schemdraw matplotlib`

参考脚本（都在 `~/code/exo-fsr/`，新图照抄其骨架）：
- `draw_v1_schematic.py` 原理图式（电源符号/接地符号/紧凑回路）
- `draw_v1_layout_style.py` 布局式（方框+双长轨，与手绘/实物同构）
- `draw_esp32_pinout.py` 引脚地图（elm.Ic 30 脚 + 图例页）

## 必须遵守的写法（每条都翻过车）

1. **中文字体**：`matplotlib.rcParams["font.family"]=["PingFang SC",...]` **且** `d.config(font="PingFang SC")`——后者会被前者遗漏，schemdraw 用自己的 font 设置，只设 rcParams 会缺字；
2. **2 端子元件跨指定两点用 `.endpoints(p1, p2)`**，不要 `.at(p1).toy(y)`——后者有渲染偏移 bug（内部端点记录正确、画出来错位 1 格，曾致 FSR 悬空，2026-09-16）；
3. **elm.Ic 的 L/R 侧引脚自底向上排布**——引脚列表要 `reversed(lst)` 才能与实物丝印同向（EN 在左上、USB 在左下）；
4. **标签防撞**：`elm.CurrentLabel` 会压元件名（改用线段 `.label("电流 →", loc="top")`）；Ic 的 label 会与 pin 名挤（把 pin 挪 `slot="3/3"`）；地轨标注放 Ground 符号 `loc="bottom"` 或独立段，别压电源圆圈；
5. **交叉语义不能省**：跨线弧（不连接的交叉）和节点圆点（连接）是唯一携带信息的细节——AI 读手绘图时先找弧再判拓扑（误判事故 2026-09-16，见 exoskeleton ch01 笔记勘误节）。

## 验收流程（顺序不可省）

1. 渲染到 `web/*.png`；
2. **程序化连通性验收**（缩略图目检不可靠——分辨率+确认偏误双重漏网）：
   把图中暗像素当导线，从 3.3V 轨出发 BFS 泛洪，能淹到 GND 轨才算过
   （实现见 2026-09-16 会话记录；约 20 行 PIL+deque）；
3. `read` PNG 自检：标签碰撞、方向与实物同向、图例完整；
4. 服务交付：`nohup .venv/bin/python -m http.server 8322 --directory web &`，
   给用户 URL（`http://<mini的ts-ip>:8322/<文件名>`）；用户放大复核是最后一道闸（T-030 三例）。

## 迭代纪律

一次只改一处坐标/布局 → 重渲染 → 重跑连通性检查。改轨位置时，**所有接到该轨的元件端点坐标同步改**（漏改一个就是悬空）。
