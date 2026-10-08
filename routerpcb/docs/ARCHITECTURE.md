# RouterPCB - Arquitetura

Estado: implementado (08/10/2026). Este documento registra as decisões técnicas seguidas no código.

## Fluxo de dados

```text
pasta <nome>_gerber
   |  laserpcb_gerber / laserpcb_excellon  (leitura, sem alteracao)
   v
TRouterPCBProject
   - camadas: cobre Top/Bottom, contorno, (mascara/serigrafia so para a previa)
   - furos: TLPDrillFile (PTH + NPTH)
   - lado: Top | Bottom ; matriz de saida M (espelho em X na caixa da placa + zero no canto)
   |
   +-- mascaras (TLPMask, resolucao padrao 0,02 mm): placa, cobre do lado
   |
   +-- Isolacao   -> TLPPaths (LPIsolation com largura efetiva da fresa)
   +-- Furacao    -> TLPDrillPlan (brocas ajustadas) + furos fresados (TLPPaths)
   +-- Recorte    -> TRPCutPaths (caminhos + intervalos de ponte)
   +-- Nivelamento-> TRPHeightMap (grade Z medida)
   |
   v
routerpcb_gcode (emissor GRBL unico)  ->  0_sondagem / 1_isolacao / 2_furos_Tn / 3_recorte
   |
   v
MultiCNC (--file, cabecalho "; RouterPCB -> MultiCNC (CNC Router)")
```

## Unidades previstas

| Unidade | Conteudo |
|---|---|
| `src/core/routerpcb_types.pas` | `TRPToolKind` (VBit, EndMill, Drill); `TRPTool` (nome, diametro, ponta, angulo, avanco, mergulho, RPM); `TRPIsolationOptions`, `TRPDrillOptions`, `TRPCutoutOptions`, `TRPLevelOptions`, `TRPMachineOptions` (SafeZ, TravelZ, espera do spindle, troca de ferramenta); padroes e validacao de cada registro. |
| `src/core/routerpcb_project.pas` | `TRouterPCBProject`: `ImportFolder`/`ImportFile`, `Side`, `OutputMatrix`, `RebuildMasks`, `GenerateIsolation`, `BuildDrillPlan`, `GenerateCutout`, `Validate(Errors, ForExport)`, `Programs` (lista nome -> TStringList). |
| `src/cam/routerpcb_isolation.pas` | largura efetiva da fresa V, verificacao de folga (cobres mais proximos que a largura), sentido de corte. |
| `src/cam/routerpcb_cutout.pas` | contorno externo deslocado R da fresa, recortes internos deslocados para dentro, pontes por altura. |
| `src/cam/routerpcb_drillmap.pas` | biblioteca de brocas, ajuste diametro -> broca, furos grandes -> trajetoria circular/helicoidal. |
| `src/level/routerpcb_heightmap.pas` | grade, programa de sondagem, leitura `[PRB:x,y,z:1]` e CSV, bilinear, subdivisao de segmentos, limite de correcao. |
| `src/export/routerpcb_gcode.pas` | emissor de programas, estimativa de tempo, nomes dos arquivos. |
| `src/ui/routerpcb_preview.pas` | canvas: placa, cobre, isolacao, furos (cor por broca), recorte com pontes, mapa de altura em cores, reguas em mm, zoom/pan. |
| `src/app/routerpcb_main.pas` | tela principal no padrao da suite (6 etapas). |

## Algoritmos

### Largura efetiva da fresa V
Para ponta `T` (mm), angulo `A` (graus) e profundidade `D` (mm, positiva):

```text
W = T + 2 * D * tan(A / 2)
```

Exemplo: fresa V 30 graus, ponta 0,1 mm, profundidade 0,08 mm -> W = 0,143 mm.
Fresa de topo: W = diametro. `W` vai para `LPIsolation(Cobre, Placa, W, Passadas,
Sobreposicao, Res/4)`. A passada k fica a W/2 + k*W*(1-sobreposicao) do cobre.

### Verificacao de folga
Campo de distancias do cobre (`TLPField`). Onde duas ilhas de cobre estao a menos de W,
o contorno W/2 se une: a isolacao nao separa os cobres. Detectar comparando o numero de
ilhas de cobre (componentes conexos da mascara) com o numero de ilhas da mascara dilatada
de W/2. Diferenca > 0 -> aviso "folga menor que a fresa" com a posicao aproximada.

### Sentido de corte
Spindle horario (M3). Ao contornar uma ilha de cobre por fora, sentido anti-horario =
concordante (climb). Os contornos de `LPIsoContours` saem com orientacao conhecida; o
emissor inverte (`LPReversed`) conforme a opcao e o sinal de `LPSignedArea`. No Bottom
espelhado o sentido inverte de novo: aplicar o espelho antes de decidir.

### Recorte com pontes em altura
1. Contorno externo: campo de distancias da mascara da placa pelo lado de fora, nivel R
   (raio da fresa). Recortes internos (furos de contorno / janelas): nivel R por dentro.
2. Profundidade total = espessura + 0,1 mm, em passos de `StepDown`.
3. Pontes: `N` intervalos ao longo do perimetro (evitar cantos), largura `TabW + 2R`.
   Nas passadas mais fundas que `-(espessura - TabH)`, o trecho da ponte sobe para
   `-(espessura - TabH)` (rampa curta) em vez de abrir lacuna. Assim a peca fica presa e o
   G-code continua um caminho continuo.

