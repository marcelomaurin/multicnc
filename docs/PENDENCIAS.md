# Pendencias da suite (atualizado 08/10/2026)

Lista do que ficou aberto. Detalhes do LaserArt em
`laserart/docs/LASERART_PLANO.md`.

## MakeRouter (08/10/2026) - EM ANALISE
- Projeto + usinagem de madeira na CNC Router (referencia de fluxo: Vectric Aspire, sem
  copiar): material, desenho 2D, relevo, percursos (perfil, bolsao, furacao, V-Carve, 3D),
  simulacao e G-code para o MultiCNC.
- Zero virtual: G-code relativo a um ponto do material (9 pontos XY, Z topo ou mesa); o
  MultiCNC posiciona (Zero Workpiece + Frame). Contrato comum proposto em
  `docs/CONTRATO_GCODE.md` (linhas `; MS-DATUM/STOCK/BOUNDS`).
- Tela provisoria `bin\makerouter.exe` na bandeja e no MultiSuite (grupo Projetar).
- Decisoes D1-D6 (papel do MultiCAM, biblioteca de offset, emissor comum,
  vista 3D, escopo da 1a entrega) em `makerouter/docs/TAREFA.md`.

## RouterPCB (08/10/2026) - pronto, falta a maquina real
- Fecha o gap MakePCB -> RouterPCB -> MultiCNC (CNC Router): isolacao com fresa V,
  furacao por broca, recorte com pontes, nivelamento por sondagem (G38.2 + bilinear) e
  G-code GRBL com cabecalho `; RouterPCB -> MultiCNC (CNC Router)`. Reutiliza
  import/raster/CAM/drill do LaserPCB (`laserpcb_roles` compartilhado).
- Fases 0 a 6 feitas em 08/10: testes 246 + 22 checks (Linux e Win64), registro
  `stiRouterPCB` (11 ferramentas), bandeja e MultiSuite (Preparar), Central de Testes, CI
  `routerpcb-ci.yml`, botao "Abrir no RouterPCB" no MakePCB, MultiCNC reconhece o
  cabecalho, instalador `bin\setup_multcnc_003.exe` (15 aplicativos).
- Falta: teste na maquina (sondagem, isolacao em fenolite, furacao, recorte) e anotar os
  parametros em `routerpcb/docs/PARAMETROS.md`. Dupla face fica para depois.
- Andamento detalhado: `routerpcb/docs/TAREFA.md`.

## MakePCB (07/10/2026)
- Projeto de placas do zero no estilo PCB Wizard, na raiz: `makepcb/`.
  Galeria de componentes, editor (trilhas 45 graus, ligacoes, textos, areas
  de cobre, desfazer), vistas Normal / Mundo real / Sem componentes / Arte
  final, autoroteamento + DRC, lista de materiais e exemplo 555.
- Exporta Gerber + Excellon numa pasta `<nome>_gerber`; "Abrir no LaserPCB"
  passa a pasta e o LaserPCB importa tudo (`ImportFolder`).
- Registrado na suite (`stiMakePCB`), bandeja, instaladores e CI
  (`.github/workflows/makepcb-ci.yml`). `bin\makepcb.exe` (x64).
- 07/10 (tarde): esquematico com "Converter para a placa", selecao multipla e
  copiar/colar, SMD (montagem embaixo em face simples), editor de componentes
  com biblioteca pessoal e impressao 1:1 da arte final.
- Proximos: simbolos do usuario, anotacao reversa, biblioteca do MultiPCB.
  Ver `makepcb/docs/ARCHITECTURE.md`.

## LaserPCB (07/10/2026)
- Interface principal integrada com controles/icones da MultiSuite, camadas,
  placa/cobre/furos/trajetorias, posicionamento, CAM e validacao.
- SVG reutiliza o parser do LaserArt; Gerber/Excellon/raster/CAM conectados ao fluxo.
- Corrigidos Bottom destrutivo, caixas apos rotacao, parametros de exportacao,
  nesting com travas/keep-outs e recorte de CAM na placa. Compensacao apos escala.
- Testes de regressao e da UI nativa adicionados a LaserPCB CI.
- Furacao (07/10): biblioteca `laserpcb/src/drill`, etapa "5 Furar" (CNC Router,
  um arquivo por broca, pinos de registro) e processo "Marcar furos (laser)".
  MultiCNC abre a furacao em CNC Router. Detalhes em laserpcb/docs/FURACAO.md.
- Camadas (07/10): tabela "Cortes / Camadas" estilo LightBurn com varios processos
  no mesmo trabalho, paleta 00-29, previa colorida (Top vermelho, Bottom verde),
  reguas em mm e painel Saida com tempo estimado.
- Pendente: camera fisica, nesting por poligonos, persistencia completa da sessao
  (camadas e posicionamento num arquivo de projeto), campos numericos com setas
  e validacao do processo/material na maquina. Uso em laserpcb/README.md.

