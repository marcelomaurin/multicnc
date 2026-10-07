# MakePCB – guia para agentes de IA

- Leia `ARCHITECTURE.md` antes de mudar algo. O nucleo (`src/core`, `src/export`,
  `src/route`) nao pode depender da LCL visual; so `src/ui` e `src/app` usam Forms.
- Unidades em mm, Y para cima, origem no canto inferior esquerdo (igual ao LaserPCB).
- Nomes dos arquivos exportados sao contrato com o LaserPCB (`DetectLayerRole`):
  nao mude sufixos (`-B_Cu.gbl`, `-Edge_Cuts.gm1`, `-PTH.drl`...).
- Toda mudanca de geometria precisa passar em `tests/test_makepcb` (le os arquivos
  de volta com os leitores do LaserPCB) e o visual em `tests/test_makepcb_ui --shots`.
- Visual: use `multisuite_controls`/`multisuite_icons` (TSuiteButton, TSuiteHeader,
  cores clSuite*). Painel direito de 336 px, campos de 290 px, barra lateral de 214 px.
- Labels com `#10` explicito: `WordWrap := False` (o GTK2 trava no word wrap).
- Novos IDs de ferramenta vao no FIM de `TSuiteToolID` (ordinais gravados em workspaces).
- SMD: use `PadOnLayer`/`IsSMD` em qualquer codigo que percorra pads (nunca suponha furo).
- O esquema e independente da placa: so `MPConvertToPCB` escreve na placa a partir dele.
- Testes de interface que abrem formularios modais nao podem usar ShowModal: crie o formulario e use Show.
