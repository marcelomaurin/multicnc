# MultiCNC

**Langues :** [Português](README.md) · [English](README_EN.md) · [Español](README_ES.md) · Français · [Deutsch](README_DE.md) · [Русский](README_RU.md) · [中文](README_ZH.md) · [العربية](README_AR.md) · [हिन्दी](README_HI.md)

## Une plateforme intégrée pour concevoir, simuler et fabriquer

**MultiCNC** est une suite ouverte de fabrication numérique qui réunit **conception, préparation, simulation et pilotage des machines** dans un même écosystème.

Le projet va au-delà d’un simple émetteur de G-code et vise à intégrer **routeur CNC, laser CNC, impression 3D, électronique, PCB, assemblage électromécanique et simulation physique**.

> **Une idée, plusieurs procédés, un seul environnement.**

### Vision

MultiCNC cherche à relier les différentes étapes de la fabrication numérique :

```text
IDÉE → CONCEPTION → SIMULATION → PRÉPARATION → VALIDATION → FABRICATION
```

### Applications principales

- **MultiCNC :** pilotage et contrôle des machines
- **MultiSuite :** point d’entrée de la suite
- **MultiCAD :** conception et géométrie
- **MultiCAM :** préparation des trajectoires
- **MultiSlicer :** préparation de l’impression 3D
- **MultiPCB / MakePCB / LaserPCB :** conception et fabrication de PCB (MakePCB : carte à partir de zéro, style PCB Wizard, Gerber + Excellon pour LaserPCB)
- **RouterPCB :** fraisage de PCB sur la CNC Router (isolation à la fraise en V, perçage, détourage avec ponts, nivellement par palpage) à partir du dossier Gerber + Excellon du MakePCB. Voir [routerpcb/README.md](routerpcb/README.md)
- **MakeRouter** *(en développement)* : conception et usinage de pièces en bois sur la CNC Router (dessin, relief, parcours, simulation), flux de type Aspire ; G-code avec zéro virtuel positionné par le MultiCNC. Voir [makerouter/README.md](makerouter/README.md)
- **MultiAssembly :** intégration mécanique et électronique
- **MultiPhysics :** simulation physique multidomaine

Pour le laser CNC, la suite prévoit la vérification de la zone de travail avant l’exécution grâce à une fonction de contournage, ainsi que des réglages de puissance, vitesse, passes, type d’opération et assistance d’air.

**MultiPhysics** permet d’étudier le projet avant la fabrication réelle. L’intelligence artificielle est intégrée comme couche d’assistance pour l’analyse, la préparation, le diagnostic et l’accompagnement de l’utilisateur.

MultiCNC s’adresse aux **makers, étudiants, enseignants, écoles techniques, universités, FabLabs, laboratoires, chercheurs, développeurs, professionnels de l’automatisation et petits ateliers**.

Le projet est **open source et en développement continu**.

Pour la documentation technique détaillée, consultez le [README principal en portugais](README.md).