### Furacao
`TLPDrillPlan` agrupa por diametro/PTH. Antes de agrupar, cada diametro e trocado pela
broca da biblioteca mais proxima dentro da tolerancia (padrao +-0,1 mm; acima disso, aviso).
Furo maior que a maior broca + tolerancia: se houver fresa de topo menor, vira trajetoria
circular (raio = furo/2 - R) em passos de profundidade; senao erro de validacao.
Rasgos usam `LPStadium`. Ordem: menor broca primeiro, vizinho mais proximo + 2-opt
(`LPOrderHoles`).

### Nivelamento (heightmap)
- Grade `Cols x Rows` sobre a caixa da placa + margem; pontos em coordenadas de saida.
- Programa de sondagem: para cada ponto `G0 Z<TravelZ>`, `G0 X Y`, `G38.2 Z<ProbeDepth>
  F<ProbeFeed>`, `G0 Z<TravelZ>`. Primeiro ponto define a referencia (Z = 0 na
  superficie). O GRBL responde `[PRB:x,y,z:1]`; o usuario salva o log do MultiCNC
  ("Save Log...") e importa no RouterPCB. Tambem aceita CSV `X;Y;Z`.
- Interpolacao bilinear na celula; fora da grade -> erro (nao extrapola).
- Aplicacao: cada movimento G1 de corte e subdividido em trechos <= `MaxSegment`
  (padrao 1 mm) e recebe `Z + h(x,y) - h(ref)`. G0 e alturas de seguranca nao mudam.
  `|h - h(ref)| > MaxCorrection` (padrao 0,5 mm) -> erro de validacao.
- Aplica-se a isolacao (padrao ligado). Furacao e recorte: opcional (Z de inicio).

### Matriz de saida
`M = Translate(-MinX, -MinY)` para Top. Bottom: `M = Translate(-MinX,-MinY) *
Scale(-1, 1) * Translate(W, 0)` (espelho dentro da caixa, zero continua no canto inferior
esquerdo). A mesma `M` vale para isolacao, furos, recorte e grade de sondagem.

### Emissor G-code
```text
; RouterPCB -> MultiCNC (CNC Router)
; LaserPCB -> MultiCNC (CNC Router)   <- compatibilidade com o MultiCNC ja instalado
; <projeto> - <etapa> - <ferramenta>
; Zero: X/Y canto inferior esquerdo da placa, Z na superficie do cobre
G21
G90
G94
G0 Z<SafeZ>
M3 S<RPM>
G4 P<espera>
... trajetorias ...
G0 Z<SafeZ>
M5
G0 X0 Y0
M2
```
Sem `G81..G83`, sem `T`/`M6`. Troca de ferramenta com `M0` e mensagem `; Troque para ...`.
Numeros com `FormatFloat('0.###', InvFS)`. Cada linha <= 127 caracteres.

## Estado da implementacao

| Unidade | Estado |
|---|---|
| `laserpcb/src/import/laserpcb_roles.pas` | feito (funcao da camada, compartilhada) |
| `src/core/routerpcb_types.pas` | feito: opcoes, padroes, validacao, `RPVBitWidth`, `RPParseBits`, `TRPPath3` |
| `src/core/routerpcb_project.pas` | feito: importacao, lado/espelho, `OutputMatrix`, mascaras, `Generate`, `Validate` |
| `src/cam/routerpcb_isolation.pas` | feito: `RPIsolationPaths`, `RPOrientPaths`, `RPOrderPaths` (sem inverter), `RPClearanceIssues` |
| `src/cam/routerpcb_drillmap.pas` | feito: `RPChooseBit`, `RPBuildDrilling` (furos grandes -> `TRPMilledHole`) |
| `src/cam/routerpcb_cutout.pas` | feito: `RPCutoutContours`, `RPTabIntervals`, `RPDepthLevels`, `RPContourPasses`, `RPMilledHolePasses` |
| `src/level/routerpcb_heightmap.pas` | feito: grade em serpentina, `ProbeProgram` (G38.2 + `G10 L20 P0 Z0` no 1o ponto), `LoadProbeLog` (por ordem, confere deslocamentos), `LoadCSV`/`ToCSV`, `Height` bilinear, `Compensate` |
| `src/export/routerpcb_gcode.pas` | feito: `TRPWriter` (F modal, continuidade entre passadas, bicadas, rasgos), `RPBuildPrograms`, `RPSavePrograms`, `RPEstimate`, `RPCheckGCode` |
| `src/ui`, `src/app` | pendente (fase 3) |

Decisoes tomadas na implementacao:
- PTH e NPTH da mesma broca formam um so grupo (uma troca de broca).
- Furo entre duas brocas usa a broca maior seguinte (o terminal sempre entra), com aviso.
- Furos fresados vao para o programa de recorte (mesma fresa de topo).
- Resolucao automatica: 0,02 mm, aumentada so se a placa passar de ~10 milhoes de pixels.
- O log do MultiCNC traz as respostas do GRBL como `RX  [PRB:x,y,z:1]` (coordenadas de maquina):
  a leitura usa a ordem da serpentina e confere os deslocamentos X/Y relativos (o offset se cancela).
- Com nivelamento ligado e sem mapa medido, so o programa de sondagem e gerado (`NeedsProbe`).
- Os programas sao todos montados em memoria e conferidos (`RPCheckGCode`) antes de gravar qualquer arquivo.
- Verificacao de folga por expansao em largura a partir das ilhas de cobre (rotulos 8-vizinhos):
  devolve um ponto por par de ilhas em conflito.
