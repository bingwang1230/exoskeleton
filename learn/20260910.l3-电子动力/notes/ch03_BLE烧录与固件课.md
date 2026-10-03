# ch03 BLE 无线化：踩坑回顾 + 烧录实操 + 固件代码精讲

> 授课型（2026-10-03 备课）。素材全部来自 10-02~03 两天实录：预检踩坑（notes/2026601002_预检踩坑记录.md）、BLE 双坑（notes/ch03_BLE无线化双坑.md）、固件源码（exo-fsr main.py @116ec3f，共 ~60 行）。
> 性质：**操作型为主**——烧录要会独立做，固件要能逐段讲出「为什么这么写」。掌握判定走三段式。

---

## 0. 开场检索（合上笔记答）

1. 10-02 预检时串口全是乱码、换波特率也没用，最后根因在哪一层？——A 接线断路 B 波特率根本没设进去 C 固件 bug
2. 那次误诊链的教训，用一句话说是什么？

---

## 1. 烧录这块：mpremote 三招与一个暗坑

### 分层回顾（ch01 学过，0.3）

```
bootloader（出厂固化，不动）→ MicroPython 固件（.bin，esptool 刷，09-15 已刷）→ main.py（应用层，日常只动这层）
```

今天的 BLE 双模**只动第三层**——这就是分层的价值：蓝牙协议栈在第二层（NimBLE 已编进 MicroPython 固件里），`import bluetooth` 即用。

### mpremote 三招（今天实际用的）

| 命令 | 作用 | 今天的实测表现 |
|---|---|---|
| `mpremote cp main.py :main.py` | 把电脑上的 main.py 拷进板子文件系统 | ✅ 每次都成 |
| `mpremote reset` | 硬复位，板子重启自动跑 main.py | ✅ |
| `mpremote exec "…"` | 在板子上执行一段代码 | ⚠️ 有暗坑，见下 |

**暗坑：`exec` / REPL 附着会打断 main.py。** 原理：exec 要拿 REPL 解释器执行你的代码，而 REPL 正被 main.py 的死循环占着——mpremote 的做法是打断它。于是出现今天的现象：刷完用 exec 验证过 `ubluetooth ok`，之后裸串口读却是 **0 行**——不是固件死了，是 main.py 被 exec 打断停在 REPL 里，复位才恢复。
**验证纪律**：刷完固件别用 exec 验证，用**裸串口读**（pyserial 直接读 2 秒看有没有 `ms,raw` 行）——这是不干扰被测对象的观察。

**补充：RTS 脉冲复位（今天排障用的招）**。开发板上 EN(复位)脚经自动复位电路接到 CH340 的 RTS——pyserial 里 `rts=True` 0.1 秒再放掉，等效于按了一次复位键，不用伸手碰板子。今天就是用它抓到开机 NameError 的完整 traceback 的。

### 讨论题 A

刷完固件后，哪两种验证方式各有什么问题？——①`mpremote exec "print(main 在跑吗)"` ②肉眼盯 USB 串口输出。提示：一个改变被测对象，一个依赖人眼实时性。

---

## 2. 固件精讲：60 行代码的五段结构

```
① ADC 三行（老朋友） → ② BLE 初始化+服务注册 → ③ IRQ 回调 → ④ 广播 → ⑤ 主循环双发
```

### ① ADC 三行（ch01 已学，路过）

`Pin(34)` + `ATTN_11DB`（量程扩到 ~3.3V）+ `WIDTH_12BIT`（0-4095）。V2 反逻辑：FSR 受压阻值变小 → 分压点上移 → 读数**下掉**；空载 ≈4095。

### ② BLE 初始化 + GATT 服务注册

```python
_NUS = bluetooth.UUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")   # 服务 UUID
_TX  = bluetooth.UUID("6E400003-B5A3-F393-E0A9-E50E24DCCA9E")   # 特征 UUID
((tx_handle,),) = ble.gatts_register_services(
    ((_NUS, ((_TX, bluetooth.FLAG_READ | bluetooth.FLAG_NOTIFY),)),)
)
```

三个概念：
- **GATT 模型**：服务（Service）是抽屉，特征（Characteristic）是抽屉里的格子。我们只开一个格子：TX（设备→主机方向），两个权限——READ（可读当前值）+ NOTIFY（可主动推送）。
- **为什么用 Nordic UART Service（NUS）这串 UUID**：业界事实标准（AI 补充：Nordic 官方定义、所有 BLE 调试 App 如 nRF Connect 都认识它），好处是手机随手可连可调试，不用自造 UUID 再到处配置。类比：不是自己发明端口协议，而是用大家都认的「80 端口」。
- **返回值解包**：`((tx_handle,),) = ...`——注册后拿回特征的操作句柄，双层元组是 MicroPython 的固定形状（一个服务→一个元组里的各特征句柄）。

### ③ IRQ 回调（今天的两个坑全在这）

