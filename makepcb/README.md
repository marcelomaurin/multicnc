# MakePCB

Projeto de placas de circuito impresso **do zero**, no estilo do PCB Wizard,
gerando os arquivos que o **LaserPCB** consome (Gerber RS-274X/X2 + Excellon).

```
MakePCB  ──(Gerber + Excellon)──►  LaserPCB  ──(G-code)──►  MultiCNC
 desenho da placa                   isolacao a laser          execucao
```

## Etapas (barra lateral)

| Etapa | O que faz |
|---|---|
| 1 Placa | nome, tamanho, face simples/dupla, largura de trilha, folga, grade |
| 2 Componentes | galeria com miniaturas (resistores, capacitores, diodos/LEDs, transistores, CIs DIL, conectores, diversos, pads e vias), busca e propriedades do selecionado |
| 3 Ligacoes | ligacoes pad a pad (ratsnest), resumo de redes |
| 4 Trilhas | trilha manual (45 graus), area de cobre, texto, **roteamento automatico** e **DRC** |
| 5 Fabricar | lista de materiais (CSV), exportacao Gerber + Excellon, arte final PNG 600 dpi, abrir no LaserPCB |

## Vistas (como as abas do PCB Wizard)

- **Normal** – edicao: grade de pontos, Top em vermelho e Bottom em verde (mesmas cores do LaserPCB), contornos e ligacoes pendentes tracejadas.
- **Mundo real** – placa montada: FR4 com mascara, pads estanhados, serigrafia branca e corpo de cada componente.
- **Sem componentes** – a placa nua.
- **Arte final** – cobre preto em fundo branco para conferir/imprimir; opcao de espelhar.

## Atalhos

| Tecla | Acao |
|---|---|
| R | gira 90 graus (selecao ou componente a colocar) |
| Del | apaga a selecao |
| Esc | cancela / volta para Selecionar |
| Backspace | desfaz o ultimo ponto da trilha/area |
| Ctrl (segurado) | trilha livre, sem travar em 0/45/90 graus |
| Roda do mouse | zoom no cursor; botao do meio arrasta a vista |
| Ctrl+Z / Ctrl+Y | desfazer / refazer |
| Ctrl+N / Ctrl+O / Ctrl+S | novo / abrir / salvar |

## Arquivos

- Projeto: `.mpcb` (JSON; footprints referenciados pelo nome da biblioteca).
- Exportacao em `<pasta do projeto>/<nome>_gerber/`:

| Arquivo | Conteudo |
|---|---|
| `<nome>-B_Cu.gbl` | cobre inferior |
| `<nome>-F_Cu.gtl` | cobre superior (dupla face ou opcao marcada) |
| `<nome>-B_Mask.gbs` / `-F_Mask.gts` | mascara de solda |
| `<nome>-F_Silkscreen.gto` | serigrafia |
| `<nome>-Edge_Cuts.gm1` | contorno |
| `<nome>-PTH.drl` / `-NPTH.drl` | furos metalizados / de fixacao |

"Abrir no LaserPCB" chama `laserpcb --file <pasta>`; o LaserPCB importa a pasta
inteira e, em face simples, ja abre pelo lado Bottom.

## Compilar

```
lazbuild makepcb/src/app/makepcb.lpi
lazbuild makepcb/tests/test_makepcb.lpi    && makepcb/tests/test_makepcb
lazbuild makepcb/tests/test_makepcb_ui.lpi && makepcb/tests/test_makepcb_ui
```

Detalhes internos em [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
