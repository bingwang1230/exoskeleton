# 《MuJoCo 仿真与建模》学习进度

> 最后更新：2026-09-04（第二章完成：motor 执行器+静力学对拍+角度单位坑）
> 材料载体：`~/code/exo-sim`（leg0.xml 起步）+ MuJoCo 官方文档；学科性质：**操作型**（建模/仿真，0.7+ 须走裸重演 + 代码/仿真验证三段式）
> 环境：MBP `~/code/exo-sim`（uv venv + MuJoCo 3.12.0），双击 `~/Applications/MuJoCoViewer.app` 启动

## 第一章：最小模型与 viewer（leg0.xml）

| 概念 | 掌握度 | 笔记文件 |
|------|--------|----------|
| MuJoCo viewer 界面（面板分工/导航/热加载工作流） | 0.1 | notes/ch01_viewer.md |
| 刚体树与坐标层级（worldbody/body 相对坐标） | 0.2 | notes/ch01_刚体树.md |
| joint = 自由度（hinge/axis/damping；无 joint 即焊死） | 0.2 | notes/ch01_joint.md |
| joint 弹簧（stiffness）与踝弹性助力的对应 | 0.3 | notes/ch01_joint.md |
| geom 与质量惯量（capsule/fromto/mass） | 0.1 | - |
| actuator 位置伺服（position/kp；Control 滑块交互） | 0.2 | notes/ch01_actuator.md |
| timestep 与仿真步进（2ms × N 步 = 物理时间） | 0.2 | - |

## 第二章：执行器与静力学（力矩控制）

| 概念 | 掌握度 | 笔记文件 |
|------|--------|----------|
| motor 执行器与 gear（ctrl 即力矩指令） | 0.6 | notes/ch02_执行器与静力学.md |
| 静力学平衡（θ=arccos(ctrl/m·g·x_com)；viewer 手感 0.63 vs 仿真 0.59 互证） | 0.7 | 同上 |
| MJCF 角度单位坑（默认度；compiler angle=radian） | 0.8（踩过并修复） | 同上 |
| 符号纪律（新模型先静力学符号检查） | 0.5 | 同上 |
| 调试工具箱（qfrc 四路分解/efc type-3 限位/mj_resetData） | 0.5 | 同上 |

## 待学（后续章节候选）

- 第二章：自建踝关节模型（按 OpenExo 参数，对接 P0 目标）：更多 joint 类型（slide/ball）、电机力矩控制（motor + ctrlrange）、传感器（jointpos/gyro）、接触与摩擦
- 第三章：从 XML 到控制循环（Python 侧 mj_step + 力控闭环，对接 L1 受力分析）
- 工具链：mjcf 模块化（include/defaults）、批量仿真、MJX/GPU（MBP 重负载场景）

- 第二章候选改「tendon/滑轮传动建模」

## 学习记录

- @2026-09-03 首次会话：环境跑通（viewer + 双击 App）；逐行讲解 leg0.xml（刚体树/joint=自由度/弹簧踝/geom 质量）；动手改模型加了 ankle 位置伺服（我出的改法，用户录入），在 viewer 里区分了 Joint（读数）vs Control（伺服目标）面板；掌握度全部初评（讨论为主，尚无独立产出证据，偏保守）
- @2026-09-04 第二课：position 换 motor 力矩执行器；viewer 手感估平衡 ctrl≈0.63 → 静力学对拍复现理论 0.59（θ=arccos 公式）；踩中 MJCF 角度默认度的坑（踝被限位焊死 ±0.7°），compiler angle=radian 修复。证据：exo-sim statics_test.py 对拍输出 + 亲手 viewer 实验（掌握度按有独立实验证据评）。
