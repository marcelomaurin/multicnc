# MultiCNC

**Languages:** [Português](README.md) · English · [Español](README_ES.md) · [Français](README_FR.md) · [Deutsch](README_DE.md) · [Русский](README_RU.md) · [中文](README_ZH.md) · [العربية](README_AR.md) · [हिन्दी](README_HI.md)

## An integrated platform to design, simulate and manufacture

**MultiCNC** is an open digital-manufacturing suite that brings **design, preparation, simulation and machine operation** into one ecosystem.

It is more than a G-code sender. The project aims to provide an integrated workflow for **CNC routers, CNC lasers, 3D printing, electronics, PCB design, electromechanical assemblies and physical simulation**.

> **One idea, many processes, one environment.**

### Project vision

MultiCNC seeks to reduce the fragmentation of digital manufacturing. Specialized applications work together from project creation and preparation to validation and real machine operation.

```text
IDEA → DESIGN → SIMULATION → PREPARATION → VALIDATION → MANUFACTURING
```

### Main applications

- **MultiCNC:** machine operation and control
- **MultiSuite:** central entry point for the suite
- **MultiCAD:** geometric design and preparation
- **MultiCAM:** toolpath and manufacturing preparation
- **MultiSlicer:** 3D-print preparation
- **MultiPCB / MakePCB / LaserPCB:** PCB design and fabrication (MakePCB: board from scratch, PCB Wizard style, Gerber + Excellon for LaserPCB)
- **RouterPCB** *(planned)*: PCB milling on the CNC Router (V-bit isolation, drilling, board cutout with tabs, probing/autolevel) from the MakePCB Gerber + Excellon folder. See [routerpcb/README.md](routerpcb/README.md)
- **MultiAssembly:** mechanical and electronic assembly integration
- **MultiPhysics:** multidomain physical simulation

### Router, Laser and 3D printing

The suite is designed for different manufacturing processes. CNC Router focuses on machining; CNC Laser includes engraving, cutting, perforation-style jobs and work-area framing before execution; 3D printing is integrated into the same overall workflow.

For Laser jobs, the framing function lets the operator check where the design will be executed before starting. Laser-specific settings include power, speed, passes, operation type and air assist.

### Simulation and AI assistance

**MultiPhysics** extends the suite by allowing projects to be studied before real manufacturing. Artificial intelligence is being integrated as an assistance layer for project analysis, preparation, diagnostics and guidance, while the operator remains in control of machine operation.

### Who is it for?

MultiCNC is intended for **makers, students, teachers, technical schools, universities, FabLabs, laboratories, researchers, developers, automation professionals and small workshops**.

The project is **open source and under continuous development**. Modules may have different maturity levels.

For detailed technical documentation, see the [main README in Portuguese](README.md).
