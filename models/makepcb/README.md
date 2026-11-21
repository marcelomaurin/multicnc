# Exercícios do MakePCB (e da cadeia RouterPCB / LaserPCB)

Arquivos gerados por `tools/exercises/make_exercises` (licença CC0-1.0): o pisca-pisca com
555 do capítulo 25 do manual do MakePCB.

| Arquivo | O que tem | Resultado de referência |
|---|---|---|
| `pisca_555_sem_trilhas.mpcb` | Placa, esquema e componentes do pisca 555, sem trilhas | 15 ligações por rotear |
| `pisca_555_roteado.mpcb` | O mesmo projeto depois de **Rotear automaticamente** | 13 trilhas, 0 vias, 0 falhas; DRC sem erros |
| `pisca_555_gerber/` | Fabricação do projeto roteado (Gerber + Excellon) | 6 arquivos; placa 50,8 × 38,1 mm |

## E1 — Do esquema à placa roteada

1. No MakePCB, **Abrir** → `pisca_555_sem_trilhas.mpcb`.
2. Etapa **2 Esquema**: confira o 555, os resistores, o capacitor e o LED. Clique em
   **Converter para a placa** se mudar algo no esquema.
3. Etapa **3 Componentes**: arraste os componentes se quiser outro arranjo.
4. Etapa **4 Trilhas**: **Rotear automaticamente**. Esperado: 15 ligações, todas roteadas.
5. **Verificar (DRC)**: nenhum erro de afastamento.
6. Compare com `pisca_555_roteado.mpcb`.

## E2 — Fabricar

1. Etapa **5 Fabricar**: **Exportar Gerber + Excellon** para uma pasta vazia.
2. Compare com `pisca_555_gerber/`: cobre (B_Cu), máscara (B_Mask), contorno (Edge_Cuts),
   serigrafia (F_Silkscreen), furos metalizados (PTH) e não metalizados (NPTH).
3. **Salvar lista (CSV)** gera a lista de materiais; **Imprimir arte final (1:1)...** imprime a
   arte para transferência térmica.

## E3 — Fresar (RouterPCB) ou gravar (LaserPCB)

- **RouterPCB:** **Abrir pasta...** → `pisca_555_gerber` (ou **Abrir no RouterPCB** no MakePCB).
  Siga as etapas 1 Importar → 2 Isolação → 3 Furação → 4 Recorte → 5 Nivelamento → 6 Saída e
  clique **Gerar G-code...**. Veja [`../routerpcb`](../routerpcb/README.md).
- **LaserPCB:** **Abrir arquivos...** → os Gerbers da mesma pasta (ou **Abrir no LaserPCB**).
  Veja [`../laserpcb`](../laserpcb/README.md).
