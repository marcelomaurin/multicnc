# Exercícios do LaserArt

Arquivos gerados por `tools/exercises/make_exercises` (licença CC0-1.0). Abra cada um em
**Abrir** no LaserArt, ou pela Central da suíte (o arquivo vai como `--file`).

| Arquivo | O que tem | Resultado de referência |
|---|---|---|
| `caixa_encaixes_80x60x40.lart` | Caixa com encaixes 80 × 60 × 40 mm, MDF 3 mm, kerf 0,15 mm, com tampa: 6 faces na camada 0 (Linha) | 6 peças lado a lado; G-code com ≈ 650 linhas |
| `placa_identificacao.lart` | Placa 100 × 40 mm com cantos de 5 mm e 2 furos (camada 0, corte) e o texto "MULTISUITE" em negrito (camada 1, preenchimento) | gravação primeiro, corte por último |
| `engrenagem_estrela.lart` | Engrenagem módulo 2 com furo de 8 mm e uma estrela de 5 pontas | contornos fechados, prontos para corte |

## E1 — Caixa com encaixes

1. Abra `caixa_encaixes_80x60x40.lart`. As 6 faces aparecem na mesa.
2. Clique em **Caixa com encaixes...** na barra e confira os parâmetros: 80 × 60 × 40 mm,
   espessura 3 mm, kerf 0,15 mm, com tampa. Mude a altura para 50 mm e confirme: as faces são
   refeitas com a nova medida.
3. No painel da direita, clique em **Prévia** para ver a ordem de corte.
4. **Salvar G-code** gera o programa; **Enviar ao MultiCNC** abre o MultiCNC com ele.

Esperado: os dentes de uma face casam com os vãos da face vizinha. O kerf aumenta os dentes
para compensar a largura do feixe; use **Teste de material** para medir o kerf real do seu laser.

## E2 — Placa de identificação (gravar + cortar)

1. Abra `placa_identificacao.lart`.
2. Selecione a camada 1 (texto): modo preenchimento, potência menor. A camada 0 é o corte.
3. **Prévia**: a gravação do texto vem antes do corte do contorno, para a peça não se soltar
   antes de terminar.
4. Troque o texto (duplo clique) por seu nome e salve o G-code.

## E3 — Engrenagem e estrela

1. Abra `engrenagem_estrela.lart`.
2. Selecione a engrenagem e mude o número de dentes no painel de propriedades.
3. Use **Estimar potência pelo laser...** para obter potência e velocidade sugeridas para o
   material e a espessura.
4. Gere o G-code e confira no MultiCNC (Simular) se os contornos fecham.

Arquivos de laser prontos em G-code ficam em [`../cnc_laser`](../cnc_laser/README.md).
