# MultiCNC

**语言：** [Português](README.md) · [English](README_EN.md) · [Español](README_ES.md) · [Français](README_FR.md) · [Deutsch](README_DE.md) · [Русский](README_RU.md) · 中文 · [العربية](README_AR.md) · [हिन्दी](README_HI.md)

## 面向设计、仿真与制造的一体化平台

**MultiCNC** 是一个开放的数字制造软件套件，目标是在同一生态中连接 **设计、准备、仿真和机器操作**。

它不仅仅是一个 G-code 发送器，还希望统一 **CNC 路由机、CNC 激光、3D 打印、电子设计、PCB、电机电气装配以及物理仿真** 的工作流程。

> **一个创意，多种工艺，一个环境。**

### 项目愿景

```text
创意 → 设计 → 仿真 → 准备 → 验证 → 制造
```

### 主要应用

- **MultiCNC：** 机器操作与控制
- **MultiSuite：** 套件统一入口
- **MultiCAD：** 几何设计与准备
- **MultiCAM：** 刀路与制造准备
- **MultiSlicer：** 3D 打印准备
- **MultiPCB / MakePCB / LaserPCB：** PCB 设计与制造（MakePCB：从零设计电路板，PCB Wizard 风格，为 LaserPCB 生成 Gerber + Excellon）
- **RouterPCB：**在 CNC 雕刻机上铣削 PCB（V 形刀隔离、钻孔、带连接桥的外形切割、探针自动调平），输入为 MakePCB 的 Gerber + Excellon 文件夹。参见 [routerpcb/README.md](routerpcb/README.md)
- **MakeRouter**（开发中）：在 CNC 雕刻机上设计并加工木制零件（绘图、浮雕、刀路、仿真），流程参考 Aspire；G 代码使用虚拟零点，由 MultiCNC 定位。参见 [makerouter/README.md](makerouter/README.md)
- **MultiAssembly：** 机械与电子装配集成
- **MultiPhysics：** 多领域物理仿真

在 CNC 激光流程中，项目包括在正式切割或雕刻前沿工作区域轮廓移动，用来确认材料位置与加工范围，并提供功率、速度、加工次数、操作类型和气辅等设置。

**MultiPhysics** 用于在真实制造前研究项目行为；人工智能则作为辅助层，支持项目分析、准备、诊断和操作指导。

MultiCNC 面向 **创客、学生、教师、职业学校、大学、FabLab、实验室、研究人员、开发者、自动化专业人员和小型工作室**。

项目为 **开源项目，并持续开发中**。

详细技术文档请参阅[葡萄牙语主 README](README.md)。
