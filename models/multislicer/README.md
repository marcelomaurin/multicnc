# Exercícios do MultiSlicer

Usa as peças STL de [`../printer3d`](../printer3d/README.md) e a cantoneira do MultiCAD.

## E1 — Cubo de calibração

1. No MultiSlicer, **1 Impressora**: escolha o perfil da sua impressora (mesa, bico).
2. **2 Modelo** → **Abrir modelo...** → `models/printer3d/cubo_calibracao_20mm.stl`.
3. **3 Material:** PLA. **4 Qualidade:** camada 0,2 mm, 2 paredes, 15% de preenchimento.
4. **5 Suportes:** nenhum (o cubo não tem balanço).
5. **6 Prévia:** **Fatiar e visualizar** e percorra as camadas.
6. **7 Saída:** **Gerar G-code...**; **Abrir no MultiCNC** para enviar à impressora.
7. Imprima e meça: 20,0 × 20,0 × 20,0 mm. Diferenças indicam ajuste de passos/mm ou de fluxo.

## E2 — Anel e cantoneira

- `anel_diametros_20x12mm.stl`: confira os diâmetros 20 e 12 mm depois de impresso.
- `cantoneira_esquadro_30mm.stl` (ou o STL exportado de `../multicad/cantoneira_L.mcad`):
  imprima deitada; compare o G-code gerado com `cantoneira_30mm_marlin.gcode`.