## LaserArt
- **Nova versao pronta** e com pasta propria na raiz: `laserart/`
  (`src/core`, `src/ui`, `src/app`, `tests`, `docs`). Nao depende mais do
  LaserPCB. Inclui SVG, texto, imagem, formas, 30 camadas, Teste de material,
  biblioteca de materiais, previa e Enviar ao MultiCNC.
- `bin\laserart.exe` e `laserart\src\app\laserart.exe` (x64) gerados.
- Registro da suite, Central de testes e scripts de build
  (`installer\windows\build_release.bat`, `installer/linux/build_release.sh`)
  apontam para `laserart/`.
- Falta: teste fim a fim na maquina/SimuCNC laser.
- **Apagar a copia antiga dentro de `laserpcb\`** (nao e mais usada):
  - `laserpcb\src\art\` (pasta inteira, so tem `laserart_*`)
  - `laserpcb\src\app\laserart*` (`laserart.exe`, `.ico`, `.lpi`, `.lpr`,
    `.manifest`, `.res`, `laserart_main.pas`, `laserart_calibrationform.pas`)
  - `laserpcb\src\ui\laserart_canvas.pas`, `laserart_editor.pas`,
    `laserart_widgets.pas`
  - `laserpcb\tests\test_laserart_output.*` e `test_calibration_matrix.*`
  - `laserpcb\docs\LASERART_PLANO.md` (hoje so aponta para a pasta nova)
  - `laserpcb\src\app\lib\i386-win32\laserart*` (cache de compilacao)
- `multisuite.exe` e `multisuite_tray.exe` antigos acham o LaserArt em
  `bin\`; recompilados, acham tambem em `laserart\src\app\`.

## SimuCNC
- Layout novo e 3D por equipamento (impressora/router/laser) em
  `src/simucnc/`.
- Dependencias resolvidas. `SimuCNC.exe` gerado em `bin\` e em
  `src\simucnc\`; tambem compila pelo Lazarus.
- `tests/test_simucnc_jog.lpr` ainda nao foi executado.

## MultiCNC
- Layout novo gravado; `bin\multicnc.exe` (x64) atualizado.
- `src/app/multicnc.exe` continua o antigo ate recompilar no Lazarus (o
  painel da bandeja abre esse primeiro).
- `tests/test_app.lpr` atualizado para `TSuiteButton`, mas ja travava antes
  (tenta conectar em porta serial real) - revisar o teste.
- Feito: abre o arquivo recebido em `--file` (ou 1o parametro). G-code do
  LaserArt (`; LaserArt` no cabecalho) seleciona CNC Laser, Pass count = 1 e
  override desligado. `bin\multicnc.exe` (x64) recompilado com isso.

## MultiSuite
- `multisuite.exe` precisa ser recompilado (correcao do launcher que acha as
  ferramentas na arvore de desenvolvimento).
- Abertos da analise inicial:
  1. Raiz da suite errada quando instalado (`..\..\..` a partir do exe):
     botao "Central de testes" e projeto demonstracao.
  2. Interface nao abre/salva `.msuite` e o `.lpr` nao le o arquivo passado
     pela associacao do instalador.
  3. Projeto demonstracao so existe em memoria (artefatos nao criados).
  4. Testes `multisuite/tests/*.lpr` sem `.lpi` (aparecem como MISSING);
     `test_context` e `test_launcher_paths` fora do catalogo.
  5. `Load` do workspace sem validacao de faixa; `|` no nome quebra o arquivo;
     `multisuite_project.pas` sem uso; etapas do workspace diferentes do menu;
     `AI_GUIDE.md` lista 8 ferramentas (falta MultiPhysics).

## MultiSuite Bandeja
- Feito (08/10): MakePCB na bandeja, instancia unica (segunda execucao so mostra o
  painel), incluida no `build_release.bat` e no `multisuite.iss` (atalho + "Iniciar
  com o Windows"). `bin\multisuite_tray.exe` (x64) atualizado.

## Instalador
- `bin\setup_multcnc_002.exe` (0.02): 14 aplicativos, incluindo Bandeja e SimuCNC.
- `bin\setup_multcnc_003.exe` (0.03, 08/10): 15 aplicativos, com o RouterPCB.
- `bin\multicnc.exe` recompilado em 08/10 (console de log + reconhece o RouterPCB),
  usando o clone publico de `marcelomaurin/chatgpt`.

## Geral
- Builds atuais da suite sao i386; os executaveis gerados nesta sessao
  (tray, MultiCNC) sao x64, como o instalador.
- Controles visuais comuns em `multisuite/src/core/multisuite_controls.pas`
  e icones em `multisuite_icons.pas` - usar nas demais ferramentas
  (MultiCAD, MultiPCB, MultiCAM, MultiSlicer, MultiPhysics, MultiAssembly,
  LaserPCB) para padronizar o visual.
