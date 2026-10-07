# MakePCB – arquitetura

Unidades em `makepcb/src`, separadas para que o nucleo seja testavel sem
interface (o teste `test_makepcb` roda com `--ws=nogui`).

```
core/    makepcb_model     documento: placa, componentes, trilhas, areas, textos, ligacoes, redes, .mpcb
         makepcb_library   biblioteca de footprints (galeria) – origem no centro dos pads
         makepcb_font      fonte de tracos (texto no cobre e na serigrafia)
         makepcb_bom       lista de materiais + exemplo 555 astavel
export/  makepcb_gerber    Gerber RS-274X (X2) e Excellon com nomes no padrao KiCad
route/   makepcb_route     ligacoes pendentes (arvore minima por rede), roteador A* em grade
         makepcb_drc       verificacao de folga, curto, largura, placa e ligacoes sem trilha
ui/      makepcb_render    desenho da placa nas 4 vistas (TCanvas) – editor, galeria e PNG
         makepcb_editor    controle de edicao: ferramentas, zoom/pan, reguas, desfazer
         makepcb_gallery   galeria com miniaturas em cache
app/     makepcb_main      tela no padrao da suite (TSuiteHeader, etapas, painel, rodape)
```

## Convencoes

- Milimetros, Y para cima, origem no canto inferior esquerdo da placa (igual ao LaserPCB).
- Rotacao de componentes em passos de 90 graus (`TMPComponent.LocalToWorld`).
- Todos os pads sao passantes; `Plated = False` marca furos de fixacao (NPTH).
- Redes = ligacoes + trilhas que tocam pads/trilhas + areas de cobre da rede (`ComputeNets`).
- Desfazer/refazer guardam o documento inteiro em JSON (ate 60 passos).

## Roteador

Grade de `Grid/2`. Obstaculos inflados por meia largura + folga; A* em 8
direcoes com custo de curva; em dupla face troca de face com via. As
ligacoes sao roteadas da mais curta para a mais longa, com rip-up das que
bloqueiam. Trilhas existentes sao mantidas.

## Integracao com a suite

- `stiMakePCB` (no fim de `TSuiteToolID` para nao mudar os ordinais gravados
  nos workspaces), registrado em `multisuite_registry` e no grupo PROJETAR da
  bandeja e do MultiSuite.
- Saida consumida por `TLaserPCBProject.ImportFolder` (LaserPCB).

## Testes

- `tests/test_makepcb` – biblioteca, modelo, redes, arquivo, fonte, exportacao
  lida de volta pelos leitores do LaserPCB, roteamento, DRC, BOM e pasta
  importada no LaserPCB (1008 verificacoes).
- `tests/test_makepcb_ui` – monta o exemplo, roteia, DRC, todas as etapas e
  vistas e exporta; `--shots <pasta>` salva capturas (Linux/X11).

## Proximos passos

- Esquematico (simbolos) gerando as ligacoes, como no PCB Wizard 3.
- Copiar/colar e selecao multipla; mover arrastando vertices de trilha.
- Footprints SMD e editor de footprint; importar biblioteca do MultiPCB.
- Impressao direta (hoje: PNG 600 dpi em escala 1:1).
