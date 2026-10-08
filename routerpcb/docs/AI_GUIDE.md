# RouterPCB - Guia para IA

## Finalidade
Fabricacao de PCB por fresagem mecanica na CNC Router: isolacao do cobre, furacao,
recorte do contorno e nivelamento da superficie (heightmap). Recebe a pasta Gerber +
Excellon do MakePCB (ou de outro EDA) e gera G-code para o MultiCNC em modo CNC Router.

Estado: planejado. Plano em `docs/TAREFA.md`.

## Estrutura prevista
- src/core/: `routerpcb_types` (ferramentas, parametros, padroes) e `routerpcb_project`
  (importacao, lado, espelho, mascaras, geracao das operacoes, validacao).
- src/cam/: `routerpcb_isolation`, `routerpcb_cutout` (recorte com pontes em altura) e
  `routerpcb_drillmap` (ajuste dos furos as brocas disponiveis e furos fresados).
- src/level/: `routerpcb_heightmap` (grade, programa de sondagem, leitura de PRB/CSV,
  interpolacao bilinear, subdivisao de segmentos).
- src/export/: `routerpcb_gcode` (emissor GRBL unico para todas as etapas).
- src/ui/: `routerpcb_preview` (placa, cobre, trajetorias, furos, pontes, mapa de altura).
- src/app/: `routerpcb.lpi/.lpr`, `routerpcb_main.pas`, icone, manifesto.
- tests/: `test_routerpcb.lpr` (logica) e `test_routerpcb_ui.lpr` (interface nativa).

## Reuso obrigatorio (nao duplicar)
- `laserpcb/src/geom/laserpcb_geom.pas`: pontos, caminhos, matrizes, ordenacao.
- `laserpcb/src/import/laserpcb_gerber.pas` e `laserpcb_excellon.pas`: leitura.
- `laserpcb/src/cam/laserpcb_raster.pas`: `TLPMask`, `TLPField`, `LPIsoContours`.
- `laserpcb/src/cam/laserpcb_cam.pas`: `LPIsolation`, `LPOffsetMask`,
  `LPClipPathsToMask`, `LPAddTabs`.
- `laserpcb/src/drill/laserpcb_drill.pas`: `TLPDrillPlan`, `LPOrderHoles`, `LPStadium`.
- `multisuite/src/core`: controles, icones, registro, launcher, contexto.
- Deteccao da funcao da camada: hoje `DetectLayerRole` esta em `laserpcb_project.pas`.
  Mover para uma unidade leve (`laserpcb/src/import/laserpcb_roles.pas`) e fazer o
  LaserPCB usa-la, em vez de copiar.

## Limites com outras ferramentas
- **LaserPCB**: PCB por laser. RouterPCB: PCB por fresa/broca. Mesma importacao, saidas diferentes.
- **MultiCAM**: usinagem mecanica geral (pecas, pocket, perfil, 3D). Nao colocar CAM de PCB
  no MultiCAM; nao colocar usinagem de pecas no RouterPCB.
- **MultiPCB**: tem um esboco de heightmap/compensacao em `multipcb/src/positioning`
  (IDW, poucas linhas). O RouterPCB implementa a versao completa (bilinear). Ao terminar,
  avaliar mover a versao boa para um lugar comum e o MultiPCB passar a usa-la.
- **MultiCNC**: unico dono da execucao, da sondagem fisica e da seguranca.

## Regras
1. Coordenadas em mm, Y para cima; zero X/Y no canto inferior esquerdo da placa ja
   espelhada; Z = 0 na superficie do cobre.
2. Bottom espelha em X dentro da caixa da placa: isolacao, furos e recorte usam a mesma
   matriz. Nunca altere a geometria importada; aplique a matriz na saida.
3. G-code so com G0/G1/G4/M0/M3/M5 (e G38.2 na sondagem); ponto decimal; linhas <= 127.
4. Primeira linha do programa: `; RouterPCB -> MultiCNC (CNC Router)`.
5. Validar antes de gravar; erro nunca cria ou sobrescreve arquivo.
6. A correcao de Z do heightmap tem limite (MaxCorrection) e rejeita pontos fora da grade.
7. Toda logica nova com teste em `tests/test_routerpcb.lpr`.
