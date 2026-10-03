# ch03 BLE 无线化：从「连接成功却零数据」到充电宝供电跑波形（2026-10-03）

> 实录课：V2 链路当天从 USB 有线升到 BLE 无线。两个坑都是「代码看起来对、现象却不符直觉」的典型，值得单独一课。

## 背景

- 有线链路（CH340 USB 串口）10-03 上午刚全通，但鞋内实测拖着根线，走向「真·穿戴」必须剪掉它。
- 方案：ESP32 MicroPython `ubluetooth`（NimBLE）当 GATT server，服务选 **Nordic UART Service（NUS）**——业界事实标准 UUID，手机 nRF Connect / 主机 bleak 都能直连，不用自造 UUID。
- 固件双模：USB `print` 一字不动 + 连接态 `gatts_notify` 同格式行 `ms,raw`——刷一次固件，有线/无线两用。

## 坑一：ble.irq 漏挂——连接成功、notify 零发送

现象：bleak 扫描✅ 命中广播名 → 连接✅ → `start_notify`✅ → **3 秒 0 行**。

机理：MicroPython BLE 是事件驱动的——**连接句柄要靠 `_IRQ_CENTRAL_CONNECT` 事件回调送进来**。我的主循环写的是 `if conn[0] >= 0: gatts_notify(...)`，而 `conn[0]` 初值 -1 永远没变，因为我定义了 `_irq` 却**忘了 `ble.irq(_irq)` 挂上**。GATT 服务注册/广播/连接都不经过这个回调，所以前半程全对、偏偏数据阀门没开。

教训：**MicroPython 回调模式的通病——「定义了」≠「挂上了」**。排障时先问：这个回调被注册了吗？现象「服务都在、连接能建、就差数据」≈ 回调链断了。

## 坑二：ble.irq 挂在 _irq 定义之前——开机 NameError、广播整个消失

现象：补上 `ble.irq(_irq)` 后重刷，扫描里 **exo-fsr 消失**，USB 串口也 0 输出。

机理：我把挂载语句插在了 `conn = [-1]` 后面，而 `def _irq` 在更下面——Python 从上往下执行，`ble.irq(_irq)` 时 `_irq` 还不存在 → `NameError` → **main.py 整体启动失败**，串口打印和 BLE 一起死。

教训：两连坑说明我在「事件驱动 + 顺序执行」的混合范式里改代码时没有跑一遍脑内执行序。修完第一坑本该 diff 全文件确认语句顺序，而不是只看补的那一行。

## 验收口径（诚实数）

- 充电宝供电 + BLE 空口：**~66-79Hz**（设备端时间戳间隔 13ms，判定为主循环被每行 notify 拖慢，**非丢包**）。
- 对照需求（报告 20260910 §9.1：脚部动作几 Hz、上升沿几十 ms，100Hz 足够）：79Hz 仍远够用；想回满 100Hz → 一次 notify 批 2-3 行（待做，非必须）。
- 断连恢复：主机侧 5s 断流看门狗 → 重扫 → 实测 2-3s 重连；固件侧 `_IRQ_CENTRAL_DISCONNECT` 里重新 `gap_advertise`。

## 工程小账

| 项 | 值 |
|---|---|
| 广播包 | FLAGS(0x06) + 完整名 exo-fsr，13B < 31B 上限，间隔 100ms |
| 服务 | NUS `6E400001-…`，TX 特征 `6E400003-…`（READ+NOTIFY） |
| 单 notify 载荷 | `ms,raw\n` ≈ 13B < 默认 MTU 23 的 20B 上限，无需分片 |
| 主机 | bleak 3.0.2（`find_device_by_name`/`BleakClient`/`start_notify` API 与 2.x 兼容） |
| macOS 权限 | **SSH 进程拿不到蓝牙授权**（TCC 弹窗无处显示）；在用户终端/GUI 会话内跑即正常 |

## 一句话带走

BLE 三个「看起来连上了」≠「数据会来」的检查点：**回调挂了吗（irq）→ 挂对位置了吗（定义序）→ 主机能授权吗（TCC）**。