```python
conn = [-1]
def _irq(ev, data):
    if ev == _IRQ_CENTRAL_CONNECT:      # 事件1：有主机连上了
        conn[0] = data[0]               # data[0] = 连接句柄（之后 notify 要用它）
    elif ev == _IRQ_CENTRAL_DISCONNECT: # 事件2：断开了
        conn[0] = -1
        _advertise()                    # 重新广播，等下一个连接
ble.irq(_irq)   # ← 挂载。必须在 def 之后（坑二），且不能忘（坑一）
```

**为什么必须走回调**：连接句柄不是你问出来的，是蓝牙栈**事件推送**给你的。MicroPython BLE 是事件驱动模型——你不挂 `ble.irq(_irq)`，事件来了没人接，`conn[0]` 永远是初值 -1。这就是坑一：扫描✅连接✅订阅✅、数据 0 行——阀门在回调链上，链没挂。
**坑二**：`ble.irq(_irq)` 写在了 `def _irq` 之前——Python 自上而下执行，那一刻 `_irq` 还不存在 → NameError → **整个 main.py 启动失败**，串口打印和 BLE 一起死（广播消失是第一症状）。
**为什么 `conn` 是列表**：闭包里要改外层变量，MicroPython 没有 `nonlocal` 可用的场合，用可变容器绕（列表元素可改）。AI 补充，待确认你记得这个 Python 细节。

### ④ 广播：31 字节里塞「我叫什么」

```python
payload = bytes([0x02, 0x01, 0x06, len(NAME) + 1, 0x09]) + NAME
ble.gap_advertise(100_000, adv_data=payload)   # 100ms 间隔
```

广播包是**字节级手工拼装**的 AD Structure 序列：每段 = `[长度, 类型, 数据…]`。
- `02 01 06` = 长度2、类型01(FLAGS)、值06（可被发现+仅 BLE）
- `09 65 78 6f …` = 类型09(完整本地名) + "exo-fsr"
- 两段共 13 字节，上限 31（蓝牙规范，AI 补充标来源：Core Spec AD 长度）——所以广播里放名字、不放 128 位 UUID（18 字节放不下还能剩几个），主机按名字找我们就够了。
- 100_000 微秒 = 100ms 广播间隔（代码自设，省电与被发现速度的折中）。

### ⑤ 主循环双发（双模策略的核心）

```python
while True:
    line = f"{ms},{adc.read()}"
    print(line)                          # 有线：USB 串口（V1 兼容，一字不动）
    if conn[0] >= 0:
        try:
            ble.gatts_notify(conn[0], tx_handle, line.encode() + b"\n")
        except Exception:
            pass
    time.sleep_ms(10)
```

- **单行 ≈13 字节 < 20 字节**（默认 ATT MTU 23 - 3 头部，蓝牙规范值，AI 补充），一次 notify 装得下，无需分片。
- **实测代价**：空口 ~66-79Hz（设备端时间戳 13ms/行）——主循环被每行 notify 拖慢，**不是丢包**。判定依据：慢的是设备端发车节奏，不是主机收货节奏。想回 100Hz：一次 notify 批 2-3 行（待做，非必须——脚部动作几 Hz、上升沿几十 ms，79Hz 仍远够用，出处：报告 20260910 §9.1）。
- **断连恢复是双端的**：固件端 IRQ 里重新广播；主机端 fsr_live 5 秒断流看门狗 → 重扫重连（实测 2-3s 恢复）。`try/except pass`：断连瞬间 notify 会失败，交给 IRQ 收尾即可。

### 讨论题 B

1. 如果把 `ble.gatts_notify` 移到 IRQ 的 CONNECT 事件里发一次，能不能替代主循环里的做法？为什么？
2. 广播包里如果不放 FLAGS 段（只放名字），猜猜哪类设备扫不到我们？

---

## 3. 裸重演设定（操作型，掌握判定用）

1. **独立重刷**：不看笔记，从 `git pull` 到「裸串口读到 100Hz 行」独立走一遍（包括验证环节选裸读不选 exec）。
2. **口述双坑**：合上材料，向 AI 复述两个坑各自的「现象→机理→一句话教训」，AI 只判对错不提示。
3. **变式题**：想广播名改成 `exo-fsr-v3`，你会改固件哪几行？（考：NAME 常量与广播包的关系、改完要不要重刷、怎么验证改成功了。）

---

## 附：本次数字户口

| 数字 | 含义 | 出处 |
|---|---|---|
| 31B / MTU 23-3=20B | 广播包上限 / 单 notify 载荷上限 | 蓝牙核心规范（AI 补充，待确认） |
| 100_000µs=100ms | 广播间隔 | 代码自设（main.py） |
| ~13B/行、13ms/行、66-79Hz | 单行长度 / 实测发车间隔 / 空口数据率 | 10-03 实测（dbg + notify 采样） |
| 几 Hz、几十 ms | 脚部动作带宽/上升沿 | 报告 20260910 §9.1 |
| 2-3s | 主机断流重连耗时 | 10-03 实测（fsr_live.log） |
