# actuator 位置伺服（position/kp）

## 概念定义
`<actuator>` 给模型加驱动，leg0 首例：

```xml
<actuator>
  <position name="ankle_servo" joint="ankle" kp="20"/>
</actuator>
```

- `<position>` = 位置伺服：内部对目标角与实际角之差乘 kp 输出力矩（τ = kp·(目标−实际)）
- `kp` = 位置增益/伺服刚度：大→硬、快、可能过冲震荡；小→软、慢
- viewer 中交互点是 **Control 面板**的 `ankle_servo` 滑块（拖 = 设目标角，弧度），Joint 面板可观察实际角逼近过程

## 学习过程
@2026-09-03
- **初始理解**：按 AI 给的方案录入 XML（首次独立改模型文件，内容正确）；对「拖滑块 = 下发目标、电机执行」的闭环有体感，但 kp 的作用尚未对比验证
- **误解与纠正**：预期 Joint 滑块会变可拖——实际可拖的在 Control 面板（讲解者有责任，已纠正）

## 关键洞察
（待独立重演后填写）

## 待深入
- kp=20 vs 100 vs 5 的响应对比（观察题已布置：ankle 读数逼近速度/稳定性）
- `<motor>` 力矩控制（直接给 τ，更贴近真实电机+力控）——下一概念
- ctrlrange 限幅、forcerange、真实执行器的带宽/减速器映射
