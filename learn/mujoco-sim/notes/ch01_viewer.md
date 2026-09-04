# MuJoCo viewer 界面

## 概念定义
MuJoCo 自带的原生 GUI（C + OpenGL，随 mujoco Python 包分发，非 Python 写成，无中文菜单）。核心分区：
- **3D 视口**：主渲染区。左键旋转 / 滚轮缩放 / 右键平移；**Ctrl+左键拖拽 body = 施加外力扰动**（被动模型的「手掰关节」）
- **File**：Save xml/mjb、Print model/data（导出到终端）、Screenshot、Quit
- **Option**：界面外观（Font 缩放会显著影响面板布局）、Help（快捷键总表）、Profiler/Sensor 示波器
- **Simulation**：仿真控制核心——Pause/Run（空格）、Reset、**Reload**、Physics 参数实时可调
- **Joint**：各关节**实际角度读数**（灰=只读）；只有挂了位置/速度执行器的关节，对应伺服目标才能交互
- **Control**：执行器输入滑块（拖 = 给 ctrl 发指令），有 actuator 才出现
- 双击 `~/Applications/MuJoCoViewer.app` 启动（leg0 默认）；拖 .xml 进视口 = 热加载

## 学习过程
@2026-09-03
- **初始理解**：第一眼界面混乱（Font 150% 导致面板挤占视口）；以为是 Python 写的界面
- **误解与纠正**：①界面调优 = Font 回 100% + 拖分隔条/折叠面板；②界面是 C/OpenGL 原生 GUI；③Joint 滑块灰色拖不动——误以为是 bug，实为「滑块是伺服目标输入器，被动关节只读」；④加 actuator 后能拖的滑块在 Control 面板而非 Joint 面板（讲解者首次说错了位置，已纠正）
- **关键讨论**：模型加载进内存后不自动跟随文件变化 → 改 XML 后须 Reload / 拖文件进视口 / 重开

## 关键洞察
- Joint 面板 = 传感器视角（实际状态），Control 面板 = 控制器视角（下发指令）——这一对分栏正是「状态 vs 控制」的物理直觉

## 待深入
- 快捷键总表（Help）还没过一遍
- Profiler/Sensor 面板没用过
