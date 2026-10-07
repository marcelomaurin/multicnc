# Furacao

A biblioteca `src/drill/laserpcb_drill.pas` transforma os furos e rasgos do Excellon em trabalho de maquina. Ela nao depende da interface nem da conexao.

## Fluxo

Excellon -> `TLPDrillFile` -> `TLaserPCBProject.BuildDrillPlan` -> `TLPDrillPlan` -> G-code de CNC Router ou trajetorias de laser.

- O projeto converte cada furo para a mesa com `WorldPoint`, o mesmo mapeamento das trajetorias do laser. Copias, rotacao, escala e espelhamento Bottom ficam iguais no laser e na broca.
- O plano agrupa por ferramenta: diametro + PTH/NPTH. Optimize ordena as brocas da menor para a maior. Em cada broca usa vizinho mais proximo e 2-opt.
- O filtro (`TLPDrillFilter`) vale para a broca e para a marcacao a laser. Ele aceita faixa de diametro e PTH/NPTH.

## CNC Router

`RouterGCode` gera GRBL simples: G0/G1, G4, M0, M3/M5 e M30. Nao usa ciclos fixos (G81/G83), porque o GRBL nao os implementa. As linhas ficam abaixo do limite do validador do MultiCNC. A primeira linha e `; LaserPCB -> MultiCNC (CNC Router)`, entao o MultiCNC abre o arquivo em CNC Router.

- **Furos:** mergulho direto ou bicadas (peck), com retirada ao Z de deslocamento.
- **Rasgos:** descem em passadas iguais a bicada e percorrem o rasgo indo e voltando.
- **Spindle:** M3 com rotacao, seguido de espera G4 para acelerar.
- **Troca de broca:** o padrao e um arquivo por broca (`furacao_T1_0.80mm.gcode`...). Entre os arquivos, troque a broca e zere o Z. O GRBL nao permite jog nem rezerar Z durante a pausa M0. O arquivo unico com M0 so serve quando o comprimento das brocas e igual (porta-pinca com batente).
- **Validacao:** Z seguro e de deslocamento positivos, profundidade negativa ate 20 mm, avancos positivos e espera de 0 a 60 s.

O zero X/Y e o mesmo do laser. O zero Z fica na superficie da placa. Use base de sacrificio.

## Marcacao a laser

O processo "Marcar furos (laser)" usa `LaserMarks` no fluxo normal de CAM, previa, validacao e G-code do laser:

| Tipo | Uso |
|---|---|
| Centro | Anel pequeno no centro; guia a broca na furacao manual |
| Contorno | Contorno do furo compensado pelo raio do feixe |
| Cortar o furo | Aneis concentricos com passo de 80% do feixe; abre o furo em material fino |

Rasgos usam contorno arredondado (`LPStadium`).

## Dupla face

Com "Furar pinos de registro", cada placa recebe dois pinos no eixo vertical central. Eles ficam abaixo e acima da placa, no afastamento configurado.

1. Fure a placa e os pinos na base de sacrificio.
2. Grave o Top.
3. Vire a placa no eixo vertical, encaixe nos pinos e grave o Bottom com espelhamento.

Os pinos exigem rotacao 0 ou 180 graus e precisam ficar dentro da mesa.

## Testes

- `tests/test_drill`: biblioteca (plano, filtro, ordem, G-code, marcas, registro).
- `tests/test_pipeline`: projeto (mapeamento por copia/Bottom, pinos, validacao e marcas pelo CAM).
- `tests/test_ui`: etapa Furar na interface.
