# 《端到端任务无关外骨骼控制》学习进度

> 最后更新：2026-09-19（**开科**：材料就位，未开课；开科缘起见「材料与缘起」）
> 分诊：概念型为主 + 操作型延伸（控制策略可上仿真验证，对接 exo-sim）
> 学习目标：吃透「task-specific → task-agnostic」控制范式转变的技术栈——生物关节力矩估计、训练数据与域迁移、安全机制三块，能对本项目 P1（单关节髋）的传感与控制选型给出有依据的判断

## 材料与缘起

- **缘起**（2026-09-19）：小红书帖评论区有读者提到「end-to-end 外骨骼控制」论文，用户令建档学习。同日检索后开两课（本课 + `learn/皮肤贴片传感/`），并产出两份调研报告（`reports/20260919.端到端任务无关外骨骼控制调研.md`、`reports/20260919.皮肤贴片传感调研.md`）。
- **核心材料**：Shepherd, Schonhaut, Scherpereel, Tourk & Young, "A roadmap for end-to-end task-agnostic exoskeleton control", *Nat Mach Intell* **8**, 1346–1357 (2026), DOI [10.1038/s42256-026-01297-7](https://doi.org/10.1038/s42256-026-01297-7)——正文付费墙内，**已存网页快照**（摘要 + 全部 112 条参考文献逐字清单）：`materials/shepherd2026_roadmap_web快照.txt`（+ .html）

## 全文获取状态（诚实账，2026-09-19）

| 论文 | 状态 | 文件 |
|---|---|---|
| Shepherd 2026 NMI roadmap | ❌ 正文付费墙（网页快照含摘要+全引文） | materials/shepherd2026_roadmap_web快照.txt |
| Zhang/Divekar/Krishnan/Gregg 2026（arXiv 2603.22580 v2，Versatile elderly hip） | ✅ 全文 PDF | materials/papers/zhang2026_versatile_elderly_hip_arxiv2603.22580.pdf |
| Ding 2016 JNER（髋助力时机） | ✅ 全文 PDF（OA） | materials/papers/ding2016_hip_timing_soft_exosuit_jner.pdf |
| Laschowski 2022 Front Neurorobot（环境分类） | ✅ 全文 PDF（OA） | materials/papers/leslie2021_env_classification_frontiers.pdf |
| Molinaro 2024 Nature（task-agnostic 开山） | ❌ 非 OA，仅登记 [DOI](https://doi.org/10.1038/s41586-024-08157-7) | — |
| Molinaro/Kang/Young 2024 Sci Robot（adi8852 视角文） | ❌ 非 OA，仅登记 [DOI](https://doi.org/10.1126/scirobotics.adi8852) | — |
| Scherpereel 2025 Sci Robot（域适应） | ❌ 非 OA，仅登记 DOI 10.1126/scirobotics.eads8652 | — |

> 获取方法沉淀：反爬站（MDPI/ScienceDirect）curl 会被 Akamai/Cloudflare 拦；OA 副本优先走 Unpaywall API + 出版社 CDN 直链（浏览器网络日志可挖出真实 PDF URL）；作者版常挂在实验室主页（如 MIT Media Lab）。NCBI PMC 需过 reCAPTCHA，EPMC 后端偶发故障。

## 概念账本（学习前全部 0，开课后逐项记）

### 一、范式与路线图（roadmap 精读）
| 概念 | 掌握度 | 笔记 |
|---|---|---|
| task-specific（离散任务分类+HIL）vs task-agnostic（连续估计）的边界与动机 | 0.0 | - |
| 「生物关节力矩估计」作为统一控制信号的论证链 | 0.0 | - |
| roadmap 三大未决挑战（优化/安全/数据负担） | 0.0 | - |

### 二、感知与状态估计
| 概念 | 掌握度 | 笔记 |
|---|---|---|
| IMU/鞋垫/EMG/超声 各传感模态的力矩估计能力账 | 0.0 | - |
| EMG 信息对深度学习估计是否必要（Schonhaut 2026） | 0.0 | - |
| 环境/地形分类（Laschowski 2022；Frontiers 17 页全文在手） | 0.0 | - |

### 三、控制策略与优化
| 概念 | 掌握度 | 笔记 |
|---|---|---|
| 能量整形控制（Gregg 组 Lin/Divekar 系列） | 0.0 | - |
| HIL 优化 vs 仿真 RL 训练（Song/Han/Park 2026） | 0.0 | - |
| 髋助力时机（Ding 2016 全文在手） | 0.0 | - |

### 四、数据与迁移
| 概念 | 掌握度 | 笔记 |
|---|---|---|
| 公开步态数据集地图（Camargo/Reznick/Scherpereel/AddBiomechanics） | 0.0 | - |
| 深度域适应砍训练数据（Scherpereel 2025） | 0.0 | - |

## 待深入 / 问题清单
- roadmap 摘要明说训练数据负担是核心瓶颈——对个人项目意味着什么（数据能多小？）
- 我们 P1 的 FSR+IMU+编码器组合，在「力矩估计」这条路线上缺什么？
- elderly 支线（arXiv 2603.22580 全文在手）与本项目受众（老年自主起居）直接对口——优先精读
