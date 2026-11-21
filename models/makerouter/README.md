# Exercícios do MakeRouter

Arquivos gerados por `tools/exercises/make_exercises` (licença CC0-1.0).

| Arquivo | O que tem | Resultado de referência |
|---|---|---|
| `placa_exemplo.mrouter` | O projeto do botão **Demo** | 7 desenhos, 4 percursos |
| `porta_copos.mrouter` | Porta-copos de 95 mm em material de 120 × 120 × 12 mm: rebaixo de 80 mm, texto "CAFE" e recorte | 3 percursos: bolsão (fresa 3 mm), gravação (1 mm), contorno externo 12,5 mm com 3 pontes |

## E1 — Porta-copos

1. No MakeRouter, **Abrir** → `porta_copos.mrouter`.
2. **1 Material:** 120 × 120 × 12 mm, zero no canto inferior esquerdo, topo do material.
3. **2 Desenho:** o disco de 95 mm, o círculo de 80 mm do rebaixo e o texto.
4. **4 Percursos:** confira a ordem: bolsão do rebaixo → gravação do texto → contorno por fora
   com profundidade de 12,5 mm (passa 0,5 mm do material) e 3 pontes para a peça não soltar.
5. **5 Simular:** **Simular todos** e confira o resultado em 3D.
6. **6 Saída:** **Validar**, **Gerar G-code** e **Abrir no MultiCNC**.

Experimente: mude o diâmetro do rebaixo para 70 mm em **2 Desenho** e gere de novo.

## E2 — Projeto de demonstração

1. **Abrir** → `placa_exemplo.mrouter` (ou o botão **Demo**).
2. Percorra as etapas 1 a 6; em **3 Relevo** veja como uma imagem vira superfície 3D.

Programas de router prontos em G-code ficam em [`../cnc_router`](../cnc_router/README.md).
