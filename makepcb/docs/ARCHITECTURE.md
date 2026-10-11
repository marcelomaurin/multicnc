# MakePCB – arquitetura

Unidades em `makepcb/src`, separadas para que o nucleo seja testavel sem
interface (o teste `test_makepcb` roda com `--ws=nogui`).

```
core/    makepcb_model     documento: placa, componentes, trilhas, areas, textos, ligacoes, redes, .mpcb
         makepcb_library   biblioteca de footprints (galeria) – origem no centro dos pads
         makepcb_font      fonte de tracos (texto no cobre e na serigrafia)
         makepcb_bom       lista de materiais + exemplo 555 astavel
         makepcb_select    selecao multipla, mover/girar/apagar, copiar/colar (JSON)
         makepcb_schematic simbolos, esquema, redes, conversao para a placa, exemplo 555
         makepcb_printlayout copias da arte final na folha
export/  makepcb_gerber    Gerber RS-274X (X2) e Excellon com nomes no padrao KiCad
route/   makepcb_route     ligacoes pendentes (arvore minima por rede), roteador A* em grade
         makepcb_drc       verificacao de folga, curto, largura, placa e ligacoes sem trilha
ui/      makepcb_render    desenho da placa nas 4 vistas (TCanvas) – editor, galeria e PNG
         makepcb_editor    controle de edicao: ferramentas, zoom/pan, reguas, desfazer
         makepcb_gallery   galeria com miniaturas em cache
         makepcb_fpeditor  editor de componentes (biblioteca do usuario)
         makepcb_schedit   editor do esquema e galeria de simbolos
         makepcb_print     impressao 1:1 da arte final (Printer4Lazarus)
app/     makepcb_main      tela no padrao da suite (TSuiteHeader, etapas, painel, rodape)
```

## Convencoes

- Milimetros, Y para cima, origem no canto inferior esquerdo da placa (igual ao LaserPCB).
- Rotacao de componentes em passos de 90 graus (`TMPComponent.LocalToWorld`).
- Pad com furo e passante; `Plated = False` marca furos de fixacao (NPTH). Pad sem furo e SMD e
  existe so em `TMPComponent.SMDLayer` (Top, ou Bottom com `Flipped`). Redes, roteador, DRC, Gerber
  e mascara usam `PadOnLayer`.
- Componente virado (`Flipped`) espelha X antes de girar; nao vai para a serigrafia de cima.
- Footprints do usuario (`UserDefined`) sao gravados no `.mpcb` (`footprints`) e usados se a
  biblioteca local nao tiver o nome (`TMPDocument.OwnFootprint`).
- O esquema e guardado como JSON em `TMPDocument.SchematicJSON` (chave `schematic`); o modelo da
  placa nao depende da unit do esquema.

## Esquema -> placa

`MPSchNets` une pinos tocados por fios (inclusive no meio de um segmento: juncao em T), pinos
encostados, rotulos sobre pinos/fios e rotulos com o mesmo nome (GND, VCC...). `MPConvertToPCB`
cria um componente por parte que ainda nao existe na placa (mesma referencia; os novos ficam em
fileiras), troca o footprint se mudou, copia o valor e recria `Doc.Wires` a partir das redes.
Trilhas desenhadas sao mantidas. O mapa pino->pad fica em cada simbolo (diodo e LED: pad 1 e o
catodo; DIL: indice = numero do pino - 1).
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
  lida de volta pelos leitores do LaserPCB, roteamento, DRC, BOM, selecao e
  copiar/colar, SMD, componentes do usuario, esquema (redes do 555 desenhado =
  redes da placa de exemplo) e copias na folha (2382 verificacoes).
- `tests/test_makepcb_ui` – exemplo, esquema e conversao, roteamento, DRC, todas
  as etapas e vistas, exportacao, copiar/colar, SMD, editor de componentes e
  dialogo de impressao; `--shots <pasta>` salva capturas (Linux/X11).

## Proximos passos

- Simbolos do usuario (editor de simbolo) e mais CIs com pinagem nomeada.
- Anotacao reversa (placa -> esquema) e destaque cruzado da rede selecionada.
- Ampliar a biblioteca de componentes do MakePCB.
- Serigrafia de baixo para componentes virados.
