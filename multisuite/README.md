# MultiSuite

Gestor unificado da suite MultiCNC.

## Missao
MultiSuite e a porta de entrada do ambiente. Ele nao substitui as ferramentas especializadas: organiza projetos e permite abrir MultiCAD, MultiPCB, MultiAssembly, MultiCAM, MultiSlicer, LaserPCB, LaserArt e MultiCNC.

## Ferramentas
- MultiCAD: CAD mecanico.
- MultiPCB: EDA/PCB.
- MultiAssembly: montagem eletromecanica.
- MultiCAM: CAM CNC Router e simulacao.
- MultiSlicer: impressao 3D.
- LaserPCB: PCB por laser.
- LaserArt: arte geral por laser.
- MultiCNC: controle da maquina fisica.

## Arquitetura
O registro central descreve ferramentas. O gerenciador representa o projeto global. O launcher inicia executaveis independentes e pode repassar o diretorio do projeto com --project.

## Regra
MultiSuite orquestra. A logica de CAD, EDA, CAM, slicing, laser, assembly e controle permanece em seus respectivos modulos.
