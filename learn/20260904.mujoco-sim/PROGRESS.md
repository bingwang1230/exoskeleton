# 《MuJoCo 仿真与建模》学习进度

> 最后更新：2026-09-16（第三章 tendon 收官：回炉后独立产出达成；学习方式=审查者模式）
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

## 第三章：tendon 传动建模（进行中）

| 概念 | 掌握度 | 笔记文件 |
|------|--------|----------|
| fixed vs spatial tendon；绳长守恒 ≠ 张力恒定 | 0.5 | notes/ch03_tendon传动.md |
| coef 物理意义（=滑轮半径，用户自行推导） | 0.6 | 同上 |
| 执行器绑 tendon 后 ctrl 单位变张力（力矩=张力×半径） | 0.7（09-16 深夜升回：独立算 15×0.0585=−0.878 带符号+独立推 0.59/0.0585=10.1，对拍命中；半径来历 13×4.5 纠错一次） | 同上 |
| 关节限位=约束力（qfrc_constraint/efc 限位）：停转位置由 range 定、门框受压由张力定 | 0.7（09-16 深夜升回：独立建平账方程解出约束 0.281，对拍 0.282；追问带宽/方向/力臂三问显真理解） | 同上 |
| 审查者模式 6 条清单 | 0.3 | 同上 |

## 待学（后续章节候选）

- 第二章：自建踝关节模型（按 OpenExo 参数，对接 P0 目标）：更多 joint 类型（slide/ball）、电机力矩控制（motor + ctrlrange）、传感器（jointpos/gyro）、接触与摩擦
- 第三章：从 XML 到控制循环（Python 侧 mj_step + 力控闭环，对接 L1 受力分析）
- 工具链：mjcf 模块化（include/defaults）、批量仿真、MJX/GPU（MBP 重负载场景）

- 第二章候选改「tendon/滑轮传动建模」
- 第三章进行中：双向耦合（motor_side 虚拟关节）待上

## 学习记录

- @2026-09-03 首次会话：环境跑通（viewer + 双击 App）；逐行讲解 leg0.xml（刚体树/joint=自由度/弹簧踝/geom 质量）；动手改模型加了 ankle 位置伺服（我出的改法，用户录入），在 viewer 里区分了 Joint（读数）vs Control（伺服目标）面板；掌握度全部初评（讨论为主，尚无独立产出证据，偏保守）
- @2026-09-04 第二课：position 换 motor 力矩执行器；viewer 手感估平衡 ctrl≈0.63 → 静力学对拍复现理论 0.59（θ=arccos 公式）；踩中 MJCF 角度默认度的坑（踝被限位焊死 ±0.7°），compiler angle=radian 修复。证据：exo-sim statics_test.py 对拍输出 + 亲手 viewer 实验（掌握度按有独立实验证据评）。
- @2026-09-12 第三课（未完）：tendon 两类/coef 推导/张力换算静力学对拍（10.09 N 手算=仿真命中）；XML 基础大答疑（plane 半宽/rgba/capsule fromto 中轴线±半径/关节=约束无尺寸/four joint types/蓝图+接线板心智模型）。学习方式调整：不做默写改审查者模式（用户拍板）。流程 bug 教训入 learn.md 规则 8。停在审查题（限位停转），下次先答后推进。
- @2026-09-16 第四课（回炉）：审查题「12N 为何停在 -45.9°」——用户完成弧度对位（-45.9°=-0.8 rad 下限 / +34.4°=+0.6 rad 上限）并点名 radian 陷阱；两处纠错（tendon 张力双重记账、coef 误记为关节角度）。判卷曾定「通过」并记收官，**用户当场纠正「我明明还没懂」**：追问暴露账本层缺口（四档张力=脚本 ctrl 指令/平衡角=仿真停稳后的踝角/平账=静止时踝上力矩代数和=0）——判卷过急系 learn.md 规则 8 二犯，掌握度降档（ctrl 单位 0.6→0.4、限位概念 0.6→0.3）、第三章撤收官。实证脚本 tendon_qfrc_check.py 保留（四路平账：10.1N constraint=0.000 / 12N +0.106 / 15N 同角度 +0.282）。另：10.09N「手算」归属存疑更正（用户无印象，疑 AI 代算录入，待用户重算过户）。出口判据：用户独立填出 15N 行三格。顺带纠正心智模型：tendon/actuator 是顶层接线板（与 worldbody 平行），joint 长在身体里。
- @2026-09-16 第四课补（回炉出口达成，第三章真收官）：15N 行三格独立全对（执行 −0.878/约束 +0.281 对拍 +0.282/平衡角下限+理由）；0.59 与 10.1 两数当堂重算过户；半径来历纠错（×4.5 非 ÷）。三个新追问当堂答并沉淀入笔记：①内部平衡判据=F×R 落在重力矩可达带（本模型 ≈[0.34,0.60]，表里重力列各行不同即证据）②+θ=跖屈/耷拉、−θ=背伸/勾脚背（+y 轴右手法则）③抽象限位无力臂，qfrc_constraint 即关节坐标力矩，换力需几何化挡块 F=τ/r_stop。掌握度：ctrl 单位与限位约束两概念 0.7。下一课候选不变：双向耦合 motor_side/spatial 滑轮。
