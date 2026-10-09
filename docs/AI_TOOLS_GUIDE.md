# Guia das Ferramentas para IA

Este documento e o ponto de entrada para qualquer IA que altere este repositorio.

## Gestor principal
MultiSuite e a porta de entrada do usuario e o orquestrador das ferramentas. Ele cria/abre o contexto global e chama as aplicacoes especializadas; nao absorve a logica delas.

## Regra principal
Antes de escrever codigo, identifique qual ferramenta e dona da responsabilidade. Nao duplique funcionalidades entre modulos.

| Ferramenta | Responsabilidade |
|---|---|
| MultiSuite | Gestor unificado, projetos e launcher das ferramentas |
| MultiCAD | CAD parametrico de pecas (fluxo SolidWorks 2014): sketch, operacoes, arvore; STL/DXF/.mcad. Em analise, ver `multicad/docs/TAREFA.md` |
| MultiPCB | Esquematico, PCB, netlist, roteamento e arquivos de fabricacao de placas |
| MakePCB | Placa do zero estilo PCB Wizard: esquema, componentes (furados e SMD), trilhas, autoroteamento, DRC, BOM, impressao 1:1 e Gerber + Excellon para o LaserPCB (pasta `makepcb/`) |
| RouterPCB | Fresagem de PCB na CNC Router: isolacao com fresa V, furacao por broca, recorte com pontes e nivelamento por sondagem, a partir do Gerber + Excellon (pasta `routerpcb/`, andamento em `routerpcb/docs/TAREFA.md`) |
| MakeRouter | (primeira versao 2,5D; V-Carve e relevo 3D pendentes) Projeto e usinagem de madeira na CNC Router: desenho, relevo, percursos, simulacao e G-code com zero virtual (pasta `makerouter/`, decisoes em `makerouter/docs/TAREFA.md`) |
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
MakeRouter (desenho + percursos) -> MultiCNC (CNC Router)
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
11. G-code de ferramentas de preparacao usa zero virtual e o cabecalho de `docs/CONTRATO_GCODE.md`; so o MultiCNC conhece a maquina.
12. A janela principal de cada aplicativo e criada com `Application.CreateForm` no `.lpr`. Com `TForm.Create(Application)` o LCL nao define `Application.MainForm`: fechar a janela so a esconde e o processo continua rodando em segundo plano (prende o `.exe`).

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
- makerouter/docs/AI_GUIDE.md (em analise)
- multiphysics/docs/AI_GUIDE.md
- src/core/AI_GUIDE.md
