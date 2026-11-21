# Exercícios do MultiCAD

Arquivos gerados por `tools/exercises/make_exercises` (licença CC0-1.0). Os dois reconstroem
sem erros.

| Arquivo | Árvore de operações | Peça |
|---|---|---|
| `placa_furos.mcad` | Esboço no plano Superior: retângulo 80 × 40 → Extrusão 8 mm → Esboço: 2 círculos Ø 6 em (12, 20) e (68, 20) → Corte passante | Placa 80 × 40 × 8 mm com 2 furos |
| `cantoneira_L.mcad` | Esboço no plano Frontal: perfil L 30 × 30 × 3 → Extrusão 40 mm | Cantoneira 30 × 30 × 3, 40 mm |

## E1 — Placa com furos

1. No MultiCAD, **Abrir...** → `placa_furos.mcad`.
2. Na árvore, dê duplo clique no segundo esboço e mude o diâmetro dos furos para 8 mm.
3. **Reconstruir** (Ctrl+B): os furos são refeitos.
4. Mude a extrusão para 10 mm e reconstrua.

## E2 — Cantoneira → impressão 3D

1. **Abrir...** → `cantoneira_L.mcad`.
2. **Exportar STL...** e depois **Abrir no MultiSlicer** (ou abra o STL no MultiSlicer).
3. No MultiSlicer, fatie com a face de 30 × 40 mm deitada na mesa.

Também dá para **Exportar STEP...** (para outro CAD) ou **Exportar DXF...** (perfil para o
LaserArt ou o MakeRouter).
