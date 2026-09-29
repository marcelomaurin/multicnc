# Guia das Ferramentas para IA

Este documento e o ponto de entrada para qualquer IA que altere este repositorio.

## Regra principal
Antes de escrever codigo, identifique qual ferramenta e dona da responsabilidade. Nao duplique funcionalidades entre modulos.

| Ferramenta | Responsabilidade |
|---|---|
| MultiCAD | Criacao e edicao de geometria/pecas CAD |
| MultiPCB | Esquematico, PCB, netlist, roteamento e arquivos de fabricacao de placas |
| MultiAssembly | Montagem eletromecanica: une pecas, motores, placas, drivers, fontes, sensores e conexoes |
| MultiCAM | Planejamento de usinagem CNC Router, toolpaths, simulacao de usinagem e G-code |
| MultiSlicer | Fatiamento e posicionamento para impressao 3D |
| LaserPCB | Preparacao/alinhamento de PCB para processo laser |
| LaserArt | Imagens, logos, vetores e arte para laser; implementado dentro de laserpcb |
| MultiCNC | Conexao, seguranca, protocolo e execucao fisica da maquina |

## Fluxo conceitual
MultiCAD -> MultiAssembly -> MultiCAM -> MultiCNC
MultiPCB -> MultiAssembly e/ou LaserPCB/MultiCAM -> MultiCNC
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
- multicad/docs/AI_GUIDE.md
- multipcb/docs/AI_GUIDE.md
- multiassembly/docs/AI_GUIDE.md
- multicam/docs/AI_GUIDE.md
- multislicer/docs/AI_GUIDE.md
- laserpcb/docs/AI_GUIDE.md
- src/core/AI_GUIDE.md
