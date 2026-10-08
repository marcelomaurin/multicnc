# MakeRouter - Arquitetura (proposta para análise)

Estado: em análise. Nada aqui foi implementado. As decisões marcadas com **[D#]** estão em
`TAREFA.md` e esperam a escolha do Marcelo.

## 1. Sistema de coordenadas e zero virtual

- Unidades internas em **mm**, ângulos em graus. Na interface também em polegadas (fase posterior).
- **Espaço do projeto:** origem no canto inferior esquerdo do material, X para a direita, Y para
  cima e Z = 0 no **topo** do material. Os cortes ficam em Z negativo.
- **Espaço de saída (zero virtual):** o projeto é deslocado para o ponto de zero escolhido:

```text
Zero XY (9 pontos)          Zero Z
  TL ---- TC ---- TR          TOPO : Z0 = superficie do material (padrao)
  |                |          MESA : Z0 = mesa/base de sacrificio; topo = +Espessura
  ML      C       MR
  |                |
  BL ---- BC ---- BR        (BL = canto inferior esquerdo, padrao)
```

  `Saida = Projeto - Datum`, em que `Datum = (Xd, Yd, Zd)`. Para zero na mesa, `Zd = -Espessura`
  e todas as profundidades ganham `+Espessura`.
- O G-code **nunca** contém posição de máquina (nem `G53`, nem `G28` com coordenadas, nem
  `G54`..`G59` fixos). Quem amarra o zero virtual à mesa é o MultiCNC: o operador leva a
  ferramenta ao ponto, clica em **Zero Workpiece** e confere com **Frame (Test)**.
- Cabeçalho legível por máquina conforme [../../docs/CONTRATO_GCODE.md](../../docs/CONTRATO_GCODE.md).
  O MultiCNC lê o ponto de zero, o material e a caixa do trabalho para orientar o operador e
  conferir o curso da máquina antes de iniciar.

## 2. Modelo de dados (`.mrouter`, JSON)

```text
TMRProject
  Material: Width, Height, Thickness, DatumXY (9), DatumZ (Top|Table), SafeZ, HomeZ,
            Spoilboard (bool), VisualMaterial
  Layers[]: Name, Color, Visible, Locked
  Vectors[]: TMRVector (Id, Layer, Closed, Segments: line/arc/bezier, Transform)
             Text: Font, Size, Align -> convertido em contorno ao gerar
  Relief: TMRRelief (grade de alturas, resolucao, componentes)
     Components[]: Kind (Dome, Angle, Extrude, Revolve, Image, STL), VectorRefs,
                   Params, Mode (Add, Subtract, Max, Min), Offset Z, Escala Z
  Tools: referencia a biblioteca (id + copia dos parametros usados)
  Toolpaths[]: TMRToolpath (Kind, Name, Enabled, ToolId, VectorRefs, Params,
               Calculated: TMRMoves3D, Stats: comprimento, tempo, profundidade max)
```

- Os vetores são a **fonte da verdade**. Cada percurso guarda os Ids dos vetores e se marca
  como "desatualizado" quando um deles muda, como na lista do Aspire.
- O arquivo é JSON versionado (`"format": "makerouter", "version": 1`), igual ao `.mpcb`.

## 3. Unidades previstas

| Pasta | Unidades |
|---|---|
| `src/core` | `makerouter_types` (registros, padrões, validação), `makerouter_project` (projeto, camadas, JSON), `makerouter_datum` (zero virtual e conversão projeto -> saída), `makerouter_tools` (biblioteca de ferramentas e cortes por material) |
| `src/geom` | `makerouter_vectors` (segmentos, arcos e Bezier achatados com tolerância), `makerouter_shapes` (primitivas), `makerouter_text` (fonte -> contorno), `makerouter_boolean` (soldar/subtrair/interseção/offset, via biblioteca de polígonos **[D3]**), `makerouter_dxf` e o SVG reaproveitado do LaserArt |
| `src/relief` | `makerouter_relief` (grade de alturas, combinação), `makerouter_components` (domo, rampa, extrusão, revolução, imagem, STL) |
| `src/cam` | `makerouter_profile`, `makerouter_pocket`, `makerouter_drill`, `makerouter_vcarve`, `makerouter_3d` (desbaste em níveis Z e acabamento em raster com fresa esférica/reta), `makerouter_tabs`, `makerouter_leads` (rampa, hélice, entrada/saída) |
| `src/sim` | `makerouter_stock` (mapa de alturas do material, remoção por ferramenta com forma: reta, esférica, V), `makerouter_estimate` (tempo com aceleração simples) |
| `src/export` | `makerouter_gcode` (emissor GRBL; usa o emissor comum **[D4]**) |
| `src/ui` | `makerouter_view2d` (desenho com grade, réguas e *snap*), `makerouter_view3d` (relevo e simulação em OpenGL ou *software* **[D5]**), `makerouter_toolpathlist`, `makerouter_tooldb` (editor da biblioteca) |
| `src/app` | `makerouter_main` (6 etapas), `.lpi`, `.lpr`, `.ico`, `.manifest` |

## 4. Algoritmos

### 4.1 Offset e booleanas 2D
Peças de madeira chegam a 2750 × 1850 mm (chapa inteira). Com raster de 0,05 mm seriam 2 bilhões
de pixels, então o **raster do LaserPCB não serve aqui**. Offset, bolsão e booleanas precisam de
geometria vetorial: biblioteca de recorte de polígonos com *offset* e arredondamento de cantos
**[D3]**. Arcos e Bezier são achatados com erro de corda configurável (padrão 0,01 mm). Ao
gerar o G-code, sequências de pontos sobre um mesmo círculo podem voltar a ser `G2`/`G3`
(fase posterior).

### 4.2 Perfil
Offset do vetor fechado de ±R (fora/dentro) ou nenhum (na linha). Há passadas de profundidade
(`StepDown`), passada final de acabamento opcional (sobremetal), sentido concordante ou
discordante e entrada em rampa (linear ao longo do caminho) ou em hélice. As **pontes** usam o
mesmo modelo do RouterPCB: altura de ponte nas passadas mais fundas, com posição automática ou
clicada.

### 4.3 Bolsão (pocket)
Área = vetores fechados com ilhas (regra par-ímpar). Limpeza por **offset** (anéis de dentro
para fora) ou **zigue-zague** em ângulo, com contorno final. O *stepover* vem em % do diâmetro.
Entrada em rampa ou hélice. Opcional: ferramenta maior para desbaste e menor só onde a maior
não alcança (*rest machining*, fase posterior).

### 4.4 Furação
Pontos (círculos pequenos ou marcadores) com bicadas. Furos maiores que a broca viram
hélice/bolsão circular. Reaproveita a ordenação de furos (`LPOrderHoles`, vizinho mais
próximo + 2-opt).

### 4.5 V-Carve
Para cada região fechada, a profundidade em um ponto é `d = r / tan(A/2)`, em que `r` é a
distância até a borda (eixo medial). Implementação proposta em duas etapas:
1. campo de distâncias **por região** em raster local (só a caixa do texto/letra, onde
   0,02 mm é viável), reaproveitando `TLPField` do LaserPCB;
2. percurso pelas curvas de nível do campo (`LPIsoContours`) com Z variável, mais
   profundidade máxima (topo plano) e limpeza do fundo com fresa reta quando ela for limitada.

### 4.6 Relevo e 3D
O modelo 3D é um **mapa de alturas** Z(x,y) com resolução proporcional ao tamanho (padrão
0,1 mm, limite de 16 M células como no LaserPCB). Não é um sólido B-rep: cobre bandejas,
placas, letreiros e entalhes, que são o uso típico da router de 3 eixos.
- **Desbaste 3D:** níveis Z de `StepDown`. Em cada nível, a área a remover é onde o modelo + sobremetal
  < Z, limpa como bolsão (4.3) com fresa reta.
- **Acabamento 3D:** raster em X, em Y ou em ambos. A altura da ferramenta em cada ponto é a
  "drop-cutter" sobre a grade (reta, esférica ou V), com *stepover* pela altura de crista
  desejada.
- Peças maiores que a espessura ou com dois lados ficam fora do escopo inicial.

### 4.7 Simulação
O material é uma grade de alturas. Cada movimento G1 remove uma "varredura" da forma da
ferramenta (reta, esférica, V), a mesma ideia do `TStockHeightMap` do MultiCAM, ampliada para
formas. Há alerta de G0 que atravessa material e de porta-ferramenta abaixo do topo. A vista 3D
é sombreada com textura de madeira escolhida em Material.

### 4.8 G-code
Usa o mesmo conjunto do RouterPCB, com o cabeçalho do contrato:
- comandos `G21 G90 G94`, `G0`, `G1`, `G2`/`G3` (opcional), `G4`, `M3`, `M5`, `M0` e `M2`;
- ponto decimal, linhas de no máximo 127 caracteres e nenhum ciclo fixo;
- conferência automática com `multicnc_safety` e `multicnc_gcode_analyzer`, como já é feito
  nos testes do RouterPCB.

## 5. Reaproveitamento

| De onde | O quê |
|---|---|
| `laserpcb/src/geom` | caminhos, matrizes, ordenação de caminhos |
| `laserpcb/src/cam/laserpcb_raster` | `TLPField`/`LPIsoContours` para o V-Carve (raster local) |
| `laserpcb/src/drill` | `LPOrderHoles` |
| `routerpcb/src/export` | emissor GRBL, verificação (`RPCheckGCode`) e estimativa de tempo, para virar o emissor comum **[D4]** |
| `routerpcb/src/cam/routerpcb_cutout` | pontes por altura |
| `laserart/src/core/laserart_svgimport` | importação SVG |
| `multicam/src/simulation/multicam_stock_heightmap` | base da simulação do material |
| `multisuite/src/core` | controles, ícones, registro, launcher, contexto |

## 6. Limite com o MultiCAM e o MultiCAD **[D1]**

Hoje o **MultiCAM** tem cerca de 940 linhas: tipos de job, operações retangulares de
demonstração, simulação da máquina (motores, eletrônica, colisão) e remoção por heightmap. Ele
não tem desenho, relevo nem V-Carve. O **MultiCAD** é o CAD paramétrico de peças mecânicas
(sketch, cotas, extrusão).

Proposta:
- **MakeRouter:** a aplicação do usuário para madeira, letreiros e móveis, com desenho e CAM
  no mesmo lugar.
- **MultiCAM:** passa a ser o simulador da máquina (cinemática, eletrônica, colisão) e o CAM
  de peças mecânicas vindas do MultiCAD. O que for útil vira biblioteca usada pelo MakeRouter
  (simulação de material), sem duplicar.
- **MultiCAD → MakeRouter:** importação de contornos (DXF) para quem modelar a peça no CAD.
