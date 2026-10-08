# Guia das Ferramentas para IA

Este documento e o ponto de entrada para qualquer IA que altere este repositorio.

## Gestor principal
MultiSuite e a porta de entrada do usuario e o orquestrador das ferramentas. Ele cria/abre o contexto global e chama as aplicacoes especializadas; nao absorve a logica delas.

## Regra principal
Antes de escrever codigo, identifique qual ferramenta e dona da responsabilidade. Nao duplique funcionalidades entre modulos.

| Ferramenta | Responsabilidade |
|---|---|
| MultiSuite | Gestor unificado, projetos e launcher das ferramentas |
| MultiCAD | Criacao e edicao de geometria/pecas CAD |
| MultiPCB | Esquematico, PCB, netlist, roteamento e arquivos de fabricacao de placas |
| MakePCB | Placa do zero estilo PCB Wizard: esquema, componentes (furados e SMD), trilhas, autoroteamento, DRC, BOM, impressao 1:1 e Gerber + Excellon para o LaserPCB (pasta `makepcb/`) |
| RouterPCB | Fresagem de PCB na CNC Router: isolacao com fresa V, furacao por broca, recorte com pontes e nivelamento por sondagem, a partir do Gerber + Excellon (pasta `routerpcb/`, andamento em `routerpcb/docs/TAREFA.md`) |
| MultiAssembly | Montagem eletromecanica: une pecas, motores, placas, drivers, fontes, sensores e conexoes |
| MultiCAM | Planejamento de usinagem CNC Router, toolpaths, simulacao de usinagem e G-code |
| MultiSlicer | Fatiamento e posicionamento para impressao 3D |
| MultiPhysics | Simulacao fisica multidominio da montagem (eletrica, mecanica, termica, falhas); nao executa hardware |
| LaserPCB | Preparacao/alinhamento de PCB para processo laser |
| LaserArt | Imagens, logos, textos, vetores e arte para laser (pasta `laserart/`) |
| MultiCNC | Conexao, seguranca, protocolo e execucao fisica da maquina |
| SimuCNC | Simulador de maquina (impressora, router, laser) com porta serial virtual/TCP (pasta `src/simucnc/`) |
| MultiSuite Bandeja | Atalho das ferramentas ao lado do relogio (pasta `multisuite/src/tray/`) |

## Fluxo conceitual
MultiCAD -> MultiAssembly -> MultiCAM -> MultiCNC
MultiPCB -> MultiAssembly e/ou LaserPCB/MultiCAM -> MultiCNC
MakePCB -> (pasta Gerber + Excellon) -> LaserPCB -> MultiCNC (CNC Laser)
MakePCB -> (pasta Gerber + Excellon) -> RouterPCB -> MultiCNC (CNC Router)
MultiAssembly -> MultiPhysics (simulacao)
MultiCAD/STL -> MultiSlicer -> MultiCNC
Imagem/Vetor -> LaserArt -> MultiCNC

## Regras para IA
1. Preserve modulos existentes.
2. Nao mova controle fisico para CAM/CAD/Slicer.
3. MultiCNC e o unico dono da execucao na maquina real.
4. MultiAssembly descreve a maquina/produto; nao executa hardware.
5. Validacoes de seguranca devem ser deterministicas. IA nunca deve ignorar E-Stop, limites ou validadores.
6. Parametros demonstrativos nao sao valores seguros para hardware real.
7. Reutilize os tipos e motores existentes antes de criar unidades equivalentes.
8. Toda nova funcionalidade deve ter teste quando houver logica testavel.
9. Nao declare build/teste como aprovado sem executar compilador/testes.
10. Consulte o AI_GUIDE.md da ferramenta antes de editar seus fontes.

## Documentacao por ferramenta
- multisuite/docs/AI_GUIDE.md
- multicad/docs/AI_GUIDE.md
- multipcb/docs/AI_GUIDE.md
- multiassembly/docs/AI_GUIDE.md
- multicam/docs/AI_GUIDE.md
- multislicer/docs/AI_GUIDE.md
- laserpcb/docs/AI_GUIDE.md
- laserart/docs/AI_GUIDE.md
- makepcb/docs/AI_GUIDE.md
- routerpcb/docs/AI_GUIDE.md
- multiphysics/docs/AI_GUIDE.md
- src/core/AI_GUIDE.md
